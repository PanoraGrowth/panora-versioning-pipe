"""Integration test for generate-changelog-last-commit subcommand.

Builds the Docker image and runs `panora-versioning generate-changelog-last-commit`
against a seeded local git repo mounted at /workspace. The test:

  1. Seeds the repo + writes /tmp/scenario.env + /tmp/.versioning-merged.yml.
  2. Runs the binary.
  3. Asserts exit code, output files, AND log content.

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


def _commit(workspace: Path, msg: str, files: dict[str, str] | None = None) -> str:
    """Create a commit and return its SHA."""
    if files:
        for rel_path, content in files.items():
            p = workspace / rel_path
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
            subprocess.run(
                ["git", "add", rel_path], cwd=workspace, check=True, capture_output=True
            )
    else:
        sentinel = workspace / f"_change_{uuid.uuid4().hex[:6]}.txt"
        sentinel.write_text(f"{msg}\n")
        subprocess.run(
            ["git", "add", sentinel.name], cwd=workspace, check=True, capture_output=True
        )

    subprocess.run(
        ["git", "commit", "-m", msg],
        cwd=workspace,
        check=True,
        capture_output=True,
    )
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=workspace,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _write_scenario_env(workspace: Path, scenario: str = "development_release") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "scenario.env").write_text(f"SCENARIO={scenario}\n")


def _write_next_version(workspace: Path, version: str = "v1.2.0") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "next_version.txt").write_text(f"{version}\n")


def _write_config(
    workspace: Path,
    mode: str = "last_commit",
    use_emojis: bool = False,
    include_author: bool = False,
    include_commit_link: bool = False,
    include_ticket_link: bool = False,
) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)

    content = textwrap.dedent(f"""\
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
          mode: "{mode}"
          use_emojis: {str(use_emojis).lower()}
          include_author: {str(include_author).lower()}
          include_commit_link: {str(include_commit_link).lower()}
          include_ticket_link: {str(include_ticket_link).lower()}
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


def _run_generate_changelog_last_commit(
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
            "generate-changelog-last-commit",
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

class TestLastCommitBasic:
    """Single feat commit → CHANGELOG created with correct content."""

    def test_exit_code(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add feature")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace)

        result = _run_generate_changelog_last_commit(changelog_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_changelog_created(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add feature")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace)

        _run_generate_changelog_last_commit(changelog_image, workspace)
        changelog = workspace / "CHANGELOG.md"
        assert changelog.exists(), "CHANGELOG.md was not created"
        content = changelog.read_text()
        assert "v1.2.0" in content, f"version missing from CHANGELOG:\n{content}"
        assert "feat: add feature" in content, (
            f"commit message missing from CHANGELOG:\n{content}"
        )

    def test_changelog_header(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add feature")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace)

        _run_generate_changelog_last_commit(changelog_image, workspace)
        changelog = workspace / "CHANGELOG.md"
        assert changelog.exists(), "CHANGELOG.md was not created"
        content = changelog.read_text()
        assert content.startswith("# Changelog"), (
            f"CHANGELOG.md does not start with '# Changelog':\n{content[:200]}"
        )

    def test_logs_contain_version_and_mode(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add feature")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace)

        result = _run_generate_changelog_last_commit(changelog_image, workspace)
        stdout = result.stdout.lower()
        assert "changelog" in stdout, f"'changelog' missing from logs:\n{result.stdout}"
        assert "v1.2.0" in result.stdout, f"version missing from logs:\n{result.stdout}"


class TestLastCommitFullMode:
    """mode=full includes all commits in the CHANGELOG."""

    def test_multiple_commits_in_full_mode(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: first feature")
        _commit(workspace, "fix: first fix")
        _commit(workspace, "feat: second feature")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace, mode="full")

        _run_generate_changelog_last_commit(changelog_image, workspace)
        changelog = workspace / "CHANGELOG.md"
        assert changelog.exists(), "CHANGELOG.md was not created"
        content = changelog.read_text()
        assert "first feature" in content, f"'first feature' missing from CHANGELOG:\n{content}"
        assert "first fix" in content, f"'first fix' missing from CHANGELOG:\n{content}"
        assert "second feature" in content, f"'second feature' missing from CHANGELOG:\n{content}"


class TestLastCommitExcludesRouted:
    """Commits listed in /tmp/routed_commits.txt must not appear in the CHANGELOG."""

    def test_routed_commit_excluded(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        sha = _commit(workspace, "feat: routed feature")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace)

        tmp = workspace / "tmp"
        tmp.mkdir(exist_ok=True)
        (tmp / "routed_commits.txt").write_text(f"{sha}\n")

        _run_generate_changelog_last_commit(changelog_image, workspace)
        changelog = workspace / "CHANGELOG.md"
        content = changelog.read_text() if changelog.exists() else ""
        assert "routed feature" not in content, (
            f"routed commit message must not appear in CHANGELOG:\n{content}"
        )


class TestLastCommitHotfix:
    """Hotfix scenario — CHANGELOG includes hotfix marker."""

    def test_hotfix_marker(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "fix: patch critical bug")
        _write_scenario_env(workspace, scenario="hotfix")
        _write_next_version(workspace)
        _write_config(workspace)

        result = _run_generate_changelog_last_commit(changelog_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0 for hotfix scenario, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        changelog = workspace / "CHANGELOG.md"
        assert changelog.exists(), "CHANGELOG.md was not created for hotfix scenario"
        content = changelog.read_text()
        assert "(Hotfix)" in content, (
            f"'(Hotfix)' marker missing from hotfix CHANGELOG:\n{content}"
        )


class TestLastCommitScenarioSkip:
    """Non-release scenarios must exit 0 and produce no CHANGELOG."""

    def test_pull_request_scenario_skips(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add feature")
        _write_scenario_env(workspace, scenario="pull_request")
        _write_next_version(workspace)
        _write_config(workspace)

        result = _run_generate_changelog_last_commit(changelog_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0 for pull_request scenario, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert not (workspace / "CHANGELOG.md").exists(), (
            "CHANGELOG.md must not be created when scenario is pull_request"
        )


class TestLastCommitMissingVersion:
    """Missing /tmp/next_version.txt → non-zero exit."""

    def test_missing_version_file_fails(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add feature")
        _write_scenario_env(workspace)
        # deliberately skip _write_next_version
        _write_config(workspace)

        result = _run_generate_changelog_last_commit(changelog_image, workspace)
        assert result.returncode != 0, (
            f"expected non-zero exit when next_version.txt is missing\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


class TestLastCommitAppendBehavior:
    """Running for v1.2.0 appends to an existing CHANGELOG that contains v1.1.0."""

    def test_appends_to_existing(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat: add new thing")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config(workspace)

        existing_content = textwrap.dedent("""\
            # Changelog

            ## v1.1.0

            ### Features

            - feat: old feature
        """)
        (workspace / "CHANGELOG.md").write_text(existing_content)

        _run_generate_changelog_last_commit(changelog_image, workspace)
        changelog = workspace / "CHANGELOG.md"
        assert changelog.exists(), "CHANGELOG.md does not exist after run"
        content = changelog.read_text()

        assert "v1.2.0" in content, f"v1.2.0 not found in CHANGELOG:\n{content}"
        assert "v1.1.0" in content, f"v1.1.0 missing — existing content was overwritten:\n{content}"

        idx_new = content.index("v1.2.0")
        idx_old = content.index("v1.1.0")
        assert idx_new > idx_old, (
            f"v1.2.0 (idx={idx_new}) must appear AFTER v1.1.0 (idx={idx_old}) in CHANGELOG — new entries append to end"
        )
