"""Dual-run integration test for config-parser: bash vs Go semantic parity.

For EACH fixture in tests/fixtures/*.yml (21 fixtures):
  1. Run bash config-parser (load_config) → capture /tmp/.versioning-merged.yml
  2. Run Go config-parse subcommand     → capture /tmp/.versioning-merged.yml
  3. Parse both outputs to dicts and assert semantic equality (struct-level)

Accepted format deltas (not blockers) documented here:
  - Comments: yq preserves inline comments from source files; yaml.v3 does not.
    Getters in config-parser.sh never read comments → irrelevant.
  - Unicode escapes: yq mixes \\UXXXX escapes with raw UTF-8; yaml.v3 normalizes
    to UTF-8. Same code point, different byte representation → irrelevant.
  - Key ordering: yaml.v3 may reorder keys. Getters look up by key → irrelevant.

Any other difference (values, arrays, overrides, commit_types content) is a
blocker and must be fixed before merging.

Before Go implementation tests fail with exit 42 ("not implemented yet").
After implementation tests MUST pass with zero semantic divergence.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

import pytest
import yaml

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
# Semantic comparison helpers
# =============================================================================


def _parse_merged_yaml(content: str) -> dict[str, Any]:
    """Parse YAML string to dict. Returns {} on empty or None content."""
    if not content:
        return {}
    result = yaml.safe_load(content)
    return result if isinstance(result, dict) else {}


def _normalize_commit_types(commit_types: list[dict]) -> list[dict]:
    """Normalize commit_types for comparison: sort by name, strip description field.

    The description field is metadata only — no getter reads it. The bash output
    includes it from commit-types.yml; the Go output may omit it if not in the
    Config struct. We strip it from both sides so comparison focuses on functional fields.
    """
    if not commit_types:
        return []
    normalized = []
    for ct in commit_types:
        entry = {k: v for k, v in ct.items() if k != "description"}
        normalized.append(entry)
    return sorted(normalized, key=lambda x: x.get("name", ""))


def _semantic_diff(bash_raw: str, go_raw: str) -> str:
    """Compare bash and Go merged configs semantically.

    Returns empty string if semantically equal.
    Returns a human-readable diff description if not.

    Accepted format deltas (stripped before comparison):
      - YAML comments
      - Unicode escape vs UTF-8 (handled by yaml.safe_load)
      - commit_types.description field (metadata only)
    """
    bash_cfg = _parse_merged_yaml(bash_raw)
    go_cfg = _parse_merged_yaml(go_raw)

    if not bash_cfg:
        return "bash produced empty/unparseable merged config"
    if not go_cfg:
        return "Go produced empty/unparseable merged config"

    # Normalize commit_types (strip description, sort by name)
    bash_cfg["commit_types"] = _normalize_commit_types(bash_cfg.get("commit_types", []))
    go_cfg["commit_types"] = _normalize_commit_types(go_cfg.get("commit_types", []))

    # commit_type_overrides is consumed by the merge process and should NOT
    # appear in the final output (bash strips it after applying). If both agree
    # on absence, that's fine. If one has it and the other doesn't, report.
    # We only compare its presence/absence here, not its content.
    bash_has_overrides = "commit_type_overrides" in bash_cfg
    go_has_overrides = "commit_type_overrides" in go_cfg
    if bash_has_overrides != go_has_overrides:
        return (
            f"commit_type_overrides presence mismatch: "
            f"bash={bash_has_overrides} go={go_has_overrides}"
        )

    # Strip commit_type_overrides from both before deep comparison
    bash_cfg.pop("commit_type_overrides", None)
    go_cfg.pop("commit_type_overrides", None)

    # Deep equality check
    if bash_cfg == go_cfg:
        return ""

    # Build a detailed diff report
    lines = ["=== SEMANTIC MISMATCH ==="]
    all_keys = set(bash_cfg.keys()) | set(go_cfg.keys())
    for key in sorted(all_keys):
        bval = bash_cfg.get(key)
        gval = go_cfg.get(key)
        if bval != gval:
            lines.append(f"\nKey: {key!r}")
            lines.append(f"  bash: {bval!r}")
            lines.append(f"  go:   {gval!r}")
    return "\n".join(lines)


# =============================================================================
# Docker helpers
# =============================================================================


def _init_git_repo(workspace: Path) -> None:
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


def _dual_run(
    bash_image: str,
    go_image: str,
    workspace: Path,
    *,
    fixture_path: Path | None = None,
    raw_versioning_yml: str | None = None,
) -> tuple[subprocess.CompletedProcess, subprocess.CompletedProcess, str, str]:
    """Run bash + Go config-parser on the same input.

    Returns (bash_proc, go_proc, bash_merged_content, go_merged_content).
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


# =============================================================================
# All 21 fixtures — parametrized dual-run (semantic equality)
# =============================================================================


