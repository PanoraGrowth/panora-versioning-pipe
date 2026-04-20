"""Integration test for GO-08: check-release-readiness subcommand.

Builds the Docker image and runs `panora-versioning check-release-readiness`
against a seeded local git repo mounted at /workspace.

Scenarios covered:
  1. Clean repo → exit 0, summary shows 0 fail.
  2. Uncommitted changes → exit 1, check named in output.
  3. Missing configured version file → exit 1, file name in output.
  4. Multiple issues → all reported, summary aggregates them.
  5. Summary format matches bash: 'summary: N pass, N fail, N unclear'.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import textwrap
import uuid
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
IMAGE_TAG = os.environ.get(
    "GO_RELEASE_READINESS_IMAGE", "panora-versioning-pipe:go-release-readiness-test"
)
BINARY = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


@pytest.fixture(scope="module")
def rr_image() -> str:
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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _seed_repo(workspace: Path, *, tag: str | None = None) -> None:
    """Init a git repo with one commit and optional tag."""
    cmds = [
        ["git", "init", "--initial-branch=main"],
        ["git", "config", "user.email", "test@example.com"],
        ["git", "config", "user.name", "Test"],
    ]
    for c in cmds:
        subprocess.run(c, cwd=workspace, check=True, capture_output=True)

    (workspace / "README.md").write_text("seed\n")
    (workspace / "CHANGELOG.md").write_text("# Changelog\n")
    subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial commit"],
        cwd=workspace, check=True, capture_output=True,
    )
    if tag:
        subprocess.run(
            ["git", "tag", tag], cwd=workspace, check=True, capture_output=True
        )


def _write_config(workspace: Path, *, extra_yaml: str = "") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    base = textwrap.dedent("""\
        commits:
          format: conventional
        version:
          tag_prefix_v: true
          components:
            major: {enabled: true, initial: 0}
            patch: {enabled: true, initial: 0}
    """)
    config = base + textwrap.dedent(extra_yaml)
    (tmp / ".versioning-merged.yml").write_text(config)


def _run_rr(
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
            "check-release-readiness",
        ],
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestReleaseReadinessCleanRepo:
    """Clean repo with tagged latest → exit 0."""

    def test_exit_zero(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace)

        result = _run_rr(rr_image, workspace)
        assert result.returncode == 0, (
            f"expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_summary_line_present(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace)

        result = _run_rr(rr_image, workspace)
        assert "summary:" in result.stdout.lower(), (
            f"missing summary line\nstdout:\n{result.stdout}"
        )

    def test_header_present(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace)

        result = _run_rr(rr_image, workspace)
        assert "Release Readiness" in result.stdout, (
            f"missing header\nstdout:\n{result.stdout}"
        )


class TestReleaseReadinessUncommittedChanges:
    """Uncommitted changes → check fails, exit 1."""

    def test_exit_one(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace)
        (workspace / "dirty.txt").write_text("dirty\n")
        subprocess.run(
            ["git", "add", "dirty.txt"], cwd=workspace, check=True, capture_output=True
        )

        result = _run_rr(rr_image, workspace)
        assert result.returncode == 1, (
            f"expected exit 1 for dirty workdir\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_fail_line_present(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace)
        (workspace / "dirty.txt").write_text("dirty\n")
        subprocess.run(
            ["git", "add", "dirty.txt"], cwd=workspace, check=True, capture_output=True
        )

        result = _run_rr(rr_image, workspace)
        assert "[FAIL]" in result.stdout, (
            f"missing [FAIL] line\nstdout:\n{result.stdout}"
        )


class TestReleaseReadinessMissingVersionFile:
    """Missing configured version file → exit 1, file named."""

    def test_exit_one(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace, extra_yaml=textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: root
                  files:
                    - package.json
        """))

        result = _run_rr(rr_image, workspace)
        assert result.returncode == 1, (
            f"expected exit 1 for missing version file\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_file_named_in_output(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace, extra_yaml=textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: root
                  files:
                    - package.json
        """))

        result = _run_rr(rr_image, workspace)
        assert "package.json" in result.stdout, (
            f"missing file name in output\nstdout:\n{result.stdout}"
        )


class TestReleaseReadinessMultipleIssues:
    """Multiple issues → all reported, summary aggregates."""

    def test_fail_count_at_least_two(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace, extra_yaml=textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: root
                  files:
                    - missing_file.yaml
        """))
        (workspace / "dirty.txt").write_text("dirty\n")
        subprocess.run(
            ["git", "add", "dirty.txt"], cwd=workspace, check=True, capture_output=True
        )

        result = _run_rr(rr_image, workspace)
        assert result.returncode == 1, (
            f"expected exit 1\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        summary_lines = [ln for ln in result.stdout.splitlines() if "summary:" in ln.lower()]
        assert summary_lines, f"no summary line found\nstdout:\n{result.stdout}"
        m = re.search(r'(\d+)\s+fail', summary_lines[0])
        assert m and int(m.group(1)) >= 2, (
            f"expected >=2 failures\nline: {summary_lines[0]}"
        )


class TestReleaseReadinessSummaryFormat:
    """Summary line format matches bash: 'summary: N pass, N fail, N unclear'."""

    def test_summary_format(self, rr_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace, tag="v1.0.0")
        _write_config(workspace)

        result = _run_rr(rr_image, workspace)
        pattern = r'summary:\s+\d+\s+pass,\s+\d+\s+fail,\s+\d+\s+unclear'
        assert re.search(pattern, result.stdout, re.IGNORECASE), (
            f"summary format mismatch\nstdout:\n{result.stdout}"
        )
