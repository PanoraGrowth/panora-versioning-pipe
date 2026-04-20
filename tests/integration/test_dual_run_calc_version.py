"""Dual-run integration test for calc-version: bash vs Go parity.

Runs the same scenario against two Docker images and asserts output parity:
  - panora-versioning-pipe:bash  — legacy bash calculate-version.sh
  - panora-versioning-pipe:go    — Go binary (calc-version subcommand)

This is the gold-standard technique documented in
references/integration-testing.md § "The dual-run technique".

Usage pattern for GO-10 config-parser:
  from test_dual_run_calc_version import dual_run_calc_version, DualRunResult
  result = dual_run_calc_version(bash_image, go_image, workspace, scenario="development_release")
  assert result.bash_bump == result.go_bump
  assert result.bash_next_version == result.go_next_version

# Pattern for GO-10: see test_dual_run_calc_version.py — DualRunResult + dual_run_calc_version()
"""

from __future__ import annotations

import os
import shutil
import subprocess
import textwrap
import uuid
from dataclasses import dataclass
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

GO_IMAGE_TAG = os.environ.get(
    "PANORA_GO_IMAGE", "panora-versioning-pipe:go-calc-version-test"
)
BASH_IMAGE_TAG = os.environ.get(
    "PANORA_BASH_IMAGE", "panora-versioning-pipe:bash-dual-run-test"
)

BASH_CALC_VERSION_SCRIPT = "/pipe/bash-calc-version-wrapper.sh"
GO_BINARY = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


# =============================================================================
# Image fixtures (module-scoped: build once per test session)
# =============================================================================


