"""GitHub integration tests for panora-versioning-pipe.

Each test scenario:
1. Creates a branch in the test repo
2. Pushes commits with specific messages
3. Creates a PR to main
4. Waits for PR checks (pr-versioning.yml)
5. Optionally merges and verifies tag creation
6. Cleans up (branch, tag)

IMPORTANT: These tests MUST run sequentially (not parallel) because they merge
to main and need to wait for the tag-on-merge workflow between each merge.
Use: pytest -v test_github.py -x (stop on first failure)
"""

import re
import time

import pytest

from conftest import load_scenarios, scenario_ids


SCENARIOS = load_scenarios()

# Separate scenarios that merge (create tags) from those that don't
MERGE_SCENARIOS = [s for s in SCENARIOS if s["expected"].get("tag_created", False)]
NO_MERGE_SCENARIOS = [s for s in SCENARIOS if not s["expected"].get("tag_created", False)]


class TestPRValidation:
    """Tests that only create PRs and check validation — no merge needed."""

    @pytest.mark.parametrize("scenario", NO_MERGE_SCENARIOS,
                             ids=scenario_ids(NO_MERGE_SCENARIOS))
    def test_pr_check(self, github, run_id, scenario):
        branch_prefix = scenario.get("branch_prefix", "test/auto")
        branch = f"{branch_prefix}-{scenario['name']}-{run_id}"
        pr_title = scenario.get("pr_title", f"test: {scenario['name']}")
        pr_number = None

        try:
            github.create_branch(branch)

            config_override = scenario.get("config_override")
            commits = scenario["commits"]
            for idx, commit in enumerate(commits):
                files = dict(commit.get("files", {"test-artifact.txt": "test"}))
                if config_override and idx == 0:
                    import yaml
                    files[".versioning.yml"] = yaml.safe_dump(
                        config_override, default_flow_style=False, sort_keys=False
                    )
                github.create_commit(
                    branch=branch,
                    message=commit["message"],
                    files=files,
                )

            pr = github.create_pr(head=branch, base="main", title=pr_title)
            pr_number = pr["number"]

            check_result = github.wait_for_checks(pr_number)
            expected = scenario["expected"]["pr_check"]
            assert check_result == expected, (
                f"Expected PR check '{expected}', got '{check_result}'"
            )

        finally:
            if pr_number is not None:
                github.close_pr(pr_number)
            github.delete_branch(branch)


class TestMergeAndTag:
    """Tests that merge PRs and verify tag creation.

    These run sequentially — each test waits for the tag-on-merge workflow
    to complete before the next one starts.
    """

    @pytest.mark.parametrize("scenario", MERGE_SCENARIOS,
                             ids=scenario_ids(MERGE_SCENARIOS))
    def test_merge_creates_tag(self, github, run_id, scenario):
        # Scenarios may override the branch prefix (e.g. hotfix scenarios need
        # the hotfix/ prefix so PR-context detection routes correctly) and the
        # PR title (squash merges take the PR title as the commit subject,
        # which drives branch-context hotfix detection).
        branch_prefix = scenario.get("branch_prefix", "test/auto")
        branch = f"{branch_prefix}-{scenario['name']}-{run_id}"
        pr_title = scenario.get("pr_title", f"test: {scenario['name']}")
        pr_number = None
        created_tag = None

        try:
            # 1. Create branch and commits
            github.create_branch(branch)

            # Apply config_override by injecting .versioning.yml into the FIRST
            # scenario commit. The pipe reads the working-tree config at
            # run time, so committing the override on the branch is enough.
            config_override = scenario.get("config_override")
            commits = scenario["commits"]
            for idx, commit in enumerate(commits):
                files = dict(commit.get("files", {"test-artifact.txt": "test"}))
                if config_override and idx == 0:
                    import yaml
                    files[".versioning.yml"] = yaml.safe_dump(
                        config_override, default_flow_style=False, sort_keys=False
                    )
                github.create_commit(
                    branch=branch,
                    message=commit["message"],
                    files=files,
                )

            # 2. Create PR and wait for checks
            pr = github.create_pr(head=branch, base="main", title=pr_title)
            pr_number = pr["number"]

            check_result = github.wait_for_checks(pr_number)
            assert check_result == "pass", (
                f"PR check should pass but got '{check_result}'"
            )

            # 3. Record state before merge
            tag_before = github.get_latest_tag()
            run_before = github.get_latest_workflow_run_id()

            # 4. Merge PR (use scenario's merge_method, default squash)
            merge_method = scenario.get("merge_method", "squash")
            github.merge_pr(pr_number, method=merge_method)
            pr_number = None  # merged

            # 5. Wait for NEW tag-on-merge workflow to start and complete
            #    GitHub may not trigger the workflow if the previous push was
            #    a CHANGELOG *.md commit (paths-ignore race). If no new run
            #    appears within 30s, manually dispatch it.
            time.sleep(10)
            try:
                github.wait_for_tag_workflow(
                    previous_run_id=run_before, timeout=45,
                )
            except TimeoutError:
                # Workflow didn't trigger — dispatch manually
                github.dispatch_tag_workflow()
                time.sleep(5)
                github.wait_for_tag_workflow(
                    previous_run_id=run_before, timeout=180,
                )

            # 6. Wait for new tag (raises TimeoutError if none appears)
            tag_after = github.wait_for_new_tag(tag_before, timeout=90)
            created_tag = tag_after

            # 7. Verify tag pattern
            if "tag_pattern" in scenario["expected"]:
                pattern = scenario["expected"]["tag_pattern"]
                assert re.match(pattern, tag_after), (
                    f"Tag '{tag_after}' doesn't match '{pattern}'"
                )

            # 8. Verify changelog
            if "changelog_contains" in scenario["expected"]:
                # Give the CHANGELOG commit time to land
                time.sleep(3)
                changelog_path = scenario["expected"].get(
                    "changelog_location", "CHANGELOG.md"
                )
                content = github.get_file_content(changelog_path)
                assert content is not None, f"{changelog_path} not found"
                # Squash merge may rewrite commit messages (e.g., adding PR #).
                # Extract the key part of the expected text for a flexible match.
                expected = scenario["expected"]["changelog_contains"]
                # Strip type prefix for matching — CHANGELOG uses **type**: msg format
                key_part = expected.split(": ", 1)[-1] if ": " in expected else expected
                assert key_part in content, (
                    f"Expected '{key_part}' not found in {changelog_path}"
                )

            # 9. Verify CHANGELOG section marker (e.g. "(Hotfix)" for hotfix releases)
            if "changelog_section_marker" in scenario["expected"]:
                marker = scenario["expected"]["changelog_section_marker"]
                changelog_path = scenario["expected"].get(
                    "changelog_location", "CHANGELOG.md"
                )
                content = github.get_file_content(changelog_path)
                assert content is not None, f"{changelog_path} not found"
                assert marker in content, (
                    f"Expected marker '{marker}' not found in {changelog_path}"
                )

        finally:
            if pr_number is not None:
                github.close_pr(pr_number)
            github.delete_branch(branch)
            if created_tag:
                github.delete_tag(created_tag)

            # Wait between merge scenarios to avoid workflow race conditions
            time.sleep(10)
