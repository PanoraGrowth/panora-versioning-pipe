"""Integration test for GO-06: write-version-file subcommand.

Builds the Docker image and runs `panora-versioning write-version-file` against
a seeded local git repo mounted at /workspace. The test:

  1. Seeds the repo + writes /tmp/next_version.txt + /tmp/.versioning-merged.yml.
  2. Runs the binary.
  3. Asserts exit code, modified files list, file contents, AND log content.
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
    "GO_WRITE_VERSION_FILE_IMAGE", "panora-versioning-pipe:go-write-version-file-test"
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
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        pytest.fail(f"docker build failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
    return IMAGE_TAG


def _seed_repo(workspace: Path, *, extra_files: list[str] | None = None) -> None:
    for c in [
        ["git", "init", "--initial-branch=main"],
        ["git", "config", "user.email", "test@example.com"],
        ["git", "config", "user.name", "Test"],
    ]:
        subprocess.run(c, cwd=workspace, check=True, capture_output=True)
    (workspace / "README.md").write_text("seed\n")
    subprocess.run(["git", "add", "README.md"], cwd=workspace, check=True, capture_output=True)
    subprocess.run(["git", "commit", "-m", "chore: initial commit"], cwd=workspace, check=True, capture_output=True)
    if extra_files:
        for f in extra_files:
            subprocess.run(["git", "add", f], cwd=workspace, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "chore: add files"], cwd=workspace, check=True, capture_output=True)


def _write_next_version(workspace: Path, version: str) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / "next_version.txt").write_text(f"{version}\n")


def _write_config(workspace: Path, *, config_yaml: str) -> None:
    tmp = workspace / "tmp"
    tmp.mkdir(exist_ok=True)
    (tmp / ".versioning-merged.yml").write_text(config_yaml)


def _run_wvf(image: str, workspace: Path, *, env_overrides: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    env_flags: list[str] = []
    if env_overrides:
        for k, v in env_overrides.items():
            env_flags += ["-e", f"{k}={v}"]
    tmp_dir = workspace / "tmp"
    tmp_dir.mkdir(exist_ok=True)
    return subprocess.run(
        ["docker", "run", "--rm",
         "-v", f"{workspace}:/workspace",
         "-v", f"{tmp_dir}:/tmp",
         "-w", "/workspace",
         "--entrypoint", BINARY,
         *env_flags, image, "write-version-file"],
        capture_output=True, text=True,
    )


def _read_tmp(workspace: Path, filename: str) -> str:
    p = workspace / "tmp" / filename
    return p.read_text().strip() if p.exists() else ""


def _config_single_group(*, tag_prefix_v: bool = False, files: list[dict] | None = None, group_name: str = "root") -> str:
    files_yaml = ""
    for f in (files or []):
        path = f["path"]
        pattern = f.get("pattern", "")
        if pattern:
            files_yaml += f'              - path: "{path}"\n                pattern: "{pattern}"\n'
        else:
            files_yaml += f'              - path: "{path}"\n'
    prefix = "true" if tag_prefix_v else "false"
    return textwrap.dedent(f"""\
        commits:
          format: "conventional"
        version:
          tag_prefix_v: {prefix}
          components:
            major: {{enabled: true, initial: 0}}
            patch: {{enabled: true, initial: 0}}
        version_file:
          enabled: true
          groups:
            - name: "{group_name}"
              files:
{files_yaml}
    """)


class TestWriteVersionFilePackageJson:

    def test_exit_code(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"name": "my-app", "version": "0.0.1", "description": "test"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "1.2.3")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "package.json"}]))
        result = _run_wvf(wvf_image, workspace)
        assert result.returncode == 0, f"expected exit 0, got {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    def test_version_updated(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"name": "my-app", "version": "0.0.1", "description": "test"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "1.2.3")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "package.json"}]))
        _run_wvf(wvf_image, workspace)
        data = json.loads((workspace / "package.json").read_text())
        assert data["version"] == "1.2.3"

    def test_key_order_preserved(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"name": "my-app", "version": "0.0.1", "description": "test"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "2.0.0")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "package.json"}]))
        _run_wvf(wvf_image, workspace)
        keys = list(json.loads((workspace / "package.json").read_text()).keys())
        assert keys == ["name", "version", "description"], f"key order changed: {keys}"

    def test_tag_prefix_stripped(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"version": "0.0.0"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "v1.0.0")
        _write_config(workspace, config_yaml=_config_single_group(tag_prefix_v=True, files=[{"path": "package.json"}]))
        _run_wvf(wvf_image, workspace)
        assert json.loads((workspace / "package.json").read_text())["version"] == "1.0.0"

    def test_modified_files_list(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"version": "0.0.0"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "1.0.0")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "package.json"}]))
        _run_wvf(wvf_image, workspace)
        assert "package.json" in _read_tmp(workspace, "version_files_modified.txt")

    def test_logs(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"version": "0.0.0"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "1.0.0")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "package.json"}]))
        result = _run_wvf(wvf_image, workspace)
        assert "package.json" in result.stdout.lower(), f"missing file name in logs:\n{result.stdout}"


class TestWriteVersionFilePyprojectToml:

    def test_tool_poetry_section(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "pyproject.toml").write_text(
            '[tool.poetry]\nname = "myproject"\nversion = "0.1.0"\ndescription = "test"\n'
        )
        _seed_repo(workspace, extra_files=["pyproject.toml"])
        _write_next_version(workspace, "1.5.0")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "pyproject.toml"}]))
        result = _run_wvf(wvf_image, workspace)
        assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert 'version = "1.5.0"' in (workspace / "pyproject.toml").read_text()

    def test_project_section(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "pyproject.toml").write_text(
            '[project]\nname = "myproject"\nversion = "0.1.0"\n'
        )
        _seed_repo(workspace, extra_files=["pyproject.toml"])
        _write_next_version(workspace, "2.0.0")
        _write_config(workspace, config_yaml=_config_single_group(files=[{"path": "pyproject.toml"}]))
        result = _run_wvf(wvf_image, workspace)
        assert result.returncode == 0
        assert 'version = "2.0.0"' in (workspace / "pyproject.toml").read_text()


class TestWriteVersionFileMonorepo:

    def test_two_groups_independent(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "frontend").mkdir()
        (workspace / "backend").mkdir()
        (workspace / "frontend" / "package.json").write_text('{"version": "0.0.0"}')
        (workspace / "backend" / "package.json").write_text('{"version": "0.0.0"}')
        _seed_repo(workspace, extra_files=["frontend/package.json", "backend/package.json"])
        config = textwrap.dedent("""\
            commits:
              format: "conventional"
            version:
              tag_prefix_v: false
              components:
                major: {enabled: true, initial: 0}
                patch: {enabled: true, initial: 0}
            version_file:
              enabled: true
              groups:
                - name: "frontend"
                  files:
                    - path: "frontend/package.json"
                - name: "backend"
                  files:
                    - path: "backend/package.json"
        """)
        _write_next_version(workspace, "3.0.0")
        _write_config(workspace, config_yaml=config)
        result = _run_wvf(wvf_image, workspace)
        assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert json.loads((workspace / "frontend" / "package.json").read_text())["version"] == "3.0.0"
        assert json.loads((workspace / "backend" / "package.json").read_text())["version"] == "3.0.0"

    def test_trigger_paths_isolates_groups(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "services").mkdir()
        (workspace / "infra").mkdir()
        (workspace / "services" / "version.yaml").write_text('version: "0.0.0"\n')
        (workspace / "infra" / "version.yaml").write_text('version: "0.0.0"\n')
        bare = tmp_path / "remote.git"
        subprocess.run(["git", "init", "--bare", str(bare)], check=True, capture_output=True)
        for c in [["git", "init", "--initial-branch=main"], ["git", "config", "user.email", "t@t.com"], ["git", "config", "user.name", "T"]]:
            subprocess.run(c, cwd=workspace, check=True, capture_output=True)
        subprocess.run(["git", "add", "."], cwd=workspace, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "chore: initial"], cwd=workspace, check=True, capture_output=True)
        subprocess.run(["git", "remote", "add", "origin", str(bare)], cwd=workspace, check=True, capture_output=True)
        subprocess.run(["git", "push", "-q", "origin", "HEAD:refs/heads/main"], cwd=workspace, check=True, capture_output=True)
        (workspace / "services" / "app.tf").write_text("# changed\n")
        subprocess.run(["git", "add", "services/app.tf"], cwd=workspace, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "feat: services change"], cwd=workspace, check=True, capture_output=True)
        config = textwrap.dedent("""\
            commits:
              format: "conventional"
            version:
              tag_prefix_v: false
              components:
                major: {enabled: true, initial: 0}
                patch: {enabled: true, initial: 0}
            version_file:
              enabled: true
              groups:
                - name: "services"
                  trigger_paths:
                    - "services/**"
                  files:
                    - path: "services/version.yaml"
                - name: "infra"
                  trigger_paths:
                    - "infra/**"
                  files:
                    - path: "infra/version.yaml"
        """)
        _write_next_version(workspace, "5.0.0")
        _write_config(workspace, config_yaml=config)
        result = _run_wvf(wvf_image, workspace, env_overrides={"VERSIONING_TARGET_BRANCH": "main"})
        assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        import yaml as _yaml
        assert _yaml.safe_load((workspace / "services" / "version.yaml").read_text())["version"] == "5.0.0"
        assert _yaml.safe_load((workspace / "infra" / "version.yaml").read_text())["version"] == "0.0.0"


class TestWriteVersionFileMissingPattern:

    def test_missing_pattern_exits_error(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace)
        _write_next_version(workspace, "1.0.0")
        (workspace / "src").mkdir()
        (workspace / "src" / "version.ts").write_text('export const V = "__VERSION__";\n')
        _write_config(workspace, config_yaml=textwrap.dedent("""\
            commits:
              format: "conventional"
            version:
              tag_prefix_v: false
              components:
                major: {enabled: true, initial: 0}
                patch: {enabled: true, initial: 0}
            version_file:
              enabled: true
              groups:
                - name: "root"
                  files:
                    - path: "src/version.ts"
        """))
        result = _run_wvf(wvf_image, workspace)
        assert result.returncode != 0, f"expected non-zero\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


class TestWriteVersionFileDisabled:

    def test_disabled_exits_zero(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "package.json").write_text('{"version": "0.0.0"}')
        _seed_repo(workspace, extra_files=["package.json"])
        _write_next_version(workspace, "9.0.0")
        _write_config(workspace, config_yaml=textwrap.dedent("""\
            commits:
              format: "conventional"
            version_file:
              enabled: false
              groups:
                - name: "root"
                  files:
                    - path: "package.json"
        """))
        result = _run_wvf(wvf_image, workspace)
        assert result.returncode == 0
        assert json.loads((workspace / "package.json").read_text())["version"] == "0.0.0"

    def test_disabled_logs_skip(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        _seed_repo(workspace)
        _write_next_version(workspace, "9.0.0")
        _write_config(workspace, config_yaml=textwrap.dedent("""\
            commits:
              format: "conventional"
            version_file:
              enabled: false
              groups: []
        """))
        result = _run_wvf(wvf_image, workspace)
        assert "disabled" in result.stdout.lower() or "skip" in result.stdout.lower(), f"logs:\n{result.stdout}"


class TestWriteVersionFileModifiedFilesList:

    def test_multiple_files_in_list(self, wvf_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        (workspace / "version.yaml").write_text('version: "0.0.0"\n')
        (workspace / "package.json").write_text('{"version": "0.0.0"}')
        _seed_repo(workspace, extra_files=["version.yaml", "package.json"])
        _write_next_version(workspace, "4.0.0")
        _write_config(workspace, config_yaml=textwrap.dedent("""\
            commits:
              format: "conventional"
            version:
              tag_prefix_v: false
              components:
                major: {enabled: true, initial: 0}
                patch: {enabled: true, initial: 0}
            version_file:
              enabled: true
              groups:
                - name: "root"
                  files:
                    - path: "version.yaml"
                    - path: "package.json"
        """))
        _run_wvf(wvf_image, workspace)
        modified = _read_tmp(workspace, "version_files_modified.txt")
        assert "version.yaml" in modified
        assert "package.json" in modified