def _fixture_files() -> list[Path]:
    return sorted(FIXTURES_DIR.glob("*.yml"))


@pytest.mark.parametrize(
    "fixture_path",
    _fixture_files(),
    ids=[p.stem for p in _fixture_files()],
)
class TestConfigParserDualRunFixtures:
    r"""For each fixture, bash and Go must produce semantically equal merged YAML.

    Accepted format deltas (documented in PR "Behavior delta vs bash"):
      - YAML comments from source files
      - Unicode escape notation (\UXXXX vs raw UTF-8)
      - Key ordering
      - commit_types.description field (metadata, no getter reads it)
    """

    def test_dual_run_semantic_equal(
        self,
        bash_image: str,
        go_image: str,
        tmp_path: Path,
        fixture_path: Path,
    ) -> None:
        workspace = tmp_path / fixture_path.stem
        workspace.mkdir()

        bash_proc, go_proc, bash_merged, go_merged = _dual_run(
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

        diff = _semantic_diff(bash_merged, go_merged)
        assert diff == "", (
            f"Semantic mismatch for fixture {fixture_path.name}:\n{diff}"
        )


# =============================================================================
# commit_type_overrides — explicit scenarios
# =============================================================================


class TestCommitTypeOverrides:
    """Validate commit_type_overrides: update existing, add new, change bump."""

    def test_override_update_emoji(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        workspace = (tmp_path / "override-emoji").mkdir() or tmp_path / "override-emoji"
        yml = (
            'commits:\n  format: "conventional"\n'
            "commit_type_overrides:\n  feat:\n    emoji: \"⭐\"\n"
        )
        bash_proc, go_proc, bash_merged, go_merged = _dual_run(
            bash_image, go_image, workspace, raw_versioning_yml=yml
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        diff = _semantic_diff(bash_merged, go_merged)
        assert diff == "", f"Semantic mismatch:\n{diff}"
        # Verify the override was actually applied
        go_cfg = _parse_merged_yaml(go_merged)
        feat = next((ct for ct in go_cfg.get("commit_types", []) if ct["name"] == "feat"), None)
        assert feat is not None, "feat commit type missing"
        assert feat.get("emoji") == "⭐", f"feat emoji not overridden: {feat}"

    def test_override_add_new_type(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        workspace = (tmp_path / "override-add").mkdir() or tmp_path / "override-add"
        yml = (
            'commits:\n  format: "conventional"\n'
            "commit_type_overrides:\n  newtype:\n    bump: \"patch\"\n    emoji: \"🆕\"\n"
        )
        bash_proc, go_proc, bash_merged, go_merged = _dual_run(
            bash_image, go_image, workspace, raw_versioning_yml=yml
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        diff = _semantic_diff(bash_merged, go_merged)
        assert diff == "", f"Semantic mismatch:\n{diff}"
        # Verify new type was appended
        go_cfg = _parse_merged_yaml(go_merged)
        newtype = next(
            (ct for ct in go_cfg.get("commit_types", []) if ct["name"] == "newtype"), None
        )
        assert newtype is not None, "newtype was not added"
        assert newtype.get("bump") == "patch"

    def test_override_bump_change(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        """custom-types fixture: docs bump→none, feat emoji, add infra type."""
        workspace = (tmp_path / "override-bump").mkdir() or tmp_path / "override-bump"
        bash_proc, go_proc, bash_merged, go_merged = _dual_run(
            bash_image, go_image, workspace, fixture_path=FIXTURES_DIR / "custom-types.yml"
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        diff = _semantic_diff(bash_merged, go_merged)
        assert diff == "", f"Semantic mismatch:\n{diff}"
        go_cfg = _parse_merged_yaml(go_merged)
        docs = next((ct for ct in go_cfg.get("commit_types", []) if ct["name"] == "docs"), None)
        assert docs is not None
        assert docs.get("bump") == "none", f"docs bump should be none: {docs}"


# =============================================================================
# Fallback chain: absent .versioning.yml
# =============================================================================


class TestFallbackChain:
    def test_no_versioning_yml(
        self, bash_image: str, go_image: str, tmp_path: Path
    ) -> None:
        workspace = (tmp_path / "no-yml").mkdir() or tmp_path / "no-yml"
        bash_proc, go_proc, bash_merged, go_merged = _dual_run(
            bash_image, go_image, workspace
        )
        assert bash_proc.returncode == 0
        assert go_proc.returncode == 0
        assert bash_merged != ""
        assert go_merged != ""
        diff = _semantic_diff(bash_merged, go_merged)
        assert diff == "", f"Semantic mismatch (no .versioning.yml):\n{diff}"


# =============================================================================
# Error handling: malformed YAML
# =============================================================================


class TestErrorHandling:
    def test_malformed_yaml_exits_nonzero(
        self, go_image: str, tmp_path: Path
    ) -> None:
        go_ws = tmp_path / "malformed_go"
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
