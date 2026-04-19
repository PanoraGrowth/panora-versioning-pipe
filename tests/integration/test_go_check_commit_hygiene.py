"""Integration tests for the Go `check-commit-hygiene` subcommand (ticket GO-03).

Tests build the Docker image and assert on exit code + output produced by
`panora-versioning check-commit-hygiene`. These tests MUST fail before the Go
implementation exists (stubs return exit 42) and MUST pass after.

Contract preserved from scripts/lint/check-commit-hygiene.sh:
  - Modes: -m "msg", -f path, -p PR_NUMBER (PR mode replaced: no gh CLI, uses git range)
  - Forbidden patterns: [skip ci], [ci skip], [no ci], [skip actions], [actions skip],
    skip-checks: true (case-insensitive)
  - Exempt: subject starts with chore(release): or chore(hotfix):
  - Exempt: body contains X-Intentional-Skip-CI: true on its own line
  - Exit 0: clean; Exit 1: forbidden found; Exit 2: usage/arg error
  - Error output references CONTRIBUTING.md and lists safe alternatives

Behavior delta vs bash:
  - -p PR_NUMBER mode is NOT implemented in Go (it required gh CLI which is
    removed from the Go binary per ticket spec). The flag may return exit 2
    with a clear error message. No integration test for -p mode since it
    would require a real GitHub token.
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


def _run_hygiene(image: str, *args: str) -> subprocess.CompletedProcess:
    """Run panora-versioning check-commit-hygiene with given args."""
    return subprocess.run(
        [
            "docker", "run", "--rm",
            "--entrypoint", BINARY,
            image,
            "check-commit-hygiene",
            *args,
        ],
        capture_output=True,
        text=True,
    )


def _run_hygiene_with_file(image: str, tmp_path: Path, content: str) -> subprocess.CompletedProcess:
    """Write content to a temp file and run -f mode."""
    msg_file = tmp_path / f"msg-{uuid.uuid4().hex[:8]}.txt"
    msg_file.write_text(content)
    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{msg_file}:/tmp/commit_msg.txt",
            "--entrypoint", BINARY,
            image,
            "check-commit-hygiene",
            "-f", "/tmp/commit_msg.txt",
        ],
        capture_output=True,
        text=True,
    )


# =============================================================================
# Clean messages — exit 0
# =============================================================================

def test_clean_message_exits_0(go_image: str) -> None:
    """A clean conventional commit exits 0."""
    result = _run_hygiene(go_image, "-m", "feat: add new feature")
    assert result.returncode == 0, (
        f"Expected exit 0 for clean message\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_clean_message_no_warnings(go_image: str) -> None:
    """Clean message must produce no error output."""
    result = _run_hygiene(go_image, "-m", "fix: resolve crash in auth")
    assert result.returncode == 0
    assert "ERROR" not in result.stderr, f"Unexpected error output:\n{result.stderr}"


def test_safe_alternative_skip_dash_ci_exits_0(go_image: str) -> None:
    """'skip-ci' with a dash is a safe alternative and must not trigger the lint."""
    result = _run_hygiene(go_image, "-m", "docs: explain the skip-ci behavior of the pipe")
    assert result.returncode == 0, (
        f"skip-ci (with dash) should be allowed\nstderr:\n{result.stderr}"
    )


# =============================================================================
# Forbidden patterns — exit 1
# =============================================================================

@pytest.mark.parametrize("pattern,label", [
    ("[skip ci]", "[skip ci]"),
    ("[ci skip]", "[ci skip]"),
    ("[no ci]", "[no ci]"),
    ("[skip actions]", "[skip actions]"),
    ("[actions skip]", "[actions skip]"),
    ("skip-checks: true", "skip-checks: true"),
])
def test_forbidden_pattern_exits_1(go_image: str, pattern: str, label: str) -> None:
    """Each forbidden pattern must be detected and exit 1."""
    result = _run_hygiene(go_image, "-m", f"feat: something {pattern}")
    assert result.returncode == 1, (
        f"Expected exit 1 for pattern {label!r}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert "forbidden substring" in combined.lower(), (
        f"'forbidden substring' not in output for {label!r}\noutput:\n{combined}"
    )
    assert label in combined, (
        f"Pattern {label!r} not named in output\noutput:\n{combined}"
    )


# =============================================================================
# Case-insensitive detection
# =============================================================================

@pytest.mark.parametrize("variant", [
    "feat: foo [Skip CI]",
    "feat: foo [SKIP CI]",
    "feat: foo [Ci Skip]",
])
def test_case_insensitive_detection(go_image: str, variant: str) -> None:
    """Forbidden patterns must be detected case-insensitively."""
    result = _run_hygiene(go_image, "-m", variant)
    assert result.returncode == 1, (
        f"Expected exit 1 for case variant {variant!r}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


# =============================================================================
# Pipe-authored exemption (chore(release):, chore(hotfix):)
# =============================================================================

def test_chore_release_with_skip_ci_exits_0(go_image: str) -> None:
    """chore(release): subjects are allowed to contain [skip ci]."""
    result = _run_hygiene(
        go_image,
        "-m",
        "chore(release): update CHANGELOG for version v1.0.0 (minor bump) [skip ci]",
    )
    assert result.returncode == 0, (
        f"chore(release) with [skip ci] should be allowed\nstderr:\n{result.stderr}"
    )


def test_chore_hotfix_with_skip_ci_exits_0(go_image: str) -> None:
    """chore(hotfix): subjects are allowed to contain [skip ci]."""
    result = _run_hygiene(
        go_image,
        "-m",
        "chore(hotfix): update CHANGELOG [skip ci]",
    )
    assert result.returncode == 0, (
        f"chore(hotfix) with [skip ci] should be allowed\nstderr:\n{result.stderr}"
    )


# =============================================================================
# Intentional exemption trailer
# =============================================================================

def test_intentional_skip_ci_trailer_exits_0(go_image: str) -> None:
    """X-Intentional-Skip-CI: true trailer exempts the message."""
    msg = "docs: pure docs\n\nX-Intentional-Skip-CI: true\n[skip ci]\n"
    result = _run_hygiene(go_image, "-m", msg)
    assert result.returncode == 0, (
        f"X-Intentional-Skip-CI trailer should exempt the message\nstderr:\n{result.stderr}"
    )


# =============================================================================
# -f mode
# =============================================================================

def test_file_mode_clean_exits_0(go_image: str, tmp_path: Path) -> None:
    """-f mode: clean file exits 0."""
    result = _run_hygiene_with_file(go_image, tmp_path, "feat: clean message\n")
    assert result.returncode == 0, (
        f"Expected exit 0 for clean file\nstderr:\n{result.stderr}"
    )


def test_file_mode_dirty_exits_1(go_image: str, tmp_path: Path) -> None:
    """-f mode: file containing forbidden pattern exits 1."""
    result = _run_hygiene_with_file(go_image, tmp_path, "feat: bad message [skip ci]\n")
    assert result.returncode == 1, (
        f"Expected exit 1 for dirty file\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert "forbidden substring" in combined.lower(), (
        f"Missing 'forbidden substring' in output\noutput:\n{combined}"
    )


# =============================================================================
# Usage errors — exit 2
# =============================================================================

def test_no_args_exits_2(go_image: str) -> None:
    """No arguments must exit 2 with usage info."""
    result = _run_hygiene(go_image)
    assert result.returncode == 2, (
        f"Expected exit 2 with no args\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert "usage" in combined.lower() or "Usage" in combined, (
        f"Usage info not shown\noutput:\n{combined}"
    )


def test_help_flag_exits_0(go_image: str) -> None:
    """-h must print usage and exit 0."""
    result = _run_hygiene(go_image, "-h")
    assert result.returncode == 0, (
        f"Expected exit 0 for -h\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert "usage" in combined.lower() or "Usage" in combined, (
        f"Usage not printed for -h\noutput:\n{combined}"
    )


def test_unknown_flag_exits_2(go_image: str) -> None:
    """Unknown flag must exit 2."""
    result = _run_hygiene(go_image, "-z", "foo")
    assert result.returncode == 2, (
        f"Expected exit 2 for unknown flag\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


# =============================================================================
# Error output quality
# =============================================================================

def test_error_references_contributing_md(go_image: str) -> None:
    """Error output for dirty messages must reference CONTRIBUTING.md."""
    result = _run_hygiene(go_image, "-m", "feat: foo [skip ci]")
    assert result.returncode == 1
    combined = result.stdout + result.stderr
    assert "CONTRIBUTING.md" in combined, (
        f"CONTRIBUTING.md not referenced in error output\noutput:\n{combined}"
    )


def test_error_suggests_safe_alternatives(go_image: str) -> None:
    """Error output must suggest the safe 'skip-ci' alternative."""
    result = _run_hygiene(go_image, "-m", "feat: foo [skip ci]")
    assert result.returncode == 1
    combined = result.stdout + result.stderr
    assert "skip-ci" in combined, (
        f"Safe alternative 'skip-ci' not suggested\noutput:\n{combined}"
    )
