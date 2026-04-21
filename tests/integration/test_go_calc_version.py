"""Integration test for GO-01: calc-version subcommand.

Builds the Docker image and runs `panora-versioning calc-version` against a
seeded local git repo mounted at /workspace. The test:

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
IMAGE_TAG = os.environ.get("GO_CALC_VERSION_IMAGE", "panora-versioning-pipe:go-calc-version-test")
BINARY = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


@pytest.fixture(scope="module")
def calc_image() -> str:
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


def _seed_repo(
    workspace: Path,
    *,
    initial_tag: str | None = None,
    commit_msg: str = "chore: seed",
) -> None:
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

    if initial_tag:
        subprocess.run(
            ["git", "tag", initial_tag],
            cwd=workspace,
            check=True,
            capture_output=True,
        )

    if commit_msg != "chore: initial commit":
        (workspace / "change.txt").write_text(f"change: {commit_msg}\n")
        subprocess.run(
            ["git", "add", "change.txt"], cwd=workspace, check=True, capture_output=True
        )
        subprocess.run(
            ["git", "commit", "-m", commit_msg],
            cwd=workspace,
            check=True,
            capture_output=True,
        )


def _write_scenario_env(workspace: Path, scenario: str = "development_release") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "scenario.env").write_text(f"SCENARIO={scenario}\n")


def _write_merged_config(workspace: Path, major_initial: int = 0) -> None:
    _write_merged_config_with_major_initial(workspace, major_initial=major_initial)


def _write_merged_config_with_major_initial(workspace: Path, *, major_initial: int = 0) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)

    content = textwrap.dedent(f"""\
        commits:
          format: "conventional"
        version:
          components:
            epoch:
              enabled: false
              initial: 0
            major:
              enabled: true
              initial: {major_initial}
            patch:
              enabled: true
              initial: 0
            hotfix_counter:
              enabled: true
              initial: 0
            timestamp:
              enabled: false
          tag_prefix_v: true
          separators:
            version: "."
        changelog:
          mode: "full"
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


def _run_calc_version(
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
            "calc-version",
        ],
        capture_output=True,
        text=True,
    )


def _read_tmp(workspace: Path, filename: str) -> str:
    p = workspace / "tmp" / filename
    return p.read_text().strip() if p.exists() else ""


