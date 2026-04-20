"""Dual-run integration test for config-parser: bash vs Go parity.

For EACH fixture in tests/fixtures/*.yml (21 fixtures):
  1. Run bash config-parser (load_config) → capture /tmp/.versioning-merged.yml
  2. Run Go config-parse subcommand     → capture /tmp/.versioning-merged.yml
  3. Assert diff is EMPTY (byte-identical output)

Also covers:
  - commit_type_overrides (add, update, remove by name)
  - Absent .versioning.yml → fallback to defaults + commit-types
  - Malformed YAML → exit 1 with clear error

Before Go implementation, tests fail with "binary not implemented yet" (exit 42).
After implementation, tests MUST pass with empty diff.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPO_ROOT / "tests" / "fixtures"

GO_IMAGE_TAG = os.environ.get(
    "PANORA_GO_IMAGE", "panora-versioning-pipe:go-config-parser-test"
)
BASH_IMAGE_TAG = os.environ.get(
    "PANORA_BASH_IMAGE", "panora-versioning-pipe:bash-config-parser-test"
)

BASH_CONFIG_PARSER_SCRIPT = "/pipe/bash-config-parser-wrapper.sh"
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
# Helpers
# =============================================================================


def _init_git_repo(workspace: Path) -> None:
    """Initialize a minimal git repo so config-parser.sh can find the repo root."""
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
        ["git", "commit", "-m", "chore: seed"],
        cwd=workspace, check=True, capture_output=True,
    )


def _run_bash_config_parser(
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
            "--entrypoint", BASH_CONFIG_PARSER_SCRIPT,
            image,
        ],
        capture_output=True,
        text=True,
    )


def _run_go_config_parser(
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
            "config-parse",
        ],
        capture_output=True,
        text=True,
    )


def _read_merged_config(workspace: Path) -> str:
    p = workspace / "tmp" / ".versioning-merged.yml"
    return p.read_text() if p.exists() else ""


def _dual_run_config_parser(
    bash_image: str,
    go_image: str,
    workspace: Path,
    *,
    fixture_path: Path | None = None,
    raw_versioning_yml: str | None = None,
) -> tuple[subprocess.CompletedProcess, subprocess.CompletedProcess, str, str]:
    """Run bash + Go config-parser on the same input.

    Either fixture_path (copy as .versioning.yml) or raw_versioning_yml (write inline)
    must be provided. If neither, no .versioning.yml is written (fallback test).

    Returns (bash_proc, go_proc, bash_merged, go_merged).
    """
    bash_ws = workspace / "bash_ws"
    go_ws = workspace / "go_ws"
    bash_ws.mkdir()
    go_ws.mkdir()

    for ws in (bash_ws, go_ws):
        _init_git_repo(ws)

    if fixture_path is not None:
        for ws in (bash_ws, go_ws):
            shutil.copy(fixture_path, ws / ".versioning.yml")
    elif raw_versioning_yml is not None:
        for ws in (bash_ws, go_ws):
            (ws / ".versioning.yml").write_text(raw_versioning_yml)
    # else: no .versioning.yml → fallback to defaults+commit-types

    bash_proc = _run_bash_config_parser(bash_image, bash_ws)
    go_proc = _run_go_config_parser(go_image, go_ws)

    bash_merged = _read_merged_config(bash_ws)
    go_merged = _read_merged_config(go_ws)

    return bash_proc, go_proc, bash_merged, go_merged


def _diff_report(fixture_name: str, bash_merged: str, go_merged: str) -> str:
    import difflib
    diff = list(difflib.unified_diff(
        bash_merged.splitlines(keepends=True),
        go_merged.splitlines(keepends=True),
        fromfile=f"bash/{fixture_name}",
        tofile=f"go/{fixture_name}",
    ))
    if not diff:
        return ""
    return "".join(diff)


# =============================================================================
# All 21 fixtures — parametrized dual-run (byte-identical)
# =============================================================================


def _fixture_files() -> list[Path]:
    return sorted(FIXTURES_DIR.glob("*.yml"))


@pytest.mark.parametrize(
    "fixture_path",
    _fixture_files(),
    ids=[p.stem for p in _fixture_files()],
)
class TestConfigParserDualRunFixtures:
    """For each fixture, bash and Go must produce byte-identical merged YAML."""

    def test_dual_run_byte_identical(
        self,
        bash_image: str,
        go_image: str,
        tmp_path: Path,
        fixture_path: Path,
    ) -> None:
        workspace = tmp_path / fixture_path.stem
        workspace.mkdir()

        bash_proc, go_proc, bash_merged, go_merged = _dual_run_config_parser(
            bash_image, go_image, workspace, fixture_path=fixture_path
        )

        assert bash_proc.returncode == 0, (
            f"bash failed for fixture {fixture_path.name}\n"
            f"stdout: {bash_proc.stdout}\nstderr: {bash_proc.stderr}"
        )
        assert go_proc.returncode == 0, (
            f"Go failed for fixture {fixture_path.name} (exit {go_proc.returncode})\n"
            f"stdout: {go_proc.stdout}\nstderr: {go_proc.stderr}"
        )
        assert bash_merged != "", f"bash produced empty merged config for {fixture_path.name}"
        assert go_merged != "", f"Go produced empty merged config for {fixture_path.name}"

        diff = _diff_report(fixture_path.stem, bash_merged, go_merged)
        assert diff == "", (
            f"Dual-run diff non-empty for fixture {fixture_path.name}:\n{diff}"
        )


# =============================================================================
# Specific scenarios: commit_type_overrides
# =============================================================================


class TestCommitTypeOverrides:
    """Validate commit_type_overrides semantics: update, add, remove."""

    def test_override_update_field(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """Updating an existing type's emoji — non-overridden fields preserved."""
        workspace = tmp_path / "override-update"
        workspace.mkdir()
        yml = (
            'commits:\n  format: "conventional"\n'
            "commit_type_overrides:\n"
            "  feat:\n    emoji: \"⭐\"\n"
        )
        bash_proc, go_proc, bash_merged, go_merged = _dual_run_config_parser(
            bash_image, go_image, workspace, raw_versioning_yml=yml
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        diff = _diff_report("override-update", bash_merged, go_merged)
        assert diff == "", f"Dual-run diff:\n{diff}"

    def test_override_add_new_type(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """Adding a new commit type via overrides."""
        workspace = tmp_path / "override-add"
        workspace.mkdir()
        yml = (
            'commits:\n  format: "conventional"\n'
            "commit_type_overrides:\n"
            "  newtype:\n    bump: \"patch\"\n    emoji: \"🆕\"\n"
        )
        bash_proc, go_proc, bash_merged, go_merged = _dual_run_config_parser(
            bash_image, go_image, workspace, raw_versioning_yml=yml
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        diff = _diff_report("override-add", bash_merged, go_merged)
        assert diff == "", f"Dual-run diff:\n{diff}"

    def test_override_bump_to_none(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """Overriding docs bump to none — uses custom-types fixture."""
        workspace = tmp_path / "override-bump-none"
        workspace.mkdir()
        fixture = FIXTURES_DIR / "custom-types.yml"
        bash_proc, go_proc, bash_merged, go_merged = _dual_run_config_parser(
            bash_image, go_image, workspace, fixture_path=fixture
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        diff = _diff_report("custom-types-override", bash_merged, go_merged)
        assert diff == "", f"Dual-run diff:\n{diff}"


# =============================================================================
# Fallback: absent .versioning.yml
# =============================================================================


class TestFallbackChain:
    """When .versioning.yml is absent, merged output = defaults + commit-types only."""

    def test_no_versioning_yml_produces_output(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """Both bash and Go produce non-empty merged config with no .versioning.yml."""
        workspace = tmp_path / "no-yml"
        workspace.mkdir()
        bash_proc, go_proc, bash_merged, go_merged = _dual_run_config_parser(
            bash_image, go_image, workspace
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        assert bash_merged != ""
        assert go_merged != ""
        diff = _diff_report("no-versioning-yml", bash_merged, go_merged)
        assert diff == "", f"Dual-run diff:\n{diff}"


# =============================================================================
# Error handling: malformed YAML
# =============================================================================


class TestErrorHandling:
    """Malformed YAML must produce exit 1 with a clear error message."""

    def test_malformed_yaml_exits_nonzero(
        self, go_image: str, tmp_path: Path
    ) -> None:
        """Go config-parse must exit non-zero on malformed .versioning.yml."""
        workspace = tmp_path / "malformed"
        workspace.mkdir()
        go_ws = workspace / "go_ws"
        go_ws.mkdir()
        _init_git_repo(go_ws)
        (go_ws / ".versioning.yml").write_text(
            "commits:\n  format: [invalid_yaml\n    bad: nesting:\n"
        )
        proc = _run_go_config_parser(go_image, go_ws)
        assert proc.returncode != 0, (
            f"Go should fail on malformed YAML but exited {proc.returncode}\n"
            f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
        )
        combined = proc.stdout + proc.stderr
        assert combined.strip() != "", "Go must emit an error message for malformed YAML"
