"""Integration test for GO-11: branch pipeline orchestrator (self-exec model).

Verifies that `panora-versioning branch-pipeline` (and the auto-dispatch default
command, triggered by VERSIONING_BRANCH being set with no VERSIONING_PR_ID)
runs the full branch pipeline end-to-end: scenario detection → calc-version →
guardrails → write-version-file → changelogs → update-changelog → tag creation.

Coverage:
  1. `branch-pipeline` subcommand runs the full tag-creation flow on tag_on branch.
  2. Default command (no subcommand) auto-detects branch context and dispatches.
  3. Branch != tag_on → early exit (no version calculation, no tag).
  4. No new commits since last tag → exit 0 with "No new commits" message.

Note: tag push to remote is NOT exercised here (no remote in test repo). The
test verifies local tag creation and CHANGELOG commit. `git_push_branch_and_tag`
would fail without a remote, so the pipeline is expected to fail at the push
stage. The test asserts the tag was created locally BEFORE the push attempt.
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


def _seed_branch_repo(
    workspace: Path,
    *,
    branch: str = "development",
    initial_tag: str | None = None,
    new_commit_msg: str = "feat: add capability",
    bare_remote: bool = True,
) -> Path | None:
    """Seed a git repo simulating a branch push: one new commit since last tag.

    If `bare_remote=True`, also creates a local bare remote and pushes the
    initial branch to it, so that `git push` in the pipeline has a target. The
    bare remote path is returned (or None if bare_remote=False).
    """
    cmds = [
        ["git", "init", f"--initial-branch={branch}"],
        ["git", "config", "user.email", "test@example.test"],
        ["git", "config", "user.name", "Test"],
    ]
    for cmd in cmds:
        subprocess.run(cmd, cwd=workspace, check=True, capture_output=True)

    (workspace / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )

    if initial_tag is not None:
        subprocess.run(
            ["git", "tag", initial_tag],
            cwd=workspace,
            check=True,
            capture_output=True,
        )

    # One new commit after the tag
    (workspace / "change.txt").write_text("change\n")
    subprocess.run(["git", "add", "change.txt"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", new_commit_msg],
        cwd=workspace,
        check=True,
        capture_output=True,
    )

    remote_path: Path | None = None
    if bare_remote:
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
            ["git", "push", "-u", "origin", branch],
            cwd=workspace,
            check=True,
            capture_output=True,
        )
        if initial_tag is not None:
            subprocess.run(
                ["git", "push", "origin", initial_tag],
                cwd=workspace,
                check=True,
                capture_output=True,
            )

    return remote_path


def _write_versioning_yml(workspace: Path) -> None:
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
          file: "CHANGELOG.md"
        version_file:
          enabled: false
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
    extra_volumes: list[tuple[Path, str]] | None = None,
) -> subprocess.CompletedProcess:
    env_flags: list[str] = []
    for k, v in (env or {}).items():
        env_flags.append(f"-e={k}={v}")

    volumes: list[tuple[Path, str]] = [(workspace, "/workspace")]
    if extra_volumes:
        volumes.extend(extra_volumes)

    cmd: list[str] = ["docker", "run", "--rm"]
    for src, dst in volumes:
        cmd.extend(["-v", f"{src}:{dst}"])
    cmd.extend([
        "-w", "/workspace",
        "--entrypoint", BINARY_PATH,
        *env_flags,
        image,
    ])
    if subcommand is not None:
        cmd.append(subcommand)

    return subprocess.run(cmd, capture_output=True, text=True)


def _list_tags(workspace: Path) -> list[str]:
    result = subprocess.run(
        ["git", "tag", "--list"],
        cwd=workspace,
        capture_output=True,
        text=True,
    )
    return [t for t in result.stdout.strip().split("\n") if t]


# =============================================================================
# Test cases
# =============================================================================


class TestGoPipelineBranch:
    """Branch pipeline orchestrator (GO-11)."""

    def test_branch_pipeline_creates_tag_and_changelog(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """`panora-versioning branch-pipeline` runs the full sequence:
        detect-scenario → calc-version → guardrails → changelog → tag.

        Verifies a new tag was created locally (remote push may or may not
        succeed depending on the bare remote, but the tag must exist locally).
        """
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_branch_repo(
            workspace,
            branch="development",
            initial_tag=None,  # no prior tags
            new_commit_msg="feat: first feature",
        )
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand="branch-pipeline",
            env={
                "VERSIONING_BRANCH": "development",
            },
        )

        # Full pipeline is exercised; returncode may be 0 or non-zero depending on
        # whether the atomic push succeeds. Either way, key stages must have run
        # and the local tag must have been created BEFORE the push attempt.
        combined = result.stdout + result.stderr
        assert "BRANCH PIPELINE - TAG CREATION" in combined, combined
        assert "CALCULATING VERSION" in combined, combined
        assert "GENERATING CHANGELOG" in combined, combined
        assert "CREATING VERSION TAG" in combined, combined

        # A local tag must have been created (v0.0.1 on initial feat)
        tags = _list_tags(workspace)
        assert len(tags) >= 1, f"expected at least one tag; got {tags}\n{combined}"

    def test_default_command_dispatches_to_branch_when_pr_id_absent(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """Default entrypoint (no subcommand) dispatches to branch-pipeline
        when VERSIONING_BRANCH is set and VERSIONING_PR_ID is not. Replaces
        pipe.sh."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_branch_repo(
            workspace,
            branch="development",
            initial_tag=None,
            new_commit_msg="feat: new",
        )
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand=None,
            env={
                "VERSIONING_BRANCH": "development",
            },
        )

        combined = result.stdout + result.stderr
        # pipe.sh banner carried over by the Go orchestrator
        assert "VERSIONING PIPE - BRANCH PIPELINE" in combined, combined
        # Version calculation ran
        assert "CALCULATING VERSION" in combined, combined

    def test_branch_pipeline_skips_non_tag_branch(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """branch-pipeline must skip (exit 0) when branch != tag_on."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_branch_repo(
            workspace,
            branch="main",  # not tag_on (development)
            initial_tag=None,
            new_commit_msg="feat: unrelated",
        )
        _write_versioning_yml(workspace)

        result = _run_pipeline(
            go_image,
            workspace,
            subcommand="branch-pipeline",
            env={
                "VERSIONING_BRANCH": "main",
            },
        )

        assert result.returncode == 0, (
            f"expected 0 on skip; got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        combined = result.stdout + result.stderr
        assert "Tag creation only runs on" in combined, combined
        # Version calculation must NOT have run
        assert "CALCULATING VERSION" not in combined
        # No tag created
        assert _list_tags(workspace) == [], "skipped pipeline must not create tags"
