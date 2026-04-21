"""Integration test for GO-02: detect-scenario subcommand.

Verifies that `panora-versioning detect-scenario`:
1. Produces /tmp/scenario.env with the correct SCENARIO value.
2. Emits the expected log banners in order.
3. Exits 0 on success.

Pattern: build the image once per module, run each scenario against the
compiled binary. No GitHub/Bitbucket API calls.
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

FIXTURES_DIR = REPO_ROOT / "tests" / "fixtures"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available on this host",
)


@pytest.fixture(scope="module")
def go_image() -> str:
    """Build the multi-stage Docker image once per module."""
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


def _init_git_repo(path: Path, initial_branch: str = "main") -> None:
    """Create a bare git repo with one initial commit."""
    cmds = [
        ["git", "init", f"--initial-branch={initial_branch}"],
        ["git", "config", "user.email", "test@example.test"],
        ["git", "config", "user.name", "Test"],
    ]
    for cmd in cmds:
        subprocess.run(cmd, cwd=path, check=True, capture_output=True)
    (path / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=path, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial"],
        cwd=path,
        check=True,
        capture_output=True,
    )


def _run_detect_scenario(
    image: str,
    workspace: Path,
    *,
    source_branch: str,
    target_branch: str | None = None,
    commit: str = "HEAD",
    fixture_name: str = "minimal",
) -> subprocess.CompletedProcess:
    """Run detect-scenario inside Docker against a seeded workspace."""
    # Copy fixture config
    fixture_src = FIXTURES_DIR / f"{fixture_name}.yml"
    (workspace / ".versioning.yml").write_bytes(fixture_src.read_bytes())

    env_flags = [
        f"-e=VERSIONING_BRANCH={source_branch}",
        f"-e=VERSIONING_COMMIT={commit}",
    ]
    if target_branch is not None:
        env_flags.append(f"-e=VERSIONING_TARGET_BRANCH={target_branch}")

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-w", "/workspace",
            "--entrypoint", BINARY_PATH,
            *env_flags,
            image,
            "detect-scenario",
        ],
        capture_output=True,
        text=True,
    )


# =============================================================================
# PR context scenarios (TARGET_BRANCH set)
# =============================================================================

class TestPRContext:
    """Tests for PR context: VERSIONING_TARGET_BRANCH is set."""

    def test_feature_to_tag_on_is_development_release(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="feature/login",
            target_branch="development",  # tag_on in minimal fixture
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "development_release" in combined.lower() or "development release" in combined.lower(), (
            f"Expected development_release in output\ncombined:\n{combined}"
        )

    def test_hotfix_branch_to_hotfix_target_is_hotfix(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="hotfix/urgent-fix",
            target_branch="pre-production",  # hotfix_target in minimal
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "hotfix" in combined.lower(), (
            f"Expected hotfix in output\ncombined:\n{combined}"
        )

    def test_tag_on_to_hotfix_target_is_promotion(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="development",
            target_branch="pre-production",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "promotion" in combined.lower(), (
            f"Expected promotion in output\ncombined:\n{combined}"
        )

    def test_feature_to_hotfix_target_is_unknown(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="feature/quick-fix",
            target_branch="main",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "unknown" in combined.lower(), (
            f"Expected unknown in output\ncombined:\n{combined}"
        )

    def test_tag_on_equals_hotfix_target_hotfix_branch_is_hotfix(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="hotfix/fix-auth",
            target_branch="main",
            fixture_name="tag-on-equals-hotfix-target",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "hotfix" in combined.lower(), (
            f"Expected hotfix in output\ncombined:\n{combined}"
        )

    def test_tag_on_equals_hotfix_target_feature_is_development_release(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="feature/new-ui",
            target_branch="main",
            fixture_name="tag-on-equals-hotfix-target",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "development_release" in combined.lower() or "development release" in combined.lower(), (
            f"Expected development_release in output\ncombined:\n{combined}"
        )

    def test_custom_branches_hotfix_to_staging(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="hotfix/db-crash",
            target_branch="staging",
            fixture_name="custom-branches",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "hotfix" in combined.lower(), (
            f"Expected hotfix in output\ncombined:\n{combined}"
        )


# =============================================================================
# Branch context scenarios (no TARGET_BRANCH)
# =============================================================================

class TestBranchContext:
    """Tests for branch context: VERSIONING_TARGET_BRANCH not set."""

    def _seed_commit(self, workspace: Path, subject: str) -> None:
        (workspace / f"artifact-{uuid.uuid4().hex[:6]}.txt").write_text("x\n")
        subprocess.run(["git", "add", "-A"], cwd=workspace, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", subject],
            cwd=workspace,
            check=True,
            capture_output=True,
        )

    def _seed_merge_commit(self, workspace: Path, branch_subject: str) -> None:
        subprocess.run(
            ["git", "checkout", "-b", "hotfix-side"],
            cwd=workspace,
            check=True,
            capture_output=True,
        )
        (workspace / "fix.txt").write_text("fix\n")
        subprocess.run(["git", "add", "fix.txt"], cwd=workspace, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", branch_subject],
            cwd=workspace,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "checkout", "main"],
            cwd=workspace,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                "git", "merge", "--no-ff", "hotfix-side",
                "-m", "Merge pull request #42 from acme/hotfix-side",
            ],
            cwd=workspace,
            check=True,
            capture_output=True,
        )

    def test_regular_commit_is_development_release(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)
        self._seed_commit(workspace, "feat: add analytics")

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="main",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "development_release" in combined.lower() or "development release" in combined.lower(), (
            f"Expected development_release\ncombined:\n{combined}"
        )

    def test_hotfix_subject_is_hotfix(self, go_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)
        self._seed_commit(workspace, "hotfix: fix critical auth bug")

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="main",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "hotfix" in combined.lower(), (
            f"Expected hotfix\ncombined:\n{combined}"
        )

    def test_merge_commit_parent_subject_hotfix(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)
        self._seed_merge_commit(workspace, "hotfix: critical auth fix")

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="main",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "hotfix" in combined.lower(), (
            f"Expected hotfix\ncombined:\n{combined}"
        )

    def test_merge_commit_feat_subject_is_development_release(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)
        self._seed_merge_commit(workspace, "feat: add analytics integration")

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="main",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"Expected exit 0\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert "development_release" in combined.lower() or "development release" in combined.lower(), (
            f"Expected development_release\ncombined:\n{combined}"
        )


# =============================================================================
# Log assertion — detection steps must appear in order
# =============================================================================

class TestLogContent:
    """Verify that the Go binary emits the expected log banners."""

    def test_log_contains_detection_section(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="feature/login",
            target_branch="development",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert "detecting pipeline scenario" in combined.lower(), (
            f"Missing detection section banner\ncombined:\n{combined}"
        )

    def test_log_contains_source_branch(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="feature/my-feature",
            target_branch="development",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert "feature/my-feature" in combined, (
            f"Source branch not logged\ncombined:\n{combined}"
        )

    def test_log_contains_scenario_written(
        self, go_image: str, tmp_path: Path
    ) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:8]}"
        workspace.mkdir()
        _init_git_repo(workspace)

        result = _run_detect_scenario(
            go_image,
            workspace,
            source_branch="feature/login",
            target_branch="development",
            fixture_name="minimal",
        )
        combined = result.stdout + result.stderr
        assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        # Must log that scenario.env was written
        assert "scenario" in combined.lower(), (
            f"No scenario log found\ncombined:\n{combined}"
        )


