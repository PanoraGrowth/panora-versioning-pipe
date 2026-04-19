"""Integration tests for the Go `validate-commits` subcommand (ticket GO-03).

Tests build the Docker image and assert on exit code + log content produced by
`panora-versioning validate-commits`. These tests MUST fail before the Go
implementation exists (stubs return exit 42) and MUST pass after.

Contract preserved from scripts/validation/validate-commits.sh:
  - Reads SCENARIO from /tmp/scenario.env
  - Reads rules from /tmp/.versioning-merged.yml
  - Uses git log origin/<target_branch>..HEAD --no-merges --pretty=%s
  - Exit 0: all commits valid (or scenario not applicable)
  - Exit 1: any violation found
  - Violations printed to stderr with human-readable context
"""

from __future__ import annotations

import os
import subprocess
import uuid
from pathlib import Path
from textwrap import dedent

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
IMAGE_TAG = os.environ.get("GO_IMAGE", "panora-versioning-pipe:go-bootstrap-test")
BINARY = "/usr/local/bin/panora-versioning"


def _build_image() -> str:
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


@pytest.fixture(scope="module")
def go_image() -> str:
    return _build_image()


def _seed_repo(path: Path, commits: list[str], target_branch: str = "main") -> None:
    """Create a bare git repo with an initial commit on target_branch + PR commits."""
    cmds = [
        ["git", "init", "--initial-branch", target_branch],
        ["git", "config", "user.email", "test@example.com"],
        ["git", "config", "user.name", "Test"],
    ]
    for cmd in cmds:
        subprocess.run(cmd, cwd=path, check=True, capture_output=True)

    # Seed file + initial commit on target branch
    (path / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=path, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial"],
        cwd=path,
        check=True,
        capture_output=True,
    )

    # Simulate origin/target_branch by creating the remote ref locally
    # (validate-commits uses `git log origin/<target>..HEAD`)
    subprocess.run(
        ["git", "update-ref", f"refs/remotes/origin/{target_branch}", "HEAD"],
        cwd=path,
        check=True,
        capture_output=True,
    )

    # Add PR commits on top
    for i, msg in enumerate(commits):
        (path / f"file{i}.txt").write_text(f"{msg}\n")
        subprocess.run(["git", "add", f"file{i}.txt"], cwd=path, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", msg],
            cwd=path,
            check=True,
            capture_output=True,
        )


def _run_validate(
    image: str,
    workspace: Path,
    scenario: str,
    config_content: str,
    target_branch: str = "main",
    extra_env: dict | None = None,
) -> subprocess.CompletedProcess:
    """Run panora-versioning validate-commits inside Docker."""
    scenario_env = workspace / "scenario.env"
    scenario_env.write_text(
        dedent(f"""\
            SCENARIO={scenario}
            VERSIONING_TARGET_BRANCH={target_branch}
            VERSIONING_BRANCH=feature/test
        """)
    )

    config_file = workspace / "versioning-merged.yml"
    config_file.write_text(config_content)

    env_args = [
        f"-e=VERSIONING_TARGET_BRANCH={target_branch}",
        f"-e=VERSIONING_BRANCH=feature/test",
    ]
    if extra_env:
        env_args += [f"-e={k}={v}" for k, v in extra_env.items()]

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-w", "/workspace",
            # Map our local files to the expected /tmp paths
            "-v", f"{scenario_env}:/tmp/scenario.env",
            "-v", f"{config_file}:/tmp/.versioning-merged.yml",
            *env_args,
            "--entrypoint", BINARY,
            image,
            "validate-commits",
        ],
        capture_output=True,
        text=True,
    )


# =============================================================================
# Scenario skip — non-applicable scenarios exit 0 immediately
# =============================================================================