class TestCalcVersionFeat:
    """feat: commit → minor bump."""

    def test_exit_code(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="feat: add thing")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        result = _run_calc_version(calc_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_next_version(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="feat: add thing")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        _run_calc_version(calc_image, workspace)
        # Schema: major+patch+hotfix_counter. hotfix_counter=0 is omitted (bash gate: >0).
        # Normal releases are 2-slot: vMAJOR.PATCH. feat bumps patch slot → v1.1.
        assert _read_tmp(workspace, "next_version.txt") == "v1.1"

    def test_bump_type(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="feat: add thing")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        _run_calc_version(calc_image, workspace)
        assert _read_tmp(workspace, "bump_type.txt") == "minor"

    def test_logs(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="feat: add thing")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        result = _run_calc_version(calc_image, workspace)
        stdout = result.stdout.lower()
        assert "calculating" in stdout, f"missing 'calculating' in logs:\n{result.stdout}"
        assert "minor" in stdout, f"missing bump type in logs:\n{result.stdout}"
        assert "next_version.txt" in stdout, f"missing write confirmation in logs:\n{result.stdout}"


class TestCalcVersionFix:
    """fix: commit → patch bump."""

    def test_patch_bump(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="fix: correct thing")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        _run_calc_version(calc_image, workspace)
        assert _read_tmp(workspace, "bump_type.txt") == "patch"
        # Schema: major+patch+hotfix_counter. hotfix_counter=0 omitted. patch slot bumped → v1.1.
        assert _read_tmp(workspace, "next_version.txt") == "v1.1"


class TestCalcVersionBreaking:
    """feat!: or BREAKING CHANGE → major bump."""

    def test_breaking_bang(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="feat!: remove api")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        _run_calc_version(calc_image, workspace)
        assert _read_tmp(workspace, "bump_type.txt") == "major"
        # Schema: major+patch+hotfix_counter. major++ patch=0 hotfix=0 (omitted). → v2.0.
        assert _read_tmp(workspace, "next_version.txt") == "v2.0"


class TestCalcVersionChore:
    """chore: commit → no bump (bump=none)."""

    def test_none_bump(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="chore: update deps")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        result = _run_calc_version(calc_image, workspace)
        assert result.returncode == 0, (
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        bump = _read_tmp(workspace, "bump_type.txt")
        assert bump in ("none", ""), f"unexpected bump: {bump!r}"


class TestCalcVersionColdStart:
    """No tags → uses initial values from config."""

    def test_cold_start_minor(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, commit_msg="feat: first feature")
        _write_scenario_env(workspace)
        _write_merged_config(workspace)

        result = _run_calc_version(calc_image, workspace)
        assert result.returncode == 0
        # Schema: major+patch+hotfix_counter. Cold start: major=0, patch=0+1=1, hotfix=0 (omitted). → v0.1.
        assert _read_tmp(workspace, "next_version.txt") == "v0.1"
        assert _read_tmp(workspace, "bump_type.txt") == "minor"


class TestCalcVersionNamespaceFilter:
    """Tags outside major.initial namespace are ignored."""

    def test_namespace_filter(self, calc_image: str, tmp_path: Path) -> None:
        """With major.initial=2, tags v1.x.x should be ignored — cold start in v2."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.9.9", commit_msg="feat: new epoch")
        _write_scenario_env(workspace)
        _write_merged_config_with_major_initial(workspace, major_initial=2)

        result = _run_calc_version(calc_image, workspace)
        assert result.returncode == 0
        # Schema: major+patch+hotfix_counter. major_initial=2, cold start → patch=0+1=1, hotfix=0 (omitted). → v2.1.
        assert _read_tmp(workspace, "next_version.txt") == "v2.1"
        assert _read_tmp(workspace, "bump_type.txt") == "minor"


def _write_merged_config_hotfix(workspace: Path) -> None:
    """Write a merged config with hotfix_counter enabled."""
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)

    content = textwrap.dedent("""\
        commits:
          format: "conventional"
        version:
          components:
            epoch:
              enabled: false
              initial: 0
            major:
              enabled: true
              initial: 0
            patch:
              enabled: true
              initial: 0
            hotfix_counter:
              enabled: true
              initial: 0
            timestamp:
              enabled: false
          tag_prefix_v: true
          separators:
            version: "."
        changelog:
          mode: "full"
        commit_types:
          - name: "feat"
            bump: "minor"
          - name: "fix"
            bump: "patch"
          - name: "chore"
            bump: "none"
        validation:
          ignore_patterns:
            - "^Merge"
            - "^chore\\\\(release\\\\)"
    """)
    (tmp / ".versioning-merged.yml").write_text(content)


class TestCalcVersionHotfix:
    """hotfix scenario → bump_type=hotfix, next_version increments hotfix_counter.

    Verifies the fix for AUDIT finding [BLOCKER]: calc_version.go was writing
    bump_type="patch" instead of "hotfix" in hotfix scenarios, causing the
    guardrail to check patch regression instead of hotfix_counter regression.
    """

    def test_exit_code(self, calc_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="fix: critical bug")
        _write_scenario_env(workspace, scenario="hotfix")
        _write_merged_config_hotfix(workspace)

        result = _run_calc_version(calc_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_bump_type_is_hotfix(self, calc_image: str, tmp_path: Path) -> None:
        """bump_type.txt must contain 'hotfix', not 'patch'."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="fix: critical bug")
        _write_scenario_env(workspace, scenario="hotfix")
        _write_merged_config_hotfix(workspace)

        _run_calc_version(calc_image, workspace)
        bump = _read_tmp(workspace, "bump_type.txt")
        assert bump == "hotfix", (
            f"expected bump_type='hotfix' (BLOCKER fix), got {bump!r}"
        )

    def test_next_version_increments_hotfix_counter(self, calc_image: str, tmp_path: Path) -> None:
        """next_version.txt must increment hotfix_counter in schema-aware format
        (3-slot when epoch disabled: major.patch.hotfix_counter).

        Ticket 074: post-fix, nextHotfixVersion emits slots equal to enabled
        components, without the spurious "base" slot. Seed v1.0.0 (3-slot)
        + hotfix → v1.0.1 (not v1.0.0.1).
        """
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="fix: critical bug")
        _write_scenario_env(workspace, scenario="hotfix")
        _write_merged_config_hotfix(workspace)

        _run_calc_version(calc_image, workspace)
        next_ver = _read_tmp(workspace, "next_version.txt")
        assert next_ver == "v1.0.1", (
            f"expected next_version='v1.0.1', got {next_ver!r}"
        )

    def test_logs_mention_hotfix(self, calc_image: str, tmp_path: Path) -> None:
        """stdout must mention 'hotfix' to confirm the correct scenario path."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, initial_tag="v1.0.0", commit_msg="fix: critical bug")
        _write_scenario_env(workspace, scenario="hotfix")
        _write_merged_config_hotfix(workspace)

        result = _run_calc_version(calc_image, workspace)
        assert "hotfix" in result.stdout.lower(), (
            f"expected 'hotfix' in stdout logs:\n{result.stdout}"
        )
