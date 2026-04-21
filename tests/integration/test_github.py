"""GitHub integration tests for panora-versioning-pipe.

Each test scenario:
1. Creates a branch in the test repo (forked from the scenario's sandbox branch)
2. Pushes commits with specific messages
3. Creates a PR to the sandbox branch
4. Waits for PR checks (pr-versioning.yml)
5. Optionally merges and verifies tag creation
6. Cleans up (branch, tag)
"""

import re
import time

import pytest

from conftest import deep_merge, load_scenarios, sandbox_major, scenario_ids


SCENARIOS = load_scenarios()

# Separate scenarios that merge from those that don't.
# A scenario merges when tag_created=true (normal) OR when merge=true is
# declared explicitly (e.g. guardrail scenarios that merge but expect no tag).
MERGE_SCENARIOS = [
    s for s in SCENARIOS
    if s["expected"].get("tag_created", False) or s.get("merge", False)
]
NO_MERGE_SCENARIOS = [s for s in SCENARIOS if s not in MERGE_SCENARIOS]


class TestPRValidation:
    """Tests that only create PRs and check validation — no merge needed."""

    @pytest.mark.parametrize("scenario", NO_MERGE_SCENARIOS,
                             ids=scenario_ids(NO_MERGE_SCENARIOS))
    def test_pr_check(self, github, run_id, scenario):
        branch_prefix = scenario.get("branch_prefix", "test/auto")
        branch = f"{branch_prefix}-{scenario['name']}-{run_id}"
        pr_title = scenario.get("pr_title", f"test: {scenario['name']}")
        # PR-only scenarios always target main (no sandbox isolation needed —
        # they never merge, so no tag collision risk exists)
        pr_base = scenario.get("base", "main")
        pr_number = None
        seeded_tags: list[str] = []

        try:
            # Seed tags declared by the scenario before creating the branch.
            # These simulate pre-existing tags in the sandbox namespace so that
            # guardrail scenarios can test against a known latest tag.
            # Created on the sandbox ref; cleaned up in finally regardless of outcome.
            for tag_name in scenario.get("seed_tags", []):
                github.create_tag(tag_name, ref=pr_base)
                seeded_tags.append(tag_name)

            github.create_branch(branch, from_ref=pr_base)

            config_override = scenario.get("config_override")
            commits = scenario["commits"]
            for idx, commit in enumerate(commits):
                files = dict(commit.get("files", {"test-artifact.txt": "test"}))
                if config_override and idx == 0:
                    import yaml
                    current_raw = github.get_file_content(
                        ".versioning.yml", ref=pr_base,
                    )
                    base_cfg = yaml.safe_load(current_raw) if current_raw else {}
                    merged = deep_merge(base_cfg, config_override)
                    files[".versioning.yml"] = yaml.safe_dump(
                        merged, default_flow_style=False, sort_keys=False,
                    )
                github.create_commit(
                    branch=branch,
                    message=commit["message"],
                    files=files,
                )

            pr = github.create_pr(head=branch, base=pr_base, title=pr_title)
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
            for tag_name in seeded_tags:
                github.delete_tag(tag_name)