@pytest.fixture(scope="module")
def bash_image() -> str:
    result = subprocess.run(
        [
            "docker", "build",
            "-f", str(REPO_ROOT / "tests" / "integration" / "Dockerfile.bash"),
            "-t", BASH_IMAGE_TAG,
            str(REPO_ROOT),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        pytest.fail(
            f"bash docker build failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return BASH_IMAGE_TAG


@pytest.fixture(scope="module")
def go_image() -> str:
    result = subprocess.run(
        ["docker", "build", "-t", GO_IMAGE_TAG, str(REPO_ROOT)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        pytest.fail(
            f"go docker build failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return GO_IMAGE_TAG


# =============================================================================
# Repo/fixture helpers (shared with test_go_calc_version.py conventions)
# =============================================================================


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


def _write_merged_config(workspace: Path) -> None:
    """Write pre-merged config for the Go image (reads /tmp/.versioning-merged.yml directly).

    Schema mirrors the repo's own .versioning.yml: epoch+major+patch (3 slots),
    hotfix_counter disabled, timestamp disabled. This is the canonical schema
    used for dual-run comparison.
    """
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    content = textwrap.dedent("""\
        commits:
          format: "conventional"
        version:
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


def _write_versioning_yml(workspace: Path) -> None:
    """Write a .versioning.yml in the workspace root for the bash image.

    The bash config-parser.sh regenerates the merged config at runtime by
    reading defaults.yml + this file. It does NOT use a pre-merged config.

    Schema matches the repo's own .versioning.yml: epoch+major+patch (3 slots),
    hotfix_counter disabled, timestamp disabled — same as _write_merged_config().
    """
    content = textwrap.dedent("""\
        commits:
          format: "conventional"
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


def _read_tmp(workspace: Path, filename: str) -> str:
    p = workspace / "tmp" / filename
    return p.read_text().strip() if p.exists() else ""


def _run_bash_calc_version(
    image: str,
    workspace: Path,
) -> subprocess.CompletedProcess:
    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)
    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-v", f"{tmp_dir}:/tmp",
            "-w", "/workspace",
            "--entrypoint", BASH_CALC_VERSION_SCRIPT,
            image,
        ],
        capture_output=True,
        text=True,
    )


def _run_go_calc_version(
    image: str,
    workspace: Path,
) -> subprocess.CompletedProcess:
    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)
    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-v", f"{tmp_dir}:/tmp",
            "-w", "/workspace",
            "--entrypoint", GO_BINARY,
            image,
            "calc-version",
        ],
        capture_output=True,
        text=True,
    )


# =============================================================================
# Public helper — reusable by GO-10 config-parser tests
# =============================================================================


@dataclass
class DualRunResult:
    """Output of a dual-run comparison.

    Attributes
    ----------
    bash_bump:          bump_type.txt from bash image
    go_bump:            bump_type.txt from Go image
    bash_next_version:  next_version.txt from bash image
    go_next_version:    next_version.txt from Go image
    bash_exit_code:     exit code from bash container
    go_exit_code:       exit code from Go container
    bash_stdout:        full stdout from bash container
    go_stdout:          full stdout from Go container
    bump_match:         True if both bumps are equal
    version_match:      True if both next_versions are equal
    exit_code_match:    True if both exit codes are equal
    """

    bash_bump: str
    go_bump: str
    bash_next_version: str
    go_next_version: str
    bash_exit_code: int
    go_exit_code: int
    bash_stdout: str
    go_stdout: str

    @property
    def bump_match(self) -> bool:
        return self.bash_bump == self.go_bump

    @property
    def version_match(self) -> bool:
        return self.bash_next_version == self.go_next_version

    @property
    def exit_code_match(self) -> bool:
        return self.bash_exit_code == self.go_exit_code

    def divergence_report(self) -> str:
        lines = ["=== DUAL-RUN DIVERGENCE REPORT ==="]
        if not self.exit_code_match:
            lines.append(f"EXIT CODE: bash={self.bash_exit_code}  go={self.go_exit_code}")
        if not self.bump_match:
            lines.append(f"BUMP TYPE: bash={self.bash_bump!r}  go={self.go_bump!r}")
        if not self.version_match:
            lines.append(
                f"NEXT VERSION: bash={self.bash_next_version!r}  go={self.go_next_version!r}"
            )
        lines.append("--- bash stdout ---")
        lines.append(self.bash_stdout or "(empty)")
        lines.append("--- go stdout ---")
        lines.append(self.go_stdout or "(empty)")
        return "\n".join(lines)


def dual_run_calc_version(
    bash_image: str,
    go_image: str,
    workspace: Path,
    *,
    scenario: str = "development_release",
    initial_tag: str | None = "v1.0.0",
    commit_msg: str = "feat: test",
    write_config: bool = True,
) -> DualRunResult:
    """Run calc-version against both bash and Go images and return a DualRunResult.

    Reusable fixture function for GO-10 config-parser tests and beyond.

    Parameters
    ----------
    bash_image:   Docker image tag for the bash legacy image.
    go_image:     Docker image tag for the Go image.
    workspace:    Temporary directory (will be seeded with a git repo). The function
                  creates two sub-workspaces (bash_ws / go_ws) so output files don't
                  overwrite each other between runs.
    scenario:     Value to write into scenario.env (default: development_release).
    initial_tag:  Git tag to create on initial commit (default: v1.0.0).
    commit_msg:   Commit message for the change commit.
    write_config: If True, writes a standard .versioning-merged.yml. Set False
                  if the caller has already written a custom config to workspace/tmp
                  before calling (the function will copy it to both sub-workspaces).

    Returns
    -------
    DualRunResult with outputs from both runtimes. Does NOT assert — callers assert.
    """
    bash_ws = workspace / "bash_ws"
    go_ws = workspace / "go_ws"
    bash_ws.mkdir()
    go_ws.mkdir()

    for ws in (bash_ws, go_ws):
        _seed_repo(ws, initial_tag=initial_tag, commit_msg=commit_msg)
        _write_scenario_env(ws, scenario=scenario)

    if write_config:
        # bash: write .versioning.yml at workspace root — config-parser.sh regenerates
        # the merged config at runtime from defaults.yml + this file.
        _write_versioning_yml(bash_ws)
        # go: write pre-merged config — the Go binary reads /tmp/.versioning-merged.yml directly.
        _write_merged_config(go_ws)

    bash_result = _run_bash_calc_version(bash_image, bash_ws)
    go_result = _run_go_calc_version(go_image, go_ws)

    return DualRunResult(
        bash_bump=_read_tmp(bash_ws, "bump_type.txt"),
        go_bump=_read_tmp(go_ws, "bump_type.txt"),
        bash_next_version=_read_tmp(bash_ws, "next_version.txt"),
        go_next_version=_read_tmp(go_ws, "next_version.txt"),
        bash_exit_code=bash_result.returncode,
        go_exit_code=go_result.returncode,
        bash_stdout=bash_result.stdout,
        go_stdout=go_result.stdout,
    )


# =============================================================================
# TestDualRunCalcVersion — proof-of-concept: 3 scenarios
# =============================================================================


class TestDualRunCalcVersion:
    """Dual-run proof-of-concept: bash vs Go for development_release scenarios.

    Schema used: epoch+major+patch (3 slots), hotfix_counter disabled, tag_prefix_v=true.
    This matches the repo's own .versioning.yml — the canonical reference schema.

    Cold start (no initial_tag): both runtimes start from scratch.

    Scenarios:
      1. feat:  → bump_type=minor. Both agree — v0.0.1 (FINDING MEDIUM fixed in GO-10).
      2. fix:   → bump_type=patch. Both agree — v0.0.1.
      3. chore: → no bump, no version. Both agree.

    GO-10 made NextVersion schema-aware (slot-based, no Masterminds/semver).
    Both runtimes now produce v0.0.1 for feat cold start on epoch+major+patch schema.
    """

    def test_feat_development_release(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """feat: → bump_type=minor en ambos. next_version=v0.0.1 en ambos (FINDING MEDIUM fixeado)."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()

        result = dual_run_calc_version(
            bash_image,
            go_image,
            workspace,
            initial_tag=None,
            commit_msg="feat: add new capability",
        )

        assert result.exit_code_match, result.divergence_report()
        assert result.bash_exit_code == 0, f"bash exited {result.bash_exit_code}\n{result.bash_stdout}"
        assert result.go_exit_code == 0, f"go exited {result.go_exit_code}\n{result.go_stdout}"

        assert result.bump_match, result.divergence_report()
        assert result.bash_bump == "minor", (
            f"bash bump={result.bash_bump!r}, expected 'minor'\n" + result.divergence_report()
        )

        assert result.version_match, result.divergence_report()

    def test_fix_development_release(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """fix: → bump_type=patch, next_version=v0.0.1 en ambos."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()

        result = dual_run_calc_version(
            bash_image,
            go_image,
            workspace,
            initial_tag=None,
            commit_msg="fix: correct edge case",
        )

        assert result.exit_code_match, result.divergence_report()
        assert result.bash_exit_code == 0, f"bash exited {result.bash_exit_code}\n{result.bash_stdout}"
        assert result.go_exit_code == 0, f"go exited {result.go_exit_code}\n{result.go_stdout}"

        assert result.bump_match, result.divergence_report()
        assert result.bash_bump == "patch", (
            f"bash bump={result.bash_bump!r}, expected 'patch'\n" + result.divergence_report()
        )

        assert result.version_match, result.divergence_report()
        assert result.bash_next_version == "v0.0.1", (
            f"bash next_version={result.bash_next_version!r}, expected 'v0.0.1'\n"
            + result.divergence_report()
        )

    def test_chore_development_release(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """chore: → no bump, no version. Both bash and Go agree — passes cleanly."""
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()

        result = dual_run_calc_version(
            bash_image,
            go_image,
            workspace,
            initial_tag=None,
            commit_msg="chore: update dependencies",
        )

        assert result.exit_code_match, result.divergence_report()
        assert result.bash_exit_code == 0, f"bash exited {result.bash_exit_code}\n{result.bash_stdout}"
        assert result.go_exit_code == 0, f"go exited {result.go_exit_code}\n{result.go_stdout}"

        assert result.bump_match, result.divergence_report()
        assert result.bash_bump in ("none", ""), (
            f"bash bump={result.bash_bump!r}, expected 'none' or ''\n" + result.divergence_report()
        )
