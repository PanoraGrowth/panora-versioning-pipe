"""Integration test for GO-11: PR pipeline orchestrator (self-exec model).

Verifies that `panora-versioning pr-pipeline` (and the auto-dispatch default
command, triggered by VERSIONING_PR_ID being set) runs the PR pipeline by
invoking each stage as a sub-process, matching pipe.sh + pr-pipeline.sh behavior.

Coverage:
  1. `pr-pipeline` subcommand exists and runs validation stages.
  2. Default command (no subcommand) auto-detects PR context from
     VERSIONING_PR_ID and dispatches to pr-pipeline.
  3. No tag is ever created in PR mode (this is the invariant that separates
     PR from branch pipeline).
  4. Early exit path: target_branch != tag_branch AND not hotfix_target → skip
     with exit 0 and skipped banner.
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
IMAGE_TAG = os.environ.get("GO_PIPELINE_IMAGE", "panora-versioning-pipe:go-pipeline-test")
BINARY_PATH = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available on this host",
)


@pytest.fixture(scope="module")
def go_image() -> str:
    """Build the multi-stage Docker image once per module."""
    result = subprocess.run(
        ["docker", "build", "-t", IMAGE_TAG, str(REPO_ROOT)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        pytest.fail(
            "docker build failed\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    return IMAGE_TAG


def _seed_pr_repo(
    workspace: Path,
    *,
    source_branch: str = "feature/pr-test",
    target_branch: str = "development",
    commit_msg: str = "feat: add new capability",
) -> Path:
    """Seed a git repo that simulates a PR: two branches, one feature commit.

    Creates a local bare remote at `<workspace>-remote.git` so that
    `origin/<target_branch>` resolves — matching the real CI environment.
    """
    cmds = [
        ["git", "init", f"--initial-branch={target_branch}"],
        ["git", "config", "user.email", "test@example.test"],
        ["git", "config", "user.name", "Test"],
    ]
    for cmd in cmds:
        subprocess.run(cmd, cwd=workspace, check=True, capture_output=True)

    # Initial commit on target branch
    (workspace / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )

    # Bare remote so origin/<target> resolves
    remote_path = workspace.parent / f"{workspace.name}-remote.git"
    subprocess.run(
        ["git", "init", "--bare", str(remote_path)],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "remote", "add", "origin", str(remote_path)],
        cwd=workspace,
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "push", "-u", "origin", target_branch],
        cwd=workspace,
        check=True,
        capture_output=True,
    )

    # Create source branch and the feature commit
    subprocess.run(["git", "checkout", "-b", source_branch], cwd=workspace, check=True, capture_output=True)
    (workspace / "feature.txt").write_text("feature\n")
    subprocess.run(["git", "add", "feature.txt"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", commit_msg],
        cwd=workspace,
        check=True,
        capture_output=True,
    )
    return remote_path


def _write_versioning_yml(workspace: Path) -> None:
    """Minimal repo config matching the canonical schema used across integration tests."""
    content = textwrap.dedent("""\
        commits:
          format: "conventional"
        branches:
          tag_on: "development"
          hotfix_targets: []
        version:
          tag_prefix_v: true
          components:
            epoch:
              enabled: true
              initial: 0
            major:
              enabled: true
              initial: 0
            patch:
              enabled: true
              initial: 0
            hotfix_counter:
              enabled: false
            timestamp:
              enabled: false
        changelog:
          mode: "full"
        validation:
          ignore_patterns:
            - "^Merge"
            - "^chore(release)"
    """)
    (workspace / ".versioning.yml").write_text(content)


def _run_pipeline(
    image: str,
    workspace: Path,
    *,
    subcommand: str | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    """Run the Go binary against a workspace.

    If `subcommand` is None, the default command (auto-dispatch) runs, which
    is the actual ENTRYPOINT behavior replacing pipe.sh.
    """
    env_flags: list[str] = []
    for k, v in (env or {}).items():
        env_flags.append(f"-e={k}={v}")

    cmd: list[str] = [
        "docker", "run", "--rm",
        "-v", f"{workspace}:/workspace",
        "-w", "/workspace",
        "--entrypoint", BINARY_PATH,
        *env_flags,
        image,
    ]
    if subcommand is not None:
        cmd.append(subcommand)

    return subprocess.run(cmd, capture_output=True, text=True)


def _tag_exists(workspace: Path, tag: str) -> bool:
    result = subprocess.run(
        ["git", "tag", "-l", tag],
        cwd=workspace,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() == tag


def _any_tag_exists(workspace: Path) -> bool:
    result = subprocess.run(
        ["git", "tag", "--list"],
        cwd=workspace,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() != ""


# =============================================================================
# Test cases
# =============================================================================


class TestGoPipelinePR:
    """PR pipeline orchestrator (GO-11)."""

    def test_pr_pipeline_subcommand_validates_commits(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """`panora-versioning pr-pipeline` runs validate-commits stage for a valid PR."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_pr_repo(workspace)
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand="pr-pipeline",
            env={
                "VERSIONING_BRANCH": "feature/pr-test",
                "VERSIONING_TARGET_BRANCH": "development",
                "VERSIONING_PR_ID": "42",
            },
        )

        assert result.returncode == 0, (
            f"pr-pipeline exited {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        # Scenario detection ran
        assert "DETECTING PIPELINE SCENARIO" in result.stdout
        # Validate-commits stage ran
        assert "VALIDATING COMMIT FORMAT" in result.stdout
        # Success banner visible
        assert "PIPELINE COMPLETED SUCCESSFULLY" in result.stdout
        # No tag created in PR mode
        assert not _any_tag_exists(workspace), "PR pipeline must not create tags"

    def test_default_command_dispatches_to_pr_when_pr_id_set(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """Default entrypoint (no subcommand) dispatches to PR pipeline when
        VERSIONING_PR_ID is set. This is the pipe.sh replacement behavior."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_pr_repo(workspace)
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand=None,  # no subcommand → auto-dispatch
            env={
                "VERSIONING_BRANCH": "feature/pr-test",
                "VERSIONING_TARGET_BRANCH": "development",
                "VERSIONING_PR_ID": "42",
            },
        )

        assert result.returncode == 0, (
            f"auto-dispatch exited {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        # PR pipeline banner visible
        assert "PR PIPELINE" in result.stdout
        # No tag created
        assert not _any_tag_exists(workspace), "PR pipeline (default cmd) must not create tags"

    def test_pr_pipeline_skips_when_target_is_not_tag_branch(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """PR targeting a non-tag, non-hotfix branch must skip (exit 0, no action)."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_pr_repo(
            workspace,
            source_branch="feature/pr-test",
            target_branch="main",  # not tag_on (development)
        )
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand="pr-pipeline",
            env={
                "VERSIONING_BRANCH": "feature/pr-test",
                "VERSIONING_TARGET_BRANCH": "main",  # unrelated branch
                "VERSIONING_PR_ID": "42",
            },
        )

        assert result.returncode == 0, (
            f"pr-pipeline (skipped) exited {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "PR PIPELINE SKIPPED" in result.stdout
        # Validation must not have run
        assert "VALIDATING COMMIT FORMAT" not in result.stdout

    def test_error_when_no_pipeline_context(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """Auto-dispatch with no VERSIONING_* variables set must error out (exit 1)."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_pr_repo(workspace)
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand=None,
            env={},  # nothing set, no platform detectable
        )

        assert result.returncode != 0, (
            f"expected non-zero exit; got stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        # Error message matches pipe.sh wording
        assert "Cannot determine pipeline type" in (result.stdout + result.stderr)
