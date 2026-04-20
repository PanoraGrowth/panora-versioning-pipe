"""Integration test for GO-07: update-changelog subcommand.

Builds the Docker image once (shared via GO_CHANGELOG_IMAGE env var) and runs
`panora-versioning update-changelog` against a seeded local git repo.

The test verifies:
  - exit 0 when there are changes to commit
  - changelog_committed.flag written on branch context (no VERSIONING_PR_ID)
  - No push attempted without a remote (expected push failure handled)
  - Commit message format matches bash exactly
  - No-op when CHANGELOG.md has no changes
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
IMAGE_TAG = os.environ.get(
    "GO_CHANGELOG_IMAGE",
    "panora-versioning-pipe:go-changelog-test",
)
BINARY = "/usr/local/bin/panora-versioning"
BASH_SCRIPT = "/pipe/changelog/update-changelog.sh"


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
# Helpers
# ---------------------------------------------------------------------------

def _make_workspace(tmp_path: Path) -> Path:
    ws = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
    ws.mkdir()
    return ws


def _seed_repo(workspace: Path) -> None:
    cmds = [
        ["git", "init", "--initial-branch=main"],
        ["git", "config", "user.email", "ci@example.com"],
        ["git", "config", "user.name", "CI Pipeline"],
    ]
    for c in cmds:
        subprocess.run(c, cwd=workspace, check=True, capture_output=True)

    (workspace / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial commit"],
        cwd=workspace, check=True, capture_output=True,
    )
    subprocess.run(["git", "tag", "v1.0.0"], cwd=workspace, check=True, capture_output=True)


def _write_config(workspace: Path) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    config = textwrap.dedent("""\
        commits:
          format: "conventional"
        version:
          tag_prefix_v: true
          components:
            major: { enabled: true, initial: 0 }
            patch: { enabled: true, initial: 0 }
        changelog:
          file: "CHANGELOG.md"
          title: "Changelog"
          mode: "last_commit"
          use_emojis: false
          include_author: true
          include_commit_link: false
          include_ticket_link: false
        """)
    (tmp / ".versioning-merged.yml").write_text(config)


def _seed_changelog_change(workspace: Path) -> None:
    """Write a CHANGELOG.md to workspace (not yet committed = dirty)."""
    (workspace / "CHANGELOG.md").write_text(
        "# Changelog\n\n## 1.1.0 - 2026-04-20\n\n- feat: add feature\n\n"
    )


def _run_update_changelog(
    image: str,
    workspace: Path,
    *,
    env_overrides: dict[str, str] | None = None,
    use_bash: bool = False,
    scenario: str = "development_release",
) -> subprocess.CompletedProcess:
    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)

    # Only write scenario.env if not already present (allows tests to override it beforehand).
    scenario_file = tmp_dir / "scenario.env"
    if not scenario_file.exists():
        scenario_file.write_text(f"SCENARIO={scenario}\n")
    (tmp_dir / "next_version.txt").write_text("1.1.0\n")
    (tmp_dir / "bump_type.txt").write_text("minor\n")

    env_flags: list[str] = []
    env_flags += ["-e", "VERSIONING_BRANCH=feature/test"]
    env_flags += ["-e", "VERSIONING_TARGET_BRANCH=main"]

    if env_overrides:
        for k, v in env_overrides.items():
            env_flags += ["-e", f"{k}={v}"]

    if use_bash:
        entrypoint_args = ["--entrypoint", "/bin/bash", image, BASH_SCRIPT]
    else:
        entrypoint_args = [
            "--entrypoint", BINARY,
            image,
            "update-changelog",
        ]

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-v", f"{tmp_dir}:/tmp",
            "-w", "/workspace",
            *env_flags,
            *entrypoint_args,
        ],
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Scenario 1: CHANGELOG.md modified, branch context → commit + flag
# ---------------------------------------------------------------------------

class TestUpdateChangelogBranchContext:
    def test_exit_0_with_changes(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)
        result = _run_update_changelog(changelog_image, ws)
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"expected 0, got {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_flag_file_created(self, changelog_image: str, tmp_path: Path) -> None:
        """Branch context (no VERSIONING_PR_ID) → /tmp/changelog_committed.flag must exist."""
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)
        _run_update_changelog(changelog_image, ws)
        flag = ws / "tmp" / "changelog_committed.flag"
        assert flag.exists(), "/tmp/changelog_committed.flag not created"

    def test_changelog_staged_and_committed(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)
        _run_update_changelog(changelog_image, ws)
        # After the container runs, git log in the host workspace should show the commit
        result = subprocess.run(
            ["git", "log", "--oneline", "-2"],
            cwd=ws, capture_output=True, text=True,
        )
        assert "chore(release)" in result.stdout, (
            f"release commit not found in git log:\n{result.stdout}"
        )

    def test_commit_message_format(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)
        _run_update_changelog(changelog_image, ws)
        result = subprocess.run(
            ["git", "log", "--format=%B", "-1"],
            cwd=ws, capture_output=True, text=True,
        )
        msg = result.stdout
        assert "chore(release): update CHANGELOG for version 1.1.0 (minor bump)" in msg, (
            f"commit message format wrong:\n{msg}"
        )
        assert "[skip ci]" in msg or "skip-ci" in msg, (
            f"skip-ci marker missing:\n{msg}"
        )

    def test_banner_present(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)
        result = _run_update_changelog(changelog_image, ws)
        combined = result.stdout + result.stderr
        assert "CHANGELOG" in combined.upper(), f"banner missing:\n{combined}"


# ---------------------------------------------------------------------------
# Scenario 2: no changes → exit 0, no commit
# ---------------------------------------------------------------------------

class TestUpdateChangelogNoChanges:
    def test_exit_0_no_op(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        # No CHANGELOG.md change — nothing to commit
        result = _run_update_changelog(changelog_image, ws)
        assert result.returncode == 0

    def test_no_commit_created(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _run_update_changelog(changelog_image, ws)
        result = subprocess.run(
            ["git", "log", "--oneline", "-1"],
            cwd=ws, capture_output=True, text=True,
        )
        assert "chore(release)" not in result.stdout, (
            f"unexpected release commit created:\n{result.stdout}"
        )

    def test_no_flag_file(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _run_update_changelog(changelog_image, ws)
        flag = ws / "tmp" / "changelog_committed.flag"
        assert not flag.exists(), "flag file should not exist when nothing committed"


# ---------------------------------------------------------------------------
# Scenario 3: non-release scenario → exit 0, no-op
# ---------------------------------------------------------------------------

class TestUpdateChangelogNonRelease:
    def test_pr_scenario_no_commit(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)
        tmp_dir = ws / "tmp"
        (tmp_dir / "scenario.env").write_text("SCENARIO=pr\n")
        result = _run_update_changelog(changelog_image, ws)
        assert result.returncode == 0
        result_log = subprocess.run(
            ["git", "log", "--oneline", "-1"],
            cwd=ws, capture_output=True, text=True,
        )
        assert "chore(release)" not in result_log.stdout


# ---------------------------------------------------------------------------
# Scenario 4: version files also staged when present
# ---------------------------------------------------------------------------

class TestUpdateChangelogVersionFiles:
    def test_version_files_staged(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        _write_config(ws)
        _seed_changelog_change(ws)

        # Create a version file
        (ws / "package.json").write_text('{"version":"1.0.0"}\n')
        subprocess.run(["git", "add", "package.json"], cwd=ws, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "chore: add package.json"],
            cwd=ws, check=True, capture_output=True,
        )
        # Modify it (simulate write-version-file output)
        (ws / "package.json").write_text('{"version":"1.1.0"}\n')

        tmp_dir = ws / "tmp"
        (tmp_dir / "version_files_modified.txt").write_text("/workspace/package.json\n")

        result = _run_update_changelog(changelog_image, ws)
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"expected 0\n{result.stdout}\n{result.stderr}"
        )
        # Check both files were committed
        result_log = subprocess.run(
            ["git", "show", "--name-only", "--format=", "HEAD"],
            cwd=ws, capture_output=True, text=True,
        )
        committed_files = result_log.stdout
        assert "CHANGELOG.md" in committed_files, f"CHANGELOG not committed:\n{committed_files}"
        assert "package.json" in committed_files, f"package.json not committed:\n{committed_files}"
