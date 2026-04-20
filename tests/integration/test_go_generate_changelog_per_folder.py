"""Integration test for generate-changelog-per-folder subcommand.

Builds the Docker image and runs `panora-versioning generate-changelog-per-folder`
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


def _write_config_per_folder(
    workspace: Path,
    folders: list[str],
    mode: str = "full",
    scope_matching: str = "prefix",
) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)

    folders_lines = "".join(f'              - "{f}"\n' for f in folders)

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
          use_emojis: false
          include_author: false
          include_commit_link: false
          include_ticket_link: false
          per_folder:
            enabled: true
            scope_matching: "{scope_matching}"
            fallback: "none"
            folders:
{folders_lines}
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


def _run_generate_changelog_per_folder(
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
            "generate-changelog-per-folder",
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

class TestPerFolderBasic:
    """Monorepo with two service folders — basic routing and changelog generation."""

    def test_exit_code(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        _commit(workspace, "fix(worker): retry", {"services/worker/worker.go": "package worker\n"})
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api", "services/worker"])

        result = _run_generate_changelog_per_folder(changelog_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_routed_commits_written(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        api_sha = _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        worker_sha = _commit(workspace, "fix(worker): retry", {"services/worker/worker.go": "package worker\n"})
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api", "services/worker"])

        _run_generate_changelog_per_folder(changelog_image, workspace)
        routed = _read_tmp(workspace, "routed_commits.txt")
        assert api_sha in routed, (
            f"api commit SHA {api_sha} not in routed_commits.txt:\n{routed}"
        )
        assert worker_sha in routed, (
            f"worker commit SHA {worker_sha} not in routed_commits.txt:\n{routed}"
        )

    def test_per_folder_changelogs_list_written(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        _commit(workspace, "fix(worker): retry", {"services/worker/worker.go": "package worker\n"})
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api", "services/worker"])

        _run_generate_changelog_per_folder(changelog_image, workspace)
        changelogs_list = _read_tmp(workspace, "per_folder_changelogs.txt")
        assert "services/api" in changelogs_list, (
            f"services/api path not in per_folder_changelogs.txt:\n{changelogs_list}"
        )
        assert "services/worker" in changelogs_list, (
            f"services/worker path not in per_folder_changelogs.txt:\n{changelogs_list}"
        )

    def test_folder_changelog_content(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        _commit(workspace, "fix(worker): retry", {"services/worker/worker.go": "package worker\n"})
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api", "services/worker"])

        _run_generate_changelog_per_folder(changelog_image, workspace)
        api_changelog = workspace / "services" / "api" / "CHANGELOG.md"
        assert api_changelog.exists(), "services/api/CHANGELOG.md was not created"
        content = api_changelog.read_text()
        assert "v1.2.0" in content, f"version missing from api CHANGELOG:\n{content}"
        assert "feat" in content.lower(), f"'feat' missing from api CHANGELOG:\n{content}"
        assert "add endpoint" in content, f"commit description missing from api CHANGELOG:\n{content}"

    def test_unscoped_commit_not_routed(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        unscoped_sha = _commit(workspace, "chore: update readme")
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api", "services/worker"])

        _run_generate_changelog_per_folder(changelog_image, workspace)
        routed = _read_tmp(workspace, "routed_commits.txt")
        assert unscoped_sha not in routed, (
            f"unscoped commit SHA {unscoped_sha} should NOT be in routed_commits.txt:\n{routed}"
        )

    def test_non_development_scenario_exits_0_skips(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        _write_scenario_env(workspace, scenario="pull_request")
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api"])

        result = _run_generate_changelog_per_folder(changelog_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0 for pull_request scenario, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert not _tmp_exists(workspace, "routed_commits.txt"), (
            "routed_commits.txt must not be created when scenario is pull_request"
        )
        assert not (workspace / "services" / "api" / "CHANGELOG.md").exists(), (
            "CHANGELOG.md must not be created when scenario is pull_request"
        )

    def test_logs_show_routing(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "feat(api): add endpoint", {"services/api/main.go": "package main\n"})
        _write_scenario_env(workspace)
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api"])

        result = _run_generate_changelog_per_folder(changelog_image, workspace)
        stdout = result.stdout.lower()
        assert "per-folder" in stdout or "changelog" in stdout, (
            f"expected 'per-folder' or 'changelog' in logs:\n{result.stdout}"
        )


class TestPerFolderHotfix:
    """Hotfix scenario — folder CHANGELOG includes hotfix marker."""

    def test_hotfix_header_suffix(self, changelog_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _init_repo(workspace)
        _commit(workspace, "fix(api): patch security issue", {"services/api/main.go": "package main\n"})
        _write_scenario_env(workspace, scenario="hotfix")
        _write_next_version(workspace)
        _write_config_per_folder(workspace, ["services/api"])

        result = _run_generate_changelog_per_folder(changelog_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0 for hotfix scenario, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        api_changelog = workspace / "services" / "api" / "CHANGELOG.md"
        assert api_changelog.exists(), "services/api/CHANGELOG.md was not created for hotfix"
        content = api_changelog.read_text()
        assert "(Hotfix)" in content, (
            f"'(Hotfix)' marker missing from hotfix scenario CHANGELOG:\n{content}"
        )