class TestMergeAndTag:
    """Tests that merge PRs and verify tag creation.

    Runs in parallel via pytest-xdist (-n auto). Each scenario targets its own
    sandbox branch, giving it a disjoint tag namespace (vN.*). No shared
    mutable state between scenarios.
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

        # Derive sandbox routing — every merge scenario has a base sandbox
        base = scenario.get("base", "main")
        major = sandbox_major(base)
        tag_prefix = scenario.get("tag_prefix_override") or (f"v{major}." if major else None)

        pr_number = None
        created_tag = None
        tag_before = None
        seeded_tags: list[str] = []

        try:
            # Seed tags declared by the scenario before creating the branch.
            for tag_name in scenario.get("seed_tags", []):
                github.create_tag(tag_name, ref=base)
                seeded_tags.append(tag_name)

            # 1. Create branch forked from the scenario's sandbox (not main)
            github.create_branch(branch, from_ref=base)

            # Apply config_override by injecting .versioning.yml into the FIRST
            # scenario commit. The pipe reads the working-tree config at
            # run time, so committing the override on the branch is enough.
            # CRITICAL: read the base config from the sandbox ref, not main.
            config_override = scenario.get("config_override")
            commits = scenario["commits"]
            for idx, commit in enumerate(commits):
                files = dict(commit.get("files", {"test-artifact.txt": "test"}))
                # Append run_id to every non-config file so the squash merge
                # always produces a non-empty diff even when sandboxes already
                # contain the file from a previous run with the same content.
                files = {
                    k: (v + f"\n# run:{run_id}" if k != ".versioning.yml" else v)
                    for k, v in files.items()
                }
                if config_override and idx == 0:
                    import yaml
                    current_raw = github.get_file_content(
                        ".versioning.yml", ref=base,
                    )
                    base_cfg = yaml.safe_load(current_raw) if current_raw else {}
                    merged = deep_merge(base_cfg, config_override)
                    files[".versioning.yml"] = yaml.safe_dump(
                        merged, default_flow_style=False, sort_keys=False,
                    )
                github.create_commit(
                    branch=branch,
                    message=commit["message"],
                    files=files,
                )

            # 2. Create PR targeting the sandbox branch and wait for checks
            pr = github.create_pr(head=branch, base=base, title=pr_title)
            pr_number = pr["number"]

            check_result = github.wait_for_checks(pr_number)
            assert check_result == "pass", (
                f"PR check should pass but got '{check_result}'"
            )

            # 3. Record state before merge (scoped to this sandbox's branch)
            tag_before = github.get_latest_tag(prefix=tag_prefix)
            run_before = github.get_latest_workflow_run_id(branch=base)

            # 4. Merge PR (use scenario's merge_method, default squash)
            merge_method = scenario.get("merge_method", "squash")
            merge_subject = scenario.get("merge_subject")
            github.merge_pr(pr_number, method=merge_method, subject=merge_subject)
            pr_number = None  # merged

            # 5. Wait for NEW tag-on-merge workflow to start and complete.
            #    GitHub may not trigger the workflow if the previous push was
            #    a CHANGELOG *.md commit (paths-ignore race). If no new run
            #    appears within 30s, manually dispatch it.
            #    The ~10s sleep is for push-event propagation — kept per-sandbox.
            image_tag = scenario.get("image_tag")
            time.sleep(10)
            run_id_after = github.wait_for_new_workflow_run(
                previous_run_id=run_before, timeout=45, branch=base,
            )
            if run_id_after is None:
                # Push event didn't trigger a new run — dispatch manually
                github.dispatch_tag_workflow(image_tag=image_tag, ref=base)
                time.sleep(5)
                run_id_after = github.wait_for_new_workflow_run(
                    previous_run_id=run_before, timeout=60, branch=base,
                )
            # Wait for the detected run to complete (up to 180s regardless of
            # how it was triggered — push or dispatch)
            github.wait_for_workflow_run_completion(
                run_id=run_id_after, timeout=180,
            )

            # 6. Verify tag outcome — scenarios that merge but expect no tag (e.g.
            #    guardrail blocks emission) wait for the workflow to complete then
            #    assert no new tag appeared. Normal merge scenarios wait for a tag.
            tag_after = None
            if scenario["expected"].get("tag_created", True):
                tag_after = github.wait_for_new_tag(tag_before, timeout=180,
                                                    prefix=tag_prefix)
                created_tag = tag_after
            else:
                # Guardrail or other block: workflow ran but must not have pushed a tag.
                time.sleep(15)
                latest_now = github.get_latest_tag(prefix=tag_prefix)
                assert latest_now == tag_before, (
                    f"Expected no new tag (guardrail should block) but found "
                    f"'{latest_now}' (was '{tag_before}')"
                )

            # 7. Verify tag pattern
            if tag_after and "tag_pattern" in scenario["expected"]:
                pattern = scenario["expected"]["tag_pattern"]
                assert re.match(pattern, tag_after), (
                    f"Tag '{tag_after}' doesn't match '{pattern}'"
                )

            # 8. Verify changelog (primary location)
            if "changelog_contains" in scenario["expected"]:
                # Give the CHANGELOG commit time to land
                time.sleep(3)
                changelog_path = scenario["expected"].get(
                    "changelog_location", "CHANGELOG.md"
                )
                content = github.get_file_content(changelog_path, ref=base)
                assert content is not None, f"{changelog_path} not found on {base}"
                # Squash merge may rewrite commit messages (e.g., adding PR #).
                # Extract the key part of the expected text for a flexible match.
                expected_text = scenario["expected"]["changelog_contains"]
                # Strip type prefix for matching — CHANGELOG uses **type**: msg format
                key_part = (expected_text.split(": ", 1)[-1]
                            if ": " in expected_text else expected_text)
                assert key_part in content, (
                    f"Expected '{key_part}' not found in {changelog_path} on {base}"
                )

            # 8b. Verify additional changelog locations (e.g. multi-folder write)
            if "changelog_locations" in scenario["expected"]:
                expected_text = scenario["expected"]["changelog_contains"]
                key_part = (expected_text.split(": ", 1)[-1]
                            if ": " in expected_text else expected_text)
                for extra_path in scenario["expected"]["changelog_locations"]:
                    extra_content = github.get_file_content(extra_path, ref=base)
                    assert extra_content is not None, (
                        f"{extra_path} not found on {base}"
                    )
                    assert key_part in extra_content, (
                        f"Expected '{key_part}' not found in {extra_path} on {base}"
                    )

            # 8c. Verify changelog NOT in forbidden locations
            if "changelog_not_locations" in scenario["expected"]:
                expected_text = scenario["expected"]["changelog_contains"]
                key_part = (expected_text.split(": ", 1)[-1]
                            if ": " in expected_text else expected_text)
                for forbidden_path in scenario["expected"]["changelog_not_locations"]:
                    forbidden_content = github.get_file_content(forbidden_path, ref=base)
                    if forbidden_content is not None:
                        assert key_part not in forbidden_content, (
                            f"Text '{key_part}' should NOT appear in {forbidden_path} "
                            f"on {base} but was found"
                        )

            # 9. Verify CHANGELOG section marker (e.g. "(Hotfix)" for hotfix releases)
            if "changelog_section_marker" in scenario["expected"]:
                marker = scenario["expected"]["changelog_section_marker"]
                changelog_path = scenario["expected"].get(
                    "changelog_location", "CHANGELOG.md"
                )
                content = github.get_file_content(changelog_path, ref=base)
                assert content is not None, f"{changelog_path} not found on {base}"
                assert marker in content, (
                    f"Expected marker '{marker}' not found in {changelog_path} on {base}"
                )

            # 10. Verify version file update (version_file.groups scenarios)
            if "version_file_path" in scenario["expected"]:
                vf_path = scenario["expected"]["version_file_path"]
                vf_updated = scenario["expected"].get("version_file_updated", False)
                if vf_updated:
                    # Poll until the version file reflects the new version —
                    # the CHANGELOG commit (which includes the version file) may
                    # take a few seconds to land on the remote after the tag appears.
                    version_plain = tag_after.lstrip("v")
                    deadline = time.time() + 30
                    vf_content = None
                    while time.time() < deadline:
                        vf_content = github.get_file_content(vf_path, ref=base)
                        if vf_content and version_plain in vf_content:
                            break
                        time.sleep(3)
                    assert vf_content is not None, (
                        f"version file {vf_path} not found on {base} — expected update"
                    )
                    assert version_plain in vf_content, (
                        f"Expected version '{version_plain}' not found in version file "
                        f"{vf_path} on {base}"
                    )
                else:
                    # File may not exist OR must not contain the new tag
                    vf_content = github.get_file_content(vf_path, ref=base)
                    if vf_content is not None:
                        assert tag_after not in vf_content, (
                            f"Tag '{tag_after}' unexpectedly found in version file "
                            f"{vf_path} on {base} (trigger_paths should NOT have matched)"
                        )

        finally:
            if pr_number is not None:
                github.close_pr(pr_number)
            github.delete_branch(branch)
            for tag_name in seeded_tags:
                github.delete_tag(tag_name)
            if created_tag:
                github.delete_tag(created_tag)
            else:
                # Test may have failed before created_tag was set, but the pipe
                # might have already pushed a tag to the sandbox. Clean it up.
                latest = github.get_latest_tag(prefix=tag_prefix)
                if latest and latest != tag_before:
                    github.delete_tag(latest)