def test_non_applicable_scenario_exits_0(go_image: str, tmp_path: Path) -> None:
    """Scenarios other than development_release/hotfix must exit 0 immediately."""
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    _seed_repo(workspace, ["feat: whatever"])

    result = _run_validate(
        go_image,
        workspace,
        scenario="tag_on_merge",
        config_content=dedent("""\
            commits:
              format: conventional
            validation:
              require_commit_types: true
            changelog:
              mode: full
        """),
    )
    assert result.returncode == 0, (
        f"Expected exit 0 for non-applicable scenario\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


# =============================================================================
# Valid commits — must pass
# =============================================================================

def test_valid_conventional_commit_exits_0(go_image: str, tmp_path: Path) -> None:
    """A single valid conventional commit must exit 0."""
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    _seed_repo(workspace, ["feat: add authentication"])

    result = _run_validate(
        go_image,
        workspace,
        scenario="development_release",
        config_content=dedent("""\
            commits:
              format: conventional
            validation:
              require_commit_types: true
            changelog:
              mode: full
        """),
    )
    combined = result.stdout + result.stderr
    assert result.returncode == 0, (
        f"Expected exit 0 for valid conventional commit\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    # Banner must appear
    assert "VALIDATING COMMIT FORMAT" in combined.upper() or "validating" in combined.lower(), (
        f"Missing validation banner\noutput:\n{combined}"
    )


# =============================================================================
# Invalid commits — must fail
# =============================================================================

def test_commit_missing_type_prefix_exits_1(go_image: str, tmp_path: Path) -> None:
    """A commit without a valid type prefix must exit 1 and name the offender on stderr."""
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    _seed_repo(workspace, ["this commit has no type prefix"])

    result = _run_validate(
        go_image,
        workspace,
        scenario="development_release",
        config_content=dedent("""\
            commits:
              format: conventional
            validation:
              require_commit_types: true
            changelog:
              mode: full
        """),
    )
    assert result.returncode == 1, (
        f"Expected exit 1 for commit missing type prefix\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert "this commit has no type prefix" in combined, (
        f"Offending commit not named in output\noutput:\n{combined}"
    )


def test_multiple_invalid_commits_all_reported(go_image: str, tmp_path: Path) -> None:
    """Multiple invalid commits must all be reported and exit 1."""
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    bad_commits = ["bad commit one", "bad commit two", "bad commit three"]
    _seed_repo(workspace, bad_commits)

    result = _run_validate(
        go_image,
        workspace,
        scenario="development_release",
        config_content=dedent("""\
            commits:
              format: conventional
            validation:
              require_commit_types: true
            changelog:
              mode: full
        """),
    )
    assert result.returncode == 1, (
        f"Expected exit 1 for multiple invalid commits\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    for commit in bad_commits:
        assert commit in combined, (
            f"Commit {commit!r} not reported\noutput:\n{combined}"
        )


def test_rules_disabled_exits_0_despite_bad_commits(go_image: str, tmp_path: Path) -> None:
    """When require_commit_types is false, any commit format is accepted."""
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    _seed_repo(workspace, ["this is a totally unformatted commit"])

    result = _run_validate(
        go_image,
        workspace,
        scenario="development_release",
        config_content=dedent("""\
            commits:
              format: conventional
            validation:
              require_commit_types: false
            changelog:
              mode: full
        """),
    )
    assert result.returncode == 0, (
        f"Expected exit 0 when validation disabled\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


# =============================================================================
# Hotfix scenario — must also validate
# =============================================================================

def test_hotfix_scenario_validates_commits(go_image: str, tmp_path: Path) -> None:
    """SCENARIO=hotfix must also trigger validation (same as development_release)."""
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    _seed_repo(workspace, ["NOT_A_VALID_COMMIT_FORMAT"])

    result = _run_validate(
        go_image,
        workspace,
        scenario="hotfix",
        config_content=dedent("""\
            commits:
              format: conventional
            validation:
              require_commit_types: true
            changelog:
              mode: full
        """),
    )
    assert result.returncode == 1, (
        f"Expected exit 1 for invalid commit in hotfix scenario\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
