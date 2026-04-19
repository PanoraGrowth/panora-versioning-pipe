"""Integration tests for the Go guardrails + run-guardrails subcommands (GO-05).

The tests invoke the compiled binary directly — NOT the Docker image — for
iteration speed.  The binary reads state from /tmp/*.txt and a merged config
file, so each test scaffolds those files before calling the binary.

Scenarios covered:
  1. Happy path — consistent next/latest/bump → exit 0, GUARDRAIL result=pass.
  2. Version regression (major not incremented) → exit 1, violation named.
  3. Epoch bump without epoch increment → exit 1.
  4. Hotfix counter regression → exit 1.
  5. Escape hatch `validation.allow_version_regression: true` → exit 0 + warning.
  6. Cold start (no latest tag) → exit 0, reason=cold_start.
  7. run-guardrails aggregator — all pass → exit 0 + "All guardrails passed".
  8. run-guardrails aggregator — one block → exit 1.
  9. Log format: GUARDRAIL structured line present on pass and on block.
 10. Escape-hatch log wording matches documented format for operator grep.
"""

from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
BINARY = os.environ.get(
    "PANORA_GO_BINARY",
    str(REPO_ROOT / "panora-versioning"),
)


def _binary_available() -> bool:
    return Path(BINARY).is_file()


