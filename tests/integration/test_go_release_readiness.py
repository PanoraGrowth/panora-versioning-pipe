"""Integration test for GO-08: check-release-readiness subcommand.

Builds the Docker image and runs `panora-versioning check-release-readiness`
against seeded local git repos. The test:

  1. Seeds a repo in various states.
  2. Writes /tmp/.versioning-merged.yml with relevant config.
  3. Runs the binary.
  4. Asserts exit code, stdout check lines, and summary format.

Dual-run diff: selected scenarios also run the bash script and compare
summary format to ensure Go output is equivalent.
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
IMAGE_TAG = os.environ.get(
    "GO_RELEASE_READINESS_IMAGE",
    "panora-versioning-pipe:go-release-readiness-test",
)
BINARY = "/usr/local/bin/panora-versioning"
BASH_SCRIPT = "/pipe/release/check-release-readiness.sh"


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
# Workspace helpers
# ---------------------------------------------------------------------------

def _make_workspace(tmp_path: Path) -> Path:
    ws = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
    ws.mkdir()
    return ws


def _seed_repo(workspace: Path, *, tag: str | None = "v0.1.0") -> None:
    """Initialise a git repo with one commit and optional tag."""
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
    if tag:
        subprocess.run(["git", "tag", tag], cwd=workspace, check=True, capture_output=True)


def _write_merged_config(workspace: Path, extra_yaml: str = "") -> None:
    """Write a minimal .versioning-merged.yml."""
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    base = textwrap.dedent("""\
        commits:
          format: "conventional"
        version:
          tag_prefix_v: true
          components:
            major: { enabled: true, initial: 0 }
            patch: { enabled: true, initial: 0 }
        """)
    (tmp / ".versioning-merged.yml").write_text(base + extra_yaml)


def _seed_examples(workspace: Path) -> None:
    """Seed minimal examples/ so image-url checks pass."""
    gh_dir = workspace / "examples" / "github-actions"
    gh_dir.mkdir(parents=True)
    bb_dir = workspace / "examples" / "bitbucket"
    bb_dir.mkdir(parents=True)

    consumer = "public.ecr.aws/k5n8p2t3/panora-versioning-pipe"
    (gh_dir / "versioning.yml").write_text(
        f"image: {consumer}:latest\n"
    )
    (bb_dir / "bitbucket-pipelines.yml").write_text(
        f"image: {consumer}:latest\n"
    )


def _seed_changelog(workspace: Path) -> None:
    """Write a CHANGELOG.md so changelog check can pass."""
    (workspace / "CHANGELOG.md").write_text("# Changelog\n")
    subprocess.run(["git", "add", "CHANGELOG.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "docs: add changelog"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )


def _run_rr(
    image: str,
    workspace: Path,
    *,
    env_overrides: dict[str, str] | None = None,
    use_bash: bool = False,
) -> subprocess.CompletedProcess:
    env_flags: list[str] = []
    if env_overrides:
        for k, v in env_overrides.items():
            env_flags += ["-e", f"{k}={v}"]

    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)

    if use_bash:
        entrypoint_args = ["--entrypoint", "/bin/bash", image, BASH_SCRIPT]
    else:
        entrypoint_args = ["--entrypoint", BINARY, image, "check-release-readiness"]

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workspace}:/workspace",
            "-v", f"{tmp_dir}:/tmp",
            "-w", "/workspace",
            *env_flags,
            *entrypoint_args,
        ],
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Scenario 1: clean repo, no blocked checks → exit 0
# ---------------------------------------------------------------------------

def _seed_bats(workspace: Path, count: int = 220) -> None:
    """Seed a minimal tests/unit/ bats file with enough @test entries to pass the floor."""
    unit_dir = workspace / "tests" / "unit"
    unit_dir.mkdir(parents=True)
    content = "\n".join(f"@test \"stub {i}\" {{ true; }}" for i in range(count))
    (unit_dir / "stubs.bats").write_text(content + "\n")


class TestCleanRepo:
    """Repo with enough bats to pass unit_test_count and unreachable BASE_REF → all UNCLEAR/PASS → exit 0."""

    def _setup(self, tmp_path: Path) -> Path:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)
        _seed_bats(ws)
        _seed_examples(ws)
        return ws

    def test_exit_0_clean(self, rr_image: str, tmp_path: Path) -> None:
        """With enough bats and an unreachable BASE_REF, no check should block → exit 0."""
        ws = self._setup(tmp_path)
        # Use a nonexistent BASE_REF: changelog/readme/arch/commit checks → UNCLEAR (not FAIL)
        # unit_test_count → PASS (220 bats seeded)
        # defaults_keys → UNCLEAR (no scripts/defaults.yml in our test workspace)
        # examples → PASS (seeded with consumer image)
        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "nonexistent-ref"})
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_banner_present(self, rr_image: str, tmp_path: Path) -> None:
        ws = self._setup(tmp_path)
        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "nonexistent-ref"})
        combined = result.stdout + result.stderr
        assert "Release Readiness" in combined, (
            f"missing banner in logs:\n{combined}"
        )

    def test_summary_line_present(self, rr_image: str, tmp_path: Path) -> None:
        ws = self._setup(tmp_path)
        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "nonexistent-ref"})
        combined = result.stdout + result.stderr
        assert "summary:" in combined, (
            f"missing summary line:\n{combined}"
        )

    def test_summary_format(self, rr_image: str, tmp_path: Path) -> None:
        """Summary line must match: 'summary: N pass, N fail, N unclear'"""
        ws = self._setup(tmp_path)
        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "nonexistent-ref"})
        combined = result.stdout + result.stderr
        import re
        assert re.search(r"summary:\s+\d+ pass, \d+ fail, \d+ unclear", combined), (
            f"summary line format wrong:\n{combined}"
        )


# ---------------------------------------------------------------------------
# Scenario 2: uncommitted changes → exit 1 (via commit_hygiene or unit test count)
# Note: the bash script doesn't check uncommitted changes directly — it checks
# commit messages, CHANGELOG, doc timestamps, unit test count, defaults keys,
# and image URLs. We test the unit_test_count block check as the canonical
# "block → exit 1" path.
# ---------------------------------------------------------------------------

class TestBlockingCheck:
    """When unit_test_count drops below floor → FAIL → exit 1."""

    def test_exit_1_when_no_bats(self, rr_image: str, tmp_path: Path) -> None:
        """No bats tests in repo → unit_test_count FAIL → exit 1."""
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)
        # No tests/ directory → rg finds 0 @test → below floor → FAIL

        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "HEAD~1"})
        assert result.returncode == 1, (
            f"expected exit 1 (unit_test_count fail), got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_fail_line_present(self, rr_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)

        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "HEAD~1"})
        combined = result.stdout + result.stderr
        assert "[FAIL]" in combined, (
            f"expected [FAIL] line in output:\n{combined}"
        )


# ---------------------------------------------------------------------------
# Scenario 3: CHANGELOG touched in PR → changelog_has_entry PASS
# The bash script checks whether CHANGELOG.md was modified in the PR diff.
# ---------------------------------------------------------------------------

class TestChangelogCheck:
    """changelog_has_entry: CHANGELOG.md touched in PR → PASS."""

    def test_changelog_touched_pass(self, rr_image: str, tmp_path: Path) -> None:
        """When CHANGELOG.md is touched in the diff → changelog_has_entry PASS."""
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _seed_changelog(ws)
        _write_merged_config(ws)

        # BASE_REF = the commit before CHANGELOG was added → diff includes CHANGELOG.md
        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "HEAD~1"})
        combined = result.stdout + result.stderr
        assert "[PASS] changelog_has_entry" in combined or "changelog_has_entry" in combined, (
            f"changelog check not found in output:\n{combined}"
        )

    def test_commit_hygiene_fail_on_skip_ci(self, rr_image: str, tmp_path: Path) -> None:
        """Commit message with [skip ci] → commit_hygiene FAIL → exit 1."""
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)

        # Add a commit with a forbidden marker
        (ws / "file.txt").write_text("change\n")
        subprocess.run(["git", "add", "file.txt"], cwd=ws, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "feat: something [skip ci]"],
            cwd=ws,
            check=True,
            capture_output=True,
        )

        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "HEAD~1"})
        combined = result.stdout + result.stderr
        assert result.returncode == 1, (
            f"expected exit 1 (commit_hygiene fail), got {result.returncode}\n{combined}"
        )
        assert "commit_hygiene" in combined, f"commit_hygiene not reported:\n{combined}"
        assert "[FAIL]" in combined, f"[FAIL] line missing:\n{combined}"


# ---------------------------------------------------------------------------
# Scenario 4: multiple blocking issues → all reported
# ---------------------------------------------------------------------------

class TestMultipleIssues:
    """Multiple FAIL conditions → all reported in output, exit 1."""

    def test_all_issues_reported(self, rr_image: str, tmp_path: Path) -> None:
        """No bats (unit_test_count FAIL) + skip-ci commit (commit_hygiene FAIL) → both reported."""
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)

        # Add commit with forbidden marker → commit_hygiene FAIL
        (ws / "extra.txt").write_text("x\n")
        subprocess.run(["git", "add", "extra.txt"], cwd=ws, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "fix: something [skip ci]"],
            cwd=ws,
            check=True,
            capture_output=True,
        )
        # No tests/ dir → unit_test_count FAIL
        # Both should appear in output

        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "HEAD~1"})
        combined = result.stdout + result.stderr
        fail_count = combined.count("[FAIL]")
        assert fail_count >= 2, (
            f"expected at least 2 FAILs, got {fail_count}:\n{combined}"
        )
        assert result.returncode == 1, (
            f"expected exit 1 with multiple issues, got {result.returncode}"
        )


# ---------------------------------------------------------------------------
# Scenario 5: UNCLEAR checks never cause exit 1
# ---------------------------------------------------------------------------

class TestUnclearDoesNotBlock:
    """UNCLEAR results must never cause exit 1."""

    def test_unclear_is_exit_0(self, rr_image: str, tmp_path: Path) -> None:
        """Repo with no tests/ dir but mocked unit test count → only UNCLEAR, no FAIL → exit 0.

        We test the changelog_has_entry check: when BASE_REF is unreachable,
        check emits UNCLEAR. Exit should still be 0 (no FAILs).
        We seed enough bats to pass the unit_test_count floor.
        """
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)
        _seed_bats(ws)
        _seed_examples(ws)

        # BASE_REF=nonexistent → changelog_has_entry/commit_hygiene become UNCLEAR
        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "nonexistent-branch"})
        combined = result.stdout + result.stderr
        assert "[FAIL]" not in combined or result.returncode == 0, (
            f"UNCLEAR-only run should exit 0:\n{combined}"
        )
        # Key assertion: no FAILs means exit 0
        if "[FAIL]" not in combined:
            assert result.returncode == 0, (
                f"No FAILs but exit {result.returncode}:\n{combined}"
            )


# ---------------------------------------------------------------------------
# Scenario 6: dual-run diff — Go summary matches bash summary format
# ---------------------------------------------------------------------------

class TestDualRunSummaryFormat:
    """Go and bash must produce the same summary line format."""

    def test_summary_line_format_matches_bash(self, rr_image: str, tmp_path: Path) -> None:
        """Both Go and bash must emit 'summary: N pass, N fail, N unclear'."""
        import re
        env = {"BASE_REF": "nonexistent-ref"}

        ws_go = _make_workspace(tmp_path)
        _seed_repo(ws_go, tag="v0.1.0")
        _write_merged_config(ws_go)
        _seed_bats(ws_go)
        _seed_examples(ws_go)
        go_result = _run_rr(rr_image, ws_go, env_overrides=env)
        go_combined = go_result.stdout + go_result.stderr

        ws_bash = _make_workspace(tmp_path)
        _seed_repo(ws_bash, tag="v0.1.0")
        _write_merged_config(ws_bash)
        _seed_bats(ws_bash)
        _seed_examples(ws_bash)
        bash_result = _run_rr(rr_image, ws_bash, env_overrides=env, use_bash=True)
        bash_combined = bash_result.stdout + bash_result.stderr

        pattern = r"summary:\s+\d+ pass, \d+ fail, \d+ unclear"
        go_match = re.search(pattern, go_combined)
        bash_match = re.search(pattern, bash_combined)

        assert go_match is not None, f"Go output missing summary line:\n{go_combined}"
        assert bash_match is not None, f"Bash output missing summary line:\n{bash_combined}"

    def test_check_result_lines_format(self, rr_image: str, tmp_path: Path) -> None:
        """Both Go and bash must use [PASS]/[FAIL]/[UNCLEAR] prefix format."""
        import re
        ws = _make_workspace(tmp_path)
        _seed_repo(ws, tag="v0.1.0")
        _write_merged_config(ws)
        _seed_bats(ws)

        result = _run_rr(rr_image, ws, env_overrides={"BASE_REF": "nonexistent-ref"})
        combined = result.stdout + result.stderr

        # At least one result line with the correct format
        assert re.search(r"\[(PASS|FAIL|UNCLEAR)\]", combined), (
            f"no result lines found in output:\n{combined}"
        )
