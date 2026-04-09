"""Bitbucket integration tests for panora-versioning-pipe.

Each test scenario:
1. Creates a branch in the Bitbucket test repo
2. Pushes commits with specific messages via REST API
3. Creates a PR to main
4. Waits for pipeline status (bitbucket-pipelines.yml)
5. Optionally merges and verifies tag creation
6. Cleans up (branch, tag)

IMPORTANT: These tests MUST run sequentially (not parallel) because they merge
to main and need to wait for the branch pipeline between each merge.
Use: pytest -v test_bitbucket.py -x (stop on first failure)
"""

import re
import time

import pytest
import yaml

from conftest import load_scenarios, scenario_ids


SCENARIOS = load_scenarios()

# Separate scenarios that merge (create tags) from those that don't
MERGE_SCENARIOS = [s for s in SCENARIOS if s["expected"].get("tag_created", False)]
NO_MERGE_SCENARIOS = [s for s in SCENARIOS if not s["expected"].get("tag_created", False)]


class TestPRValidation:
    """Tests that only create PRs and check pipeline status — no merge needed."""

    @pytest.mark.parametrize("scenario", NO_MERGE_SCENARIOS,
                             ids=scenario_ids(NO_MERGE_SCENARIOS))
    def test_pr_check(self, bitbucket, run_id, scenario):
        branch = f"test/auto-{scenario['name']}-{run_id}"
        pr_number = None

        try:
            bitbucket.create_branch(branch)

            # If config_override, push .versioning.yml first
            if "config_override" in scenario:
                bitbucket.create_commit(
                    branch=branch,
                    message="chore: set test config",
                    files={".versioning.yml": yaml.dump(scenario["config_override"])},
                )

            for commit in scenario["commits"]:
                bitbucket.create_commit(
                    branch=branch,
                    message=commit["message"],
                    files=commit.get("files", {"test-artifact.txt": "test"}),
                )

            pr = bitbucket.create_pr(head=branch, base="main",
                                     title=f"test: {scenario['name']}")
            pr_number = pr["number"]

            check_result = bitbucket.wait_for_checks(pr_number)
            expected = scenario["expected"]["pr_check"]
            assert check_result == expected, (
                f"Expected PR check '{expected}', got '{check_result}'"
            )

        finally:
            if pr_number is not None:
                bitbucket.close_pr(pr_number)
            bitbucket.delete_branch(branch)


class TestMergeAndTag:
    """Tests that merge PRs and verify tag creation.

    These run sequentially — each test waits for the branch pipeline
    to complete before the next one starts.
    """

    @pytest.mark.parametrize("scenario", MERGE_SCENARIOS,
                             ids=scenario_ids(MERGE_SCENARIOS))
    def test_merge_creates_tag(self, bitbucket, run_id, scenario):
        branch = f"test/auto-{scenario['name']}-{run_id}"
        pr_number = None
        created_tag = None

        try:
            # 1. Create branch and commits
            bitbucket.create_branch(branch)

            # If config_override, push .versioning.yml first
            if "config_override" in scenario:
                bitbucket.create_commit(
                    branch=branch,
                    message="chore: set test config",
                    files={".versioning.yml": yaml.dump(scenario["config_override"])},
                )

            for commit in scenario["commits"]:
                bitbucket.create_commit(
                    branch=branch,
                    message=commit["message"],
                    files=commit.get("files", {"test-artifact.txt": "test"}),
                )

            # 2. Create PR and wait for checks
            pr = bitbucket.create_pr(head=branch, base="main",
                                     title=f"test: {scenario['name']}")
            pr_number = pr["number"]

            check_result = bitbucket.wait_for_checks(pr_number)
            assert check_result == "pass", (
                f"PR check should pass but got '{check_result}'"
            )

            # 3. Record state before merge
            tag_before = bitbucket.get_latest_tag()
            pipeline_before = bitbucket.get_latest_pipeline()
            pipeline_uuid_before = pipeline_before["uuid"] if pipeline_before else None

            # 4. Merge PR (use scenario's merge_method, default squash)
            #    For squash merges, pass the last commit's message explicitly.
            #    Bitbucket defaults to "Merged in branch (pull request #N)"
            #    which loses the conventional commit subject that the pipe needs.
            merge_method = scenario.get("merge_method", "squash")
            merge_msg = None
            if merge_method == "squash":
                merge_msg = scenario["commits"][-1]["message"]
            bitbucket.merge_pr(pr_number, method=merge_method, message=merge_msg)
            pr_number = None  # merged — don't close in finally

            # 5. Wait for the branch pipeline (main push) to complete
            time.sleep(10)
            bitbucket.wait_for_main_pipeline(
                previous_uuid=pipeline_uuid_before, timeout=180,
            )

            # 6. Wait for new tag (raises TimeoutError if none appears)
            tag_after = bitbucket.wait_for_new_tag(tag_before, timeout=90)
            created_tag = tag_after

            # 7. Verify tag pattern
            if "tag_pattern" in scenario["expected"]:
                pattern = scenario["expected"]["tag_pattern"]
                assert re.match(pattern, tag_after), (
                    f"Tag '{tag_after}' doesn't match '{pattern}'"
                )

            # 8. Verify changelog
            if "changelog_contains" in scenario["expected"]:
                # Give the CHANGELOG commit time to propagate
                time.sleep(3)
                changelog_path = scenario["expected"].get(
                    "changelog_location", "CHANGELOG.md"
                )
                content = bitbucket.get_file_content(changelog_path)
                assert content is not None, f"{changelog_path} not found"
                # Squash merge may rewrite commit messages (e.g., adding PR #).
                # Extract the key part of the expected text for a flexible match.
                expected = scenario["expected"]["changelog_contains"]
                key_part = expected.split(": ", 1)[-1] if ": " in expected else expected
                assert key_part in content, (
                    f"Expected '{key_part}' not found in {changelog_path}"
                )

        finally:
            if pr_number is not None:
                bitbucket.close_pr(pr_number)
            bitbucket.delete_branch(branch)
            if created_tag:
                bitbucket.delete_tag(created_tag)

            # Wait between merge scenarios to avoid pipeline race conditions
            time.sleep(10)