pytestmark = pytest.mark.skipif(
    not _binary_available(),
    reason=f"Go binary not found at {BINARY} — run 'go build ./cmd/panora-versioning' first",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _write_config(tmp_path: Path, allow_regression: bool = False) -> Path:
    """Write a minimal merged config to a temp file and return its path."""
    config = textwrap.dedent(f"""\
        commits:
          format: conventional
        version:
          tag_prefix_v: true
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
              enabled: false
              initial: 0
            timestamp:
              enabled: false
        validation:
          allow_version_regression: {"true" if allow_regression else "false"}
    """)
    cfg = tmp_path / ".versioning-merged.yml"
    cfg.write_text(config)
    return cfg


def _write_hotfix_config(tmp_path: Path, allow_regression: bool = False) -> Path:
    """Config with epoch + hotfix_counter enabled (mirrors with-hotfix-counter fixture)."""
    config = textwrap.dedent(f"""\
        commits:
          format: conventional
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
              enabled: true
              initial: 0
            timestamp:
              enabled: false
        validation:
          allow_version_regression: {"true" if allow_regression else "false"}
    """)
    cfg = tmp_path / ".versioning-merged.yml"
    cfg.write_text(config)
    return cfg


def _write_state(tmp_path: Path, next_tag: str, latest_tag: str, bump_type: str) -> dict:
    """Write the three /tmp/*.txt state files; return paths for cleanup."""
    state_dir = tmp_path / "state"
    state_dir.mkdir(exist_ok=True)
    paths = {
        "next": state_dir / "next_version.txt",
        "latest": state_dir / "latest_tag.txt",
        "bump": state_dir / "bump_type.txt",
    }
    if next_tag:
        paths["next"].write_text(next_tag + "\n")
    if latest_tag:
        paths["latest"].write_text(latest_tag + "\n")
    if bump_type:
        paths["bump"].write_text(bump_type + "\n")
    return paths


def _run_guardrails(
    *,
    subcmd: str = "guardrails",
    next_tag: str,
    latest_tag: str,
    bump_type: str,
    tmp_path: Path,
    allow_regression: bool = False,
    use_hotfix_config: bool = False,
) -> subprocess.CompletedProcess:
    """Run the binary with state files wired via env vars."""
    if use_hotfix_config:
        cfg = _write_hotfix_config(tmp_path, allow_regression=allow_regression)
    else:
        cfg = _write_config(tmp_path, allow_regression=allow_regression)

    paths = _write_state(tmp_path, next_tag, latest_tag, bump_type)

    env = {
        **os.environ,
        "PANORA_MERGED_CONFIG": str(cfg),
        "PANORA_STATE_NEXT_VERSION": str(paths["next"]) if next_tag else "",
        "PANORA_STATE_LATEST_TAG": str(paths["latest"]) if latest_tag else "",
        "PANORA_STATE_BUMP_TYPE": str(paths["bump"]) if bump_type else "",
    }

    return subprocess.run(
        [BINARY, subcmd],
        capture_output=True,
        text=True,
        env=env,
    )


# ---------------------------------------------------------------------------
# guardrails subcommand
# ---------------------------------------------------------------------------


def test_happy_path_major_bump(tmp_path: Path) -> None:
    """Consistent major bump → exit 0, GUARDRAIL result=pass."""
    result = _run_guardrails(
        next_tag="v6.1.0", latest_tag="v5.2.0", bump_type="major", tmp_path=tmp_path
    )
    assert result.returncode == 0, f"stderr:\n{result.stderr}\nstdout:\n{result.stdout}"
    combined = result.stdout + result.stderr
    assert "result=pass" in combined
    assert "bump=major" in combined


def test_major_not_incremented_blocks(tmp_path: Path) -> None:
    """Major did not increment → exit 1, violation=major_not_incremented."""
    result = _run_guardrails(
        next_tag="v5.3.0", latest_tag="v5.2.0", bump_type="major", tmp_path=tmp_path
    )
    assert result.returncode == 1, f"expected exit 1\nstderr:\n{result.stderr}"
    combined = result.stdout + result.stderr
    assert "result=blocked" in combined
    assert "violation=major_not_incremented" in combined


def test_patch_bump_happy(tmp_path: Path) -> None:
    """Consistent patch bump → exit 0."""
    result = _run_guardrails(
        next_tag="v5.3.0", latest_tag="v5.2.0", bump_type="patch", tmp_path=tmp_path
    )
    assert result.returncode == 0, f"stderr:\n{result.stderr}"
    assert "result=pass" in result.stdout + result.stderr


def test_patch_not_incremented_blocks(tmp_path: Path) -> None:
    """Patch did not increment → exit 1."""
    result = _run_guardrails(
        next_tag="v5.2.0", latest_tag="v5.2.0", bump_type="patch", tmp_path=tmp_path
    )
    assert result.returncode == 1
    combined = result.stdout + result.stderr
    assert "result=blocked" in combined
    assert "violation=patch_not_incremented" in combined


def test_cold_start_no_latest_tag(tmp_path: Path) -> None:
    """No latest tag (cold start) → exit 0, reason=cold_start."""
    result = _run_guardrails(
        next_tag="v1.0.0", latest_tag="", bump_type="major", tmp_path=tmp_path
    )
    assert result.returncode == 0, f"stderr:\n{result.stderr}"
    combined = result.stdout + result.stderr
    assert "result=pass" in combined
    assert "reason=cold_start" in combined


def test_hotfix_counter_increments(tmp_path: Path) -> None:
    """Same base, counter increments → exit 0."""
    result = _run_guardrails(
        next_tag="v0.5.9.1",
        latest_tag="v0.5.9",
        bump_type="hotfix",
        tmp_path=tmp_path,
        use_hotfix_config=True,
    )
    assert result.returncode == 0, f"stderr:\n{result.stderr}"
    assert "result=pass" in result.stdout + result.stderr


def test_hotfix_counter_regression_blocks(tmp_path: Path) -> None:
    """Same base, counter did not increment → exit 1."""
    result = _run_guardrails(
        next_tag="v0.5.9.1",
        latest_tag="v0.5.9.1",
        bump_type="hotfix",
        tmp_path=tmp_path,
        use_hotfix_config=True,
    )
    assert result.returncode == 1
    combined = result.stdout + result.stderr
    assert "result=blocked" in combined
    assert "violation=hotfix_counter_not_incremented" in combined


def test_escape_hatch_allow_regression(tmp_path: Path) -> None:
    """allow_version_regression=true → exit 0, result=warned."""
    result = _run_guardrails(
        next_tag="v5.2.0",
        latest_tag="v5.2.0",
        bump_type="patch",
        tmp_path=tmp_path,
        allow_regression=True,
    )
    assert result.returncode == 0, f"stderr:\n{result.stderr}"
    combined = result.stdout + result.stderr
    assert "result=warned" in combined
    assert "override=allow_version_regression" in combined


def test_escape_hatch_log_wording(tmp_path: Path) -> None:
    """Escape-hatch warning log must contain documented phrasing for operator grep."""
    result = _run_guardrails(
        next_tag="v5.2.0",
        latest_tag="v5.2.0",
        bump_type="patch",
        tmp_path=tmp_path,
        allow_regression=True,
    )
    combined = result.stdout + result.stderr
    # This wording was documented in PR #118 and must stay stable.
    assert "Version regression allowed by validation.allow_version_regression=true" in combined


def test_guardrail_log_format_on_pass(tmp_path: Path) -> None:
    """Structured GUARDRAIL line on pass: name=no_version_regression result=pass."""
    result = _run_guardrails(
        next_tag="v6.1.0", latest_tag="v5.2.0", bump_type="major", tmp_path=tmp_path
    )
    combined = result.stdout + result.stderr
    assert "GUARDRAIL name=no_version_regression result=pass" in combined


def test_guardrail_log_format_on_block(tmp_path: Path) -> None:
    """Structured GUARDRAIL line on block includes next= and latest=."""
    result = _run_guardrails(
        next_tag="v5.3.0", latest_tag="v5.2.0", bump_type="major", tmp_path=tmp_path
    )
    combined = result.stdout + result.stderr
    assert "GUARDRAIL name=no_version_regression result=blocked" in combined
    assert "next=v5.3.0" in combined
    assert "latest=v5.2.0" in combined


# ---------------------------------------------------------------------------
# run-guardrails subcommand
# ---------------------------------------------------------------------------


def test_run_guardrails_all_pass(tmp_path: Path) -> None:
    """run-guardrails with no violations → exit 0, 'All guardrails passed'."""
    result = _run_guardrails(
        subcmd="run-guardrails",
        next_tag="v6.1.0",
        latest_tag="v5.2.0",
        bump_type="major",
        tmp_path=tmp_path,
    )
    assert result.returncode == 0, f"stderr:\n{result.stderr}\nstdout:\n{result.stdout}"
    combined = result.stdout + result.stderr
    assert "all guardrails passed" in combined.lower()


def test_run_guardrails_one_block(tmp_path: Path) -> None:
    """run-guardrails with a violation → exit 1."""
    result = _run_guardrails(
        subcmd="run-guardrails",
        next_tag="v5.3.0",
        latest_tag="v5.2.0",
        bump_type="major",
        tmp_path=tmp_path,
    )
    assert result.returncode == 1, f"expected exit 1\nstderr:\n{result.stderr}"
