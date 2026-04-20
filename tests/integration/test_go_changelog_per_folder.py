"""Integration test for GO-07: generate-changelog-per-folder subcommand.

Builds the Docker image once (tag panora-versioning-pipe:go-changelog-test via
GO_CHANGELOG_IMAGE env var, or the default) and runs
`panora-versioning generate-changelog-per-folder` against seeded local git
repos mounted at /workspace.

The test:
  1. Seeds a monorepo with two groups (services/auth, services/billing).
  2. Writes /tmp/.versioning-merged.yml with per_folder config.
  3. Runs the binary.
  4. Asserts exit code, folder-level CHANGELOG.md content,
     /tmp/routed_commits.txt, and logs.

Dual-run diff: selected scenarios also run the bash script on the same fixture
and compare output byte-for-byte.
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
    "GO_CHANGELOG_IMAGE",
    "panora-versioning-pipe:go-changelog-test",
)
BINARY = "/usr/local/bin/panora-versioning"
BASH_SCRIPT = "/pipe/changelog/generate-changelog-per-folder.sh"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


@pytest.fixture(scope="module")
def changelog_image() -> str:
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

def _make_workspace(tmp_path: Path) -> Path:
    ws = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
    ws.mkdir()
    return ws


def _seed_monorepo(workspace: Path) -> None:
    """Init a git repo with commits touching services/auth and services/billing."""
    cmds = [
        ["git", "init", "--initial-branch=main"],
        ["git", "config", "user.email", "ci@example.com"],
        ["git", "config", "user.name", "CI Pipeline"],
    ]
    for c in cmds:
        subprocess.run(c, cwd=workspace, check=True, capture_output=True)

    # Folder structure
    auth_dir = workspace / "services" / "auth"
    billing_dir = workspace / "services" / "billing"
    auth_dir.mkdir(parents=True)
    billing_dir.mkdir(parents=True)

    # Initial commit (becomes the base tag)
    (workspace / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: initial commit"],
        cwd=workspace, check=True, capture_output=True,
    )
    subprocess.run(["git", "tag", "v1.0.0"], cwd=workspace, check=True, capture_output=True)

    # Commit scoped to auth
    (auth_dir / "main.go").write_text("package main\n")
    subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "feat(auth): add login handler"],
        cwd=workspace, check=True, capture_output=True,
    )

    # Commit scoped to billing
    (billing_dir / "invoice.go").write_text("package billing\n")
    subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "fix(billing): correct invoice rounding"],
        cwd=workspace, check=True, capture_output=True,
    )

    # Commit with no scope → should go to root only
    (workspace / "shared.go").write_text("package main\n")
    subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: update deps"],
        cwd=workspace, check=True, capture_output=True,
    )


def _write_per_folder_config(workspace: Path, *, commit_url: str = "") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    config = textwrap.dedent(f"""\
        commits:
          format: "conventional"
        version:
          tag_prefix_v: true
          components:
            major: {{ enabled: true, initial: 0 }}
            patch: {{ enabled: true, initial: 0 }}
        changelog:
          file: "CHANGELOG.md"
          title: "Changelog"
          mode: "full"
          use_emojis: false
          include_author: true
          include_commit_link: {"true" if commit_url else "false"}
          include_ticket_link: false
          commit_url: "{commit_url}"
          per_folder:
            enabled: true
            folders:
              - services/auth
              - services/billing
            scope_matching: "exact"
            fallback: "none"
        """)
    (tmp / ".versioning-merged.yml").write_text(config)


def _run_per_folder(
    image: str,
    workspace: Path,
    *,
    env_overrides: dict[str, str] | None = None,
    use_bash: bool = False,
) -> subprocess.CompletedProcess:
    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)

    env_flags: list[str] = []
    # Seed scenario.env and next_version.txt in tmp
    (tmp_dir / "scenario.env").write_text("SCENARIO=development_release\n")
    (tmp_dir / "next_version.txt").write_text("1.1.0\n")

    base_ref = "v1.0.0"
    env_flags += ["-e", f"CHANGELOG_BASE_REF={base_ref}"]
    env_flags += ["-e", "VERSIONING_BRANCH=feature/test"]

    if env_overrides:
        for k, v in env_overrides.items():
            env_flags += ["-e", f"{k}={v}"]

    if use_bash:
        entrypoint_args = ["--entrypoint", "/bin/bash", image, BASH_SCRIPT]
    else:
        entrypoint_args = [
            "--entrypoint", BINARY,
            image,
            "generate-changelog-per-folder",
        ]

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
# Scenario 1: monorepo with 2 groups, commits in both → 2 folder changelogs
# ---------------------------------------------------------------------------

class TestPerFolderBasic:
    def test_exit_0(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        result = _run_per_folder(changelog_image, ws)
        combined = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_auth_changelog_created(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        _run_per_folder(changelog_image, ws)
        auth_cl = ws / "services" / "auth" / "CHANGELOG.md"
        assert auth_cl.exists(), "services/auth/CHANGELOG.md not created"
        content = auth_cl.read_text()
        assert "1.1.0" in content, f"version not in auth CHANGELOG:\n{content}"
        assert "feat" in content.lower(), f"feat commit missing:\n{content}"

    def test_billing_changelog_created(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        _run_per_folder(changelog_image, ws)
        billing_cl = ws / "services" / "billing" / "CHANGELOG.md"
        assert billing_cl.exists(), "services/billing/CHANGELOG.md not created"
        content = billing_cl.read_text()
        assert "1.1.0" in content
        assert "fix" in content.lower()

    def test_routed_commits_written(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        _run_per_folder(changelog_image, ws)
        routed = ws / "tmp" / "routed_commits.txt"
        assert routed.exists(), "/tmp/routed_commits.txt not created"
        content = routed.read_text().strip()
        assert content, "routed_commits.txt is empty — expected 2 routed hashes"
        lines = [l for l in content.splitlines() if l.strip()]
        assert len(lines) == 2, f"expected 2 routed commits, got {len(lines)}:\n{content}"

    def test_per_folder_changelogs_txt_written(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        _run_per_folder(changelog_image, ws)
        pf_file = ws / "tmp" / "per_folder_changelogs.txt"
        assert pf_file.exists(), "/tmp/per_folder_changelogs.txt not created"

    def test_unscoped_commit_not_routed(self, changelog_image: str, tmp_path: Path) -> None:
        """chore: update deps has no scope → must NOT appear in per-folder changelogs."""
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        _run_per_folder(changelog_image, ws)
        auth_cl = ws / "services" / "auth" / "CHANGELOG.md"
        billing_cl = ws / "services" / "billing" / "CHANGELOG.md"
        for cl in (auth_cl, billing_cl):
            if cl.exists():
                assert "update deps" not in cl.read_text(), (
                    f"unscoped commit leaked into {cl}"
                )

    def test_banner_present(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        _write_per_folder_config(ws)
        result = _run_per_folder(changelog_image, ws)
        combined = result.stdout + result.stderr
        assert "PER-FOLDER" in combined.upper() or "CHANGELOG" in combined.upper(), (
            f"missing banner in logs:\n{combined}"
        )


# ---------------------------------------------------------------------------
# Scenario 2: no scoped commits → no per-folder changelogs, exit 0
# ---------------------------------------------------------------------------

class TestPerFolderNoScoped:
    def test_exit_0_no_scoped(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        # Init repo with only unscoped commits
        cmds = [
            ["git", "init", "--initial-branch=main"],
            ["git", "config", "user.email", "ci@example.com"],
            ["git", "config", "user.name", "CI Pipeline"],
        ]
        for c in cmds:
            subprocess.run(c, cwd=ws, check=True, capture_output=True)
        (ws / "services" / "auth").mkdir(parents=True)
        (ws / "README.md").write_text("seed\n")
        subprocess.run(["git", "add", "."], cwd=ws, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "chore: initial"], cwd=ws, check=True, capture_output=True)
        subprocess.run(["git", "tag", "v1.0.0"], cwd=ws, check=True, capture_output=True)
        (ws / "file.txt").write_text("x\n")
        subprocess.run(["git", "add", "."], cwd=ws, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "chore: update readme"], cwd=ws, check=True, capture_output=True)
        _write_per_folder_config(ws)
        result = _run_per_folder(changelog_image, ws)
        assert result.returncode == 0


# ---------------------------------------------------------------------------
# Scenario 3: per_folder disabled → exit 0, no changelogs
# ---------------------------------------------------------------------------

class TestPerFolderDisabled:
    def test_exit_0_when_disabled(self, changelog_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_monorepo(ws)
        tmp_dir = ws / "tmp"
        tmp_dir.mkdir(exist_ok=True)
        config = textwrap.dedent("""\
            commits:
              format: "conventional"
            version:
              tag_prefix_v: true
              components:
                major: { enabled: true, initial: 0 }
                patch: { enabled: true, initial: 0 }
            changelog:
              mode: "full"
              per_folder:
                enabled: false
            """)
        (tmp_dir / ".versioning-merged.yml").write_text(config)
        result = _run_per_folder(changelog_image, ws)
        assert result.returncode == 0
        assert not (ws / "services" / "auth" / "CHANGELOG.md").exists()


# ---------------------------------------------------------------------------
# Scenario 4: dual-run diff — Go output byte-identical to bash
# ---------------------------------------------------------------------------

class TestPerFolderDualRun:
    """Run bash and Go on identical fixtures; diff the folder CHANGELOG.md files.

    The bash script uses config-parser.sh which reads /tmp/.versioning-merged.yml
    AND requires a .versioning.yml in the workspace root (REPO_ROOT detection).
    Both workspaces need the same structure to produce comparable output.
    """

    def _seed_monorepo_for_dual(self, workspace: Path) -> None:
        """Same as _seed_monorepo but also writes .versioning.yml for bash REPO_ROOT."""
        _seed_monorepo(workspace)
        # bash config-parser needs .versioning.yml to find REPO_ROOT
        versioning_yml = textwrap.dedent("""\
            commits:
              format: "conventional"
            changelog:
              mode: "full"
              use_emojis: false
              include_author: true
              include_commit_link: false
              include_ticket_link: false
              per_folder:
                enabled: true
                folders:
                  - services/auth
                  - services/billing
                scope_matching: "exact"
                fallback: "none"
            """)
        (workspace / ".versioning.yml").write_text(versioning_yml)
        subprocess.run(["git", "add", ".versioning.yml"], cwd=workspace, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "chore: add versioning config"],
            cwd=workspace, check=True, capture_output=True,
        )

    def test_auth_changelog_identical_to_bash(self, changelog_image: str, tmp_path: Path) -> None:
        ws_go = _make_workspace(tmp_path)
        ws_bash = _make_workspace(tmp_path)

        for ws in (ws_go, ws_bash):
            self._seed_monorepo_for_dual(ws)
            _write_per_folder_config(ws)

        result_go = _run_per_folder(changelog_image, ws_go, use_bash=False)
        result_bash = _run_per_folder(changelog_image, ws_bash, use_bash=True)

        go_cl = ws_go / "services" / "auth" / "CHANGELOG.md"
        bash_cl = ws_bash / "services" / "auth" / "CHANGELOG.md"

        if not go_cl.exists() and not bash_cl.exists():
            return  # both produced nothing — consistent

        go_text = go_cl.read_text() if go_cl.exists() else ""
        bash_text = bash_cl.read_text() if bash_cl.exists() else ""

        # Normalize commit hashes before comparing structure
        import re
        def _norm(t: str) -> str:
            return re.sub(r"\b[0-9a-f]{7,40}\b", "HASH", t)

        assert _norm(go_text) == _norm(bash_text), (
            f"Go vs bash auth CHANGELOG differ (hashes normalized):\n"
            f"--- bash (exit {result_bash.returncode}) ---\n{bash_text}\n"
            f"--- go (exit {result_go.returncode}) ---\n{go_text}\n"
            f"bash logs:\n{result_bash.stdout}{result_bash.stderr}\n"
            f"go logs:\n{result_go.stdout}{result_go.stderr}"
        )
