"""Integration test for GO-07: generate-changelog-last-commit subcommand.

Builds the Docker image once (shared via GO_CHANGELOG_IMAGE env var) and runs
`panora-versioning generate-changelog-last-commit` against seeded repos.

The test:
  1. Seeds a repo with commits of different types.
  2. Writes /tmp/.versioning-merged.yml with changelog config.
  3. Runs the binary.
  4. Asserts exit code, CHANGELOG.md content, and /tmp/changelog_entries.txt.
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


def _seed_repo_with_commits(workspace: Path, commits: list[str]) -> None:
    """Init a git repo with an initial tag then add the provided commits."""
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

    for i, msg in enumerate(commits):
        f = workspace / f"file{i}.txt"
        f.write_text(f"content {i}\n")
        subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", msg],
            cwd=workspace, check=True, capture_output=True,
        )


def _write_config(workspace: Path, extra_yaml: str = "") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    base = textwrap.dedent("""\
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
    (tmp / ".versioning-merged.yml").write_text(base + extra_yaml)


def _run_last_commit(
    image: str,
    workspace: Path,
    *,
    env_overrides: dict[str, str] | None = None,
    routed_commits: list[str] | None = None,
) -> subprocess.CompletedProcess:
    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)

    (tmp_dir / "scenario.env").write_text("SCENARIO=development_release\n")
    (tmp_dir / "next_version.txt").write_text("1.1.0\n")

    if routed_commits is not None:
        (tmp_dir / "routed_commits.txt").write_text("\n".join(routed_commits) + "\n")

    env_flags: list[str] = []
    env_flags += ["-e", "CHANGELOG_BASE_REF=v1.0.0"]
    env_flags += ["-e", "VERSIONING_BRANCH=feature/test"]

    if env_overrides:
        for k, v in env_overrides.items():
            env_flags += ["-e", f"{k}={v}"]

    entrypoint_args = [
        "--entrypoint", BINARY,
        image,
        "generate-changelog-last-commit",
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
# Scenario 1: single commit → CHANGELOG.md created with version header
# ---------------------------------------------------------------------------

class TestLastCommitSingle:
    def test_exit_0(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login handler"])
        _write_config(ws)
        result = _run_last_commit(changelog_image, ws)
        assert result.returncode == 0, (
            f"expected 0, got {result.returncode}\n{result.stdout}\n{result.stderr}"
        )

    def test_changelog_created(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login handler"])
        _write_config(ws)
        _run_last_commit(changelog_image, ws)
        cl = ws / "CHANGELOG.md"
        assert cl.exists(), "CHANGELOG.md not created"

    def test_version_header_present(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login handler"])
        _write_config(ws)
        _run_last_commit(changelog_image, ws)
        content = (ws / "CHANGELOG.md").read_text()
        assert "## 1.1.0" in content, f"version header missing:\n{content}"

    def test_commit_line_present(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login handler"])
        _write_config(ws)
        _run_last_commit(changelog_image, ws)
        content = (ws / "CHANGELOG.md").read_text()
        assert "feat: add login handler" in content, f"commit missing:\n{content}"

    def test_author_present(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login handler"])
        _write_config(ws)
        _run_last_commit(changelog_image, ws)
        content = (ws / "CHANGELOG.md").read_text()
        assert "CI Pipeline" in content, f"author missing:\n{content}"

    def test_banner_present(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login handler"])
        _write_config(ws)
        result = _run_last_commit(changelog_image, ws)
        combined = result.stdout + result.stderr
        assert "CHANGELOG" in combined.upper(), f"banner missing:\n{combined}"


# ---------------------------------------------------------------------------
# Scenario 2: multi-commit, last_commit mode → only last commit in CHANGELOG
# ---------------------------------------------------------------------------

class TestLastCommitMode:
    def test_only_last_commit_included(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, [
            "fix: fix bug",
            "feat: add new feature",  # ← this is last (most recent)
        ])
        _write_config(ws)
        _run_last_commit(changelog_image, ws)
        content = (ws / "CHANGELOG.md").read_text()
        assert "feat: add new feature" in content
        assert "fix: fix bug" not in content, (
            f"older commit should be excluded in last_commit mode:\n{content}"
        )

    def test_full_mode_includes_all(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, [
            "fix: fix bug",
            "feat: add new feature",
        ])
        # Write config with mode: full directly
        tmp_dir = ws / "tmp"
        tmp_dir.mkdir(exist_ok=True)
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
              mode: "full"
              use_emojis: false
              include_author: false
              include_commit_link: false
              include_ticket_link: false
            """)
        (tmp_dir / ".versioning-merged.yml").write_text(config)
        _run_last_commit(changelog_image, ws)
        cl = ws / "CHANGELOG.md"
        assert cl.exists(), "CHANGELOG.md not created"
        content = cl.read_text()
        assert "feat: add new feature" in content
        assert "fix: fix bug" in content


# ---------------------------------------------------------------------------
# Scenario 3: routed commits excluded in last_commit mode
# ---------------------------------------------------------------------------

class TestLastCommitRoutedExclusion:
    def test_routed_last_commit_excluded(self, changelog_image: str, tmp_path: Path) -> None:
        """When the last commit was already routed to per-folder, nothing goes to root CHANGELOG."""
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat(auth): add login"])
        _write_config(ws)

        # Get the last commit SHA
        result = subprocess.run(
            ["git", "log", "--pretty=format:%H", "-1"],
            cwd=ws, capture_output=True, text=True,
        )
        last_sha = result.stdout.strip()

        _run_last_commit(changelog_image, ws, routed_commits=[last_sha])
        # CHANGELOG should not exist or be empty of entries
        cl = ws / "CHANGELOG.md"
        if cl.exists():
            content = cl.read_text()
            assert "feat(auth)" not in content, (
                f"routed commit appeared in root CHANGELOG:\n{content}"
            )


# ---------------------------------------------------------------------------
# Scenario 4: hotfix scenario → header includes (Hotfix) marker
# ---------------------------------------------------------------------------

class TestLastCommitHotfix:
    def test_hotfix_header_marker(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["fix: critical patch"])
        _write_config(ws)
        result = _run_last_commit(
            changelog_image, ws,
            env_overrides={"SCENARIO": "hotfix"},
        )
        # Override scenario.env written inside _run_last_commit
        tmp_dir = ws / "tmp"
        (tmp_dir / "scenario.env").write_text("SCENARIO=hotfix\n")
        result = _run_last_commit(
            changelog_image, ws,
            env_overrides={},
        )
        cl = ws / "CHANGELOG.md"
        if cl.exists():
            content = cl.read_text()
            assert "(Hotfix)" in content, f"(Hotfix) marker missing:\n{content}"


# ---------------------------------------------------------------------------
# Scenario 5: emoji rendering
# ---------------------------------------------------------------------------

class TestLastCommitEmoji:
    def test_emoji_prefix_when_enabled(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo_with_commits(ws, ["feat: add login"])
        tmp_dir = ws / "tmp"
        tmp_dir.mkdir(exist_ok=True)
        config = textwrap.dedent("""\
            commits:
              format: "conventional"
            commit_types:
              - name: feat
                bump: minor
                emoji: "🚀"
            version:
              tag_prefix_v: true
              components:
                major: { enabled: true, initial: 0 }
                patch: { enabled: true, initial: 0 }
            changelog:
              file: "CHANGELOG.md"
              mode: "last_commit"
              use_emojis: true
              include_author: false
              include_commit_link: false
              include_ticket_link: false
            """)
        (tmp_dir / ".versioning-merged.yml").write_text(config)
        _run_last_commit(changelog_image, ws)
        content = (ws / "CHANGELOG.md").read_text()
        assert "🚀" in content, f"emoji missing:\n{content}"


