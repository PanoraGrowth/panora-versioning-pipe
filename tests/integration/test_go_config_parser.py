"""Integration test for config-parser: Go-only error-handling coverage.

After the bash runtime was removed from the image, dual-run parity coverage
has been dropped here. Semantic parity is enforced by unit tests on the Go
side; this file retains only Go-only error-path assertions.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

GO_IMAGE_TAG = os.environ.get(
    "PANORA_GO_IMAGE", "panora-versioning-pipe:go-config-parser-test"
)

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
