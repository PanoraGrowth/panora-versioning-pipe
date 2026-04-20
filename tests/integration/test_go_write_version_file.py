"""Integration test for GO-06: write-version-file subcommand.

Builds the Docker image and runs `panora-versioning write-version-file` against
a seeded local git repo mounted at /workspace. The test:

  1. Seeds a repo with target files and /tmp/next_version.txt.
  2. Writes /tmp/.versioning-merged.yml with version_file config.
  3. Runs the binary.
  4. Asserts exit code, file content, /tmp/version_files_modified.txt, and logs.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import textwrap
import uuid
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
IMAGE_TAG = os.environ.get(
    "GO_WRITE_VERSION_FILE_IMAGE",
    "panora-versioning-pipe:go-write-version-file-test",
)
BINARY = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


@pytest.fixture(scope="module")
def wvf_image() -> str:
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


def _seed_repo(workspace: Path) -> None:
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
    subprocess.run(
        ["git", "tag", "v1.2.3"],
        cwd=workspace,
        check=True,
        capture_output=True,
    )


def _make_workspace(tmp_path: Path) -> Path:
    ws = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
    ws.mkdir()
    return ws


def _write_version_txt(workspace: Path, version: str = "1.3.0") -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "next_version.txt").write_text(version + "\n")


def _write_merged_config(workspace: Path, version_file_yaml: str) -> None:
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
    (tmp / ".versioning-merged.yml").write_text(base + version_file_yaml)


def _run_wvf(
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
            "write-version-file",
        ],
        capture_output=True,
        text=True,
    )


def _read_tmp(workspace: Path, filename: str) -> str:
    p = workspace / "tmp" / filename
    return p.read_text().strip() if p.exists() else ""


# =============================================================================
# Single package.json
# =============================================================================
class TestSinglePackageJson:
    """Single group with a package.json — version updated, formatting preserved."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: "root"
                  files:
                    - "package.json"
            """)

    def _seed_pkg(self, workspace: Path, original: dict) -> None:
        (workspace / "package.json").write_text(json.dumps(original, indent=2) + "\n")

    def test_exit_code(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        original = {"name": "my-app", "version": "1.0.0", "private": True}
        self._seed_pkg(ws, original)
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 0, (
            f"expected exit 0, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

    def test_version_updated(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        original = {"name": "my-app", "version": "1.0.0", "private": True}
        self._seed_pkg(ws, original)
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        content = (ws / "package.json").read_text()
        data = json.loads(content)
        assert data["version"] == "1.3.0"

    def test_key_order_preserved(self, wvf_image: str, tmp_path: Path) -> None:
        """JSON key order must be preserved — bash used yq which may reorder; Go must not."""
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        original_text = '{\n  "name": "my-app",\n  "version": "1.0.0",\n  "private": true\n}\n'
        (ws / "package.json").write_text(original_text)
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        content = (ws / "package.json").read_text()
        keys = list(json.loads(content).keys())
        assert keys == ["name", "version", "private"], f"key order changed: {keys}"

    def test_other_fields_preserved(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        original = {"name": "my-app", "version": "1.0.0", "private": True, "scripts": {"build": "tsc"}}
        self._seed_pkg(ws, original)
        _write_version_txt(ws, "2.0.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        data = json.loads((ws / "package.json").read_text())
        assert data["name"] == "my-app"
        assert data["private"] is True
        assert data["scripts"] == {"build": "tsc"}
        assert data["version"] == "2.0.0"

    def test_modified_files_list(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        self._seed_pkg(ws, {"name": "app", "version": "0.0.1"})
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        modified = _read_tmp(ws, "version_files_modified.txt")
        assert "package.json" in modified

    def test_log_banner(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        self._seed_pkg(ws, {"name": "app", "version": "0.0.1"})
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        combined = result.stdout + result.stderr
        assert "WRITING VERSION FILE" in combined, f"missing banner in logs:\n{combined}"

    def test_log_per_file(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        self._seed_pkg(ws, {"name": "app", "version": "0.0.1"})
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        combined = result.stdout + result.stderr
        assert "package.json" in combined, f"per-file log missing:\n{combined}"


# =============================================================================
# pyproject.toml
# =============================================================================
class TestPyprojectToml:
    """pyproject.toml version under [tool.poetry] updated correctly."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: "python"
                  files:
                    - "pyproject.toml"
            """)

    def test_version_updated_tool_poetry(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        toml_content = textwrap.dedent("""\
            [tool.poetry]
            name = "my-service"
            version = "0.1.0"
            description = ""

            [tool.poetry.dependencies]
            python = "^3.11"
            """)
        (ws / "pyproject.toml").write_text(toml_content)
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 0, f"exit {result.returncode}\n{result.stdout}\n{result.stderr}"
        updated = (ws / "pyproject.toml").read_text()
        assert 'version = "1.3.0"' in updated
        assert 'version = "0.1.0"' not in updated

    def test_non_version_lines_preserved(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        toml_content = textwrap.dedent("""\
            [tool.poetry]
            name = "my-service"
            version = "0.1.0"
            description = ""

            [tool.poetry.dependencies]
            python = "^3.11"
            """)
        (ws / "pyproject.toml").write_text(toml_content)
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        updated = (ws / "pyproject.toml").read_text()
        assert "name = \"my-service\"" in updated
        assert "python = \"^3.11\"" in updated


# =============================================================================
# version.txt (pattern file)
# =============================================================================
class TestVersionTxt:
    """Plain version.txt (pattern-based update)."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: "plain"
                  files:
                    - "version.txt"
            """)

    def test_version_txt_updated(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        (ws / "version.txt").write_text("1.0.0\n")
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 0, f"exit {result.returncode}\n{result.stdout}\n{result.stderr}"
        assert (ws / "version.txt").read_text().strip() == "1.3.0"


# =============================================================================
# Monorepo groups — trigger_paths routing
# =============================================================================
class TestMonorepoGroups:
    """Group A with matching trigger_paths updates; Group B without match skips."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: "frontend"
                  trigger_paths:
                    - "packages/frontend/**"
                  files:
                    - "packages/frontend/package.json"
                - name: "backend"
                  trigger_paths:
                    - "packages/backend/**"
                  files:
                    - "packages/backend/package.json"
            """)

    def _seed_monorepo(self, workspace: Path) -> None:
        fe = workspace / "packages" / "frontend"
        be = workspace / "packages" / "backend"
        fe.mkdir(parents=True)
        be.mkdir(parents=True)
        (fe / "package.json").write_text('{"name":"fe","version":"1.0.0"}\n')
        (be / "package.json").write_text('{"name":"be","version":"1.0.0"}\n')
        # Commit the monorepo scaffold so these files are NOT part of the later
        # feature commit — otherwise git diff-tree HEAD would include them and
        # trigger_paths matching would see both groups.
        subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "chore: add monorepo scaffold"],
            cwd=workspace,
            check=True,
            capture_output=True,
        )

    def test_matching_group_updated(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        self._seed_monorepo(ws)

        # Make a commit that touches frontend — HEAD commit diff includes frontend file
        fe_file = ws / "packages" / "frontend" / "src.ts"
        fe_file.parent.mkdir(exist_ok=True)
        fe_file.write_text("export const v = 1;\n")
        subprocess.run(["git", "add", "."], cwd=ws, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "feat: frontend change"],
            cwd=ws,
            check=True,
            capture_output=True,
        )

        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 0, f"exit {result.returncode}\n{result.stdout}\n{result.stderr}"
        fe_data = json.loads((ws / "packages" / "frontend" / "package.json").read_text())
        assert fe_data["version"] == "1.3.0"

    def test_non_matching_group_skipped(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        self._seed_monorepo(ws)

        # Commit only touches frontend — backend should NOT be updated
        fe_file = ws / "packages" / "frontend" / "src.ts"
        fe_file.parent.mkdir(exist_ok=True)
        fe_file.write_text("export const v = 1;\n")
        subprocess.run(["git", "add", "."], cwd=ws, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "feat: frontend change"],
            cwd=ws,
            check=True,
            capture_output=True,
        )

        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        be_data = json.loads((ws / "packages" / "backend" / "package.json").read_text())
        assert be_data["version"] == "1.0.0", "backend should not have been updated"

    def test_modified_files_only_contains_updated(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        self._seed_monorepo(ws)

        fe_file = ws / "packages" / "frontend" / "src.ts"
        fe_file.parent.mkdir(exist_ok=True)
        fe_file.write_text("export const v = 1;\n")
        subprocess.run(["git", "add", "."], cwd=ws, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "feat: frontend"],
            cwd=ws,
            check=True,
            capture_output=True,
        )

        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        _run_wvf(wvf_image, ws)
        modified = _read_tmp(ws, "version_files_modified.txt")
        assert "frontend" in modified
        assert "backend" not in modified


# =============================================================================
# Version passed via /tmp/next_version.txt with tag prefix stripping
# =============================================================================
class TestVersionPrefixStripping:
    """Tag prefix v is stripped before writing to file."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: "root"
                  files:
                    - "package.json"
            """)

    def test_prefix_stripped(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        (ws / "package.json").write_text('{"name":"app","version":"1.0.0"}\n')
        # Write version WITH v prefix — the binary should strip it
        _write_version_txt(ws, "v1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 0, f"exit {result.returncode}\n{result.stdout}\n{result.stderr}"
        data = json.loads((ws / "package.json").read_text())
        assert data["version"] == "1.3.0", f"expected prefix stripped, got {data['version']}"


# =============================================================================
# Feature disabled
# =============================================================================
class TestFeatureDisabled:
    """version_file.enabled=false → exit 0, no files touched."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: false
              groups:
                - name: "root"
                  files:
                    - "package.json"
            """)

    def test_exit_zero_when_disabled(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        (ws / "package.json").write_text('{"name":"app","version":"1.0.0"}\n')
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 0, f"exit {result.returncode}\n{result.stdout}\n{result.stderr}"
        data = json.loads((ws / "package.json").read_text())
        assert data["version"] == "1.0.0", "file should not have been modified"

    def test_log_mentions_disabled(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        (ws / "package.json").write_text('{"name":"app","version":"1.0.0"}\n')
        _write_version_txt(ws, "1.3.0")
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        combined = result.stdout + result.stderr
        assert "disabled" in combined.lower(), f"missing 'disabled' in logs:\n{combined}"


# =============================================================================
# Missing next_version.txt → exit 1
# =============================================================================
class TestMissingVersionFile:
    """Missing /tmp/next_version.txt → exit 1 with clear error."""

    def _cfg(self) -> str:
        return textwrap.dedent("""\
            version_file:
              enabled: true
              groups:
                - name: "root"
                  files:
                    - "package.json"
            """)

    def test_exit_1_when_no_version_file(self, wvf_image: str, tmp_path: Path) -> None:
        ws = _make_workspace(tmp_path)
        _seed_repo(ws)
        (ws / "package.json").write_text('{"name":"app","version":"1.0.0"}\n')
        # Deliberately NOT writing next_version.txt
        _write_merged_config(ws, self._cfg())

        result = _run_wvf(wvf_image, ws)
        assert result.returncode == 1, (
            f"expected exit 1, got {result.returncode}\n{result.stdout}\n{result.stderr}"
        )
        combined = result.stdout + result.stderr
        assert "next_version" in combined or "version" in combined.lower(), (
            f"error message should mention version file:\n{combined}"
        )
