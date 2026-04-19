"""Smoke integration test for the Go bootstrap (ticket GO-00).

Builds the multi-stage Docker image and asserts that:

1. The Go binary is present at /usr/local/bin/panora-versioning.
2. `panora-versioning --version` returns 0 and prints a recognizable version line.
3. Every stubbed Wave 1/2 subcommand returns exit 42 with `not implemented yet`
   on stderr.
4. `/pipe/pipe.sh` still exists inside the image (bash legacy must coexist
   during the migration — Wave N will remove it).
5. `panora-versioning configure-git`, run inside a temporary git repo, replays
   the banner lines emitted by `scripts/setup/configure-git.sh`.

This is a Go-side smoke test — it does NOT talk to GitHub/Bitbucket and does
NOT depend on the sandbox fixtures used by `test_github.py`.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
IMAGE_TAG = os.environ.get("GO_BOOTSTRAP_IMAGE", "panora-versioning-pipe:go-bootstrap-test")
BINARY_PATH = "/usr/local/bin/panora-versioning"
PIPE_SH_PATH = "/pipe/pipe.sh"

STUB_SUBCOMMANDS = [
    "calc-version",
    "detect-scenario",
    "validate-commits",
    "check-commit-hygiene",
    "notify-teams",
    "bitbucket-build-status",
    "write-version-file",
    "generate-changelog-per-folder",
    "generate-changelog-last-commit",
    "update-changelog",
    "check-release-readiness",
    "config-parse",
    "pr-pipeline",
    "branch-pipeline",
]


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available on this host",
)


@pytest.fixture(scope="module")
def go_image() -> str:
    """Build the multi-stage Docker image once per module.

    Returns the image tag. Skips the whole module on build failure so we get
    a clear signal instead of a cascade of broken assertions.
    """
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


def _run_in_image(image: str, *args: str, check: bool = False) -> subprocess.CompletedProcess:
    """Run a command inside the image with ENTRYPOINT overridden."""
    return subprocess.run(
        ["docker", "run", "--rm", "--entrypoint", args[0], image, *args[1:]],
        capture_output=True,
        text=True,
        check=check,
    )


def test_go_binary_exists(go_image: str) -> None:
    """The Go binary must be installed at the expected path."""
    result = _run_in_image(go_image, "ls", BINARY_PATH)
    assert result.returncode == 0, (
        f"{BINARY_PATH} missing inside image\nstderr: {result.stderr}"
    )
    assert BINARY_PATH in result.stdout


def test_pipe_sh_still_present(go_image: str) -> None:
    """Bash entry point must coexist with Go during the migration."""
    result = _run_in_image(go_image, "ls", PIPE_SH_PATH)
    assert result.returncode == 0, (
        f"{PIPE_SH_PATH} missing — bash legacy must coexist during migration\n"
        f"stderr: {result.stderr}"
    )


def test_version_flag(go_image: str) -> None:
    """`panora-versioning --version` returns 0 and prints a recognizable line."""
    result = _run_in_image(go_image, BINARY_PATH, "--version")
    assert result.returncode == 0, (
        f"--version exited non-zero\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    # Accept any of: "panora-versioning vX.Y.Z ...", "panora-versioning dev ...",
    # or "... version X.Y.Z" — cobra's default format.
    combined = (result.stdout + result.stderr).lower()
    assert "panora-versioning" in combined, f"unexpected output: {result.stdout!r}"


@pytest.mark.parametrize("subcmd", STUB_SUBCOMMANDS)
def test_stub_subcommand_exits_42(go_image: str, subcmd: str) -> None:
    """Every stubbed subcommand must exit 42 with `not implemented yet` on stderr."""
    result = _run_in_image(go_image, BINARY_PATH, subcmd)
    assert result.returncode == 42, (
        f"{subcmd}: expected exit 42, got {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert "not implemented yet" in result.stderr.lower(), (
        f"{subcmd}: stderr missing 'not implemented yet'\nstderr: {result.stderr}"
    )


def test_configure_git_replays_bash_banners(go_image: str, tmp_path: Path) -> None:
    """`configure-git` must produce the same banner lines as the bash script.

    The bash `scripts/setup/configure-git.sh` emits:
      - "Configuring git..."
      - "Fetching git refs..."
      - "Git configured successfully"

    The Go port must reproduce those literal strings so operators and bats
    tests that grep the log keep working.
    """
    workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
    workspace.mkdir()
    subprocess.run(
        ["git", "init", "--initial-branch=main"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(workspace), "config", "user.email", "seed@example.test"],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(workspace), "config", "user.name", "Seed"],
        check=True,
        capture_output=True,
    )
    (workspace / "README.md").write_text("bootstrap smoke test\n")
    subprocess.run(
        ["git", "-C", str(workspace), "add", "README.md"],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(workspace), "commit", "-m", "chore: seed"],
        check=True,
        capture_output=True,
    )

    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-w", "/workspace",
            "--entrypoint", BINARY_PATH,
            go_image,
            "configure-git",
        ],
        capture_output=True,
        text=True,
    )

    combined = result.stdout + result.stderr
    assert result.returncode == 0, (
        f"configure-git exited non-zero ({result.returncode})\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for banner in ("Configuring git...", "Fetching git refs...", "Git configured successfully"):
        assert banner in combined, (
            f"configure-git output missing banner {banner!r}\n"
            f"full output:\n{combined}"
        )
