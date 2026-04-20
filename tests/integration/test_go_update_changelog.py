"""Integration test for update-changelog subcommand.

Builds the Docker image and runs `panora-versioning update-changelog` against
a seeded local git repo mounted at /workspace. The test:

  1. Seeds the repo + writes /tmp/scenario.env + /tmp/.versioning-merged.yml.
  2. Stages a CHANGELOG.md (or other files) so the subcommand has something to commit.
  3. Runs the binary.
  4. Asserts exit code, git log, flag file, AND log content.

Log assertions are the point — see references/integration-testing.md.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import textwrap
import uuid
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
IMAGE_TAG = os.environ.get("GO_CHANGELOG_IMAGE", "panora-versioning-pipe:go-changelog-test")
BINARY = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


@pytest.fixture(scope="module")
def changelog_image() -> str:
    result = subprocess.run(
        ["docker", "build", "-t", IMAGE_TAG, str(REPO_ROOT)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        pytest.fail(
            f"docker build failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return IMAGE_TAG


# ---------------------------------------------------------------------------
# Repo helpers
# ---------------------------------------------------------------------------

def _init_repo(workspace: Path) -> None:
    cmds = [
        ["git", "init", "--initial-branch=main"],
        ["git", "config", "user.email", "test@example.com"],
        ["git", "config", "user.name", "Test"],
    ]
    for c in cmds:
        subprocess.run(c, cwd=workspace, check=True, capture_output=True)

    (workspace / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial commit"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )


def _write_scenario_env(workspace: Path, scenario: str = "development_release") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "scenario.env").write_text(f"SCENARIO={scenario}\n")


def _write_next_version(workspace: Path, version: str = "v1.2.0") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "next_version.txt").write_text(f"{version}\n")


def _write_bump_type(workspace: Path, bump: str) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "bump_type.txt").write_text(f"{bump}\n")


def _write_config(workspace: Path) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    content = textwrap.dedent("""\
        commits:
          format: "conventional"
        version:
          components:
            major:
              enabled: true
              initial: 0
            patch:
              enabled: true
              initial: 0
          tag_prefix_v: true
        changelog:
          mode: "last_commit"
          use_emojis: false
          include_author: false
          include_commit_link: false
          include_ticket_link: false
        commit_types:
          - name: "feat"
            bump: "minor"
          - name: "feature"
            bump: "minor"
          - name: "fix"
            bump: "patch"
          - name: "security"
            bump: "patch"
          - name: "revert"
            bump: "patch"
          - name: "perf"
            bump: "patch"
          - name: "chore"
            bump: "none"
          - name: "docs"
            bump: "none"
          - name: "refactor"
            bump: "none"
          - name: "test"
            bump: "none"
          - name: "build"
            bump: "none"
          - name: "ci"
            bump: "none"
          - name: "style"
            bump: "none"
          - name: "breaking"
            bump: "major"
        validation:
          ignore_patterns:
            - "^Merge"
            - "^chore\\\\(release\\\\)"
    """)
    (tmp / ".versioning-merged.yml").write_text(content)


def _stage_changelog(workspace: Path) -> None:
    """Write a CHANGELOG.md and stage it with git add."""
    changelog = workspace / "CHANGELOG.md"
    changelog.write_text(textwrap.dedent("""\
        # Changelog

        ## v1.2.0

        ### Features

        - feat: add feature
    """))
    subprocess.run(
        ["git", "add", "CHANGELOG.md"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )


def _git_log_subject(workspace: Path) -> str:
    """Return the subject line of the most recent commit."""
    result = subprocess.run(
        ["git", "log", "-1", "--pretty=%s"],
        cwd=workspace,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _git_log_full(workspace: Path) -> str:
    """Return the full message of the most recent commit."""
    result = subprocess.run(
        ["git", "log", "-1", "--pretty=%B"],
        cwd=workspace,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _git_commit_count(workspace: Path) -> int:
    result = subprocess.run(
        ["git", "rev-list", "--count", "HEAD"],
        cwd=workspace,
        check=True,
        capture_output=True,
        text=True,
    )
    return int(result.stdout.strip())


def _run_update_changelog(
    image: str,
    workspace: Path,
    *,
    env_overrides: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    env_flags: list[str] = []
    if env_overrides:
        for k, v in env_overrides.items():
            env_flags += ["-e", f"{k}={v}"]

    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-v", f"{tmp_dir}:/tmp",
            "-w", "/workspace",
            "--entrypoint", BINARY,
            *env_flags,
            image,
            "update-changelog",
        ],
        capture_output=True,
        text=True,
    )


def _read_tmp(workspace: Path, filename: str) -> str:
    p = workspace / "tmp" / filename
    return p.read_text().strip() if p.exists() else ""


def _tmp_exists(workspace: Path, filename: str) -> bool:
    return (workspace / "tmp" / filename).exists()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestUpdateChangelogBranchContext:
    """Staged CHANGELOG.md → committed with chore(release) message + skip ci."""

    def test_exit_code(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _stage_changelog(workspace)
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        result = _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_commit_created(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _stage_changelog(workspace)
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        subject = _git_log_subject(workspace)
        assert "chore(release)" in subject, (
            f"expected 'chore(release)' in commit subject, got: {subject!r}"
        )

    def test_flag_file_written(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _stage_changelog(workspace)
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        assert _tmp_exists(workspace, "changelog_committed.flag"), (
            "/tmp/changelog_committed.flag was not written after successful commit"
        )

    def test_commit_message_format(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _stage_changelog(workspace)
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        full_msg = _git_log_full(workspace)
        assert "chore(release): update CHANGELOG for version v1.2.0 (minor bump)" in full_msg, (
            f"commit message does not match expected format:\n{full_msg}"
        )
        assert "skip ci" in full_msg, (
            f"'skip ci' marker missing from commit message:\n{full_msg}"
        )

    def test_logs_show_staging_and_commit(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _stage_changelog(workspace)
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        result = _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        stdout = result.stdout.lower()
        assert "changelog" in stdout, f"'changelog' missing from logs:\n{result.stdout}"
        assert "commit" in stdout, f"'commit' missing from logs:\n{result.stdout}"


class TestUpdateChangelogNoChanges:
    """No staged files → exit 0 without creating a new commit."""

    def test_no_changes_exits_0(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        # deliberately do not stage anything
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        result = _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        assert result.returncode == 0, (
            f"expected exit 0 when nothing staged, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_no_changes_no_new_commit(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        count_before = _git_commit_count(workspace)
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        count_after = _git_commit_count(workspace)
        assert count_after == count_before, (
            f"a new commit was created even though nothing was staged "
            f"(before={count_before}, after={count_after})"
        )


class TestUpdateChangelogScenarioSkip:
    """Non-release scenarios must exit 0 without committing."""

    def test_pull_request_scenario_skips(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _stage_changelog(workspace)
        count_before = _git_commit_count(workspace)
        _write_scenario_env(workspace, scenario="pull_request")
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        result = _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        assert result.returncode == 0, (
            f"expected exit 0 for pull_request scenario, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        count_after = _git_commit_count(workspace)
        assert count_after == count_before, (
            f"a commit was created for pull_request scenario "
            f"(before={count_before}, after={count_after})"
        )


class TestUpdateChangelogPerFolderChangelogs:
    """Per-folder CHANGELOGs listed in /tmp/per_folder_changelogs.txt are committed."""

    def test_per_folder_changelogs_staged(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)

        # Create a folder changelog in the workspace and stage it
        api_dir = workspace / "services" / "api"
        api_dir.mkdir(parents=True)
        api_changelog = api_dir / "CHANGELOG.md"
        api_changelog.write_text(textwrap.dedent("""\
            # Changelog

            ## v1.2.0

            ### Features

            - feat(api): add endpoint
        """))
        subprocess.run(
            ["git", "add", "services/api/CHANGELOG.md"],
            cwd=workspace,
            check=True,
            capture_output=True,
        )

        # Write per_folder_changelogs.txt pointing at the staged file
        tmp = workspace / "tmp"
        tmp.mkdir(exist_ok=True)
        (tmp / "per_folder_changelogs.txt").write_text("/workspace/services/api/CHANGELOG.md\n")

        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_bump_type(workspace, "minor")
        _write_config(workspace)

        result = _run_update_changelog(
            changelog_image,
            workspace,
            env_overrides={"VERSIONING_BRANCH": "feature/test"},
        )
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        subject = _git_log_subject(workspace)
        assert "chore(release)" in subject, (
            f"expected 'chore(release)' in commit subject after per-folder stage, got: {subject!r}"
        )
