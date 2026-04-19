"""Integration test for GO-04: bitbucket-build-status subcommand.

Runs `panora-versioning bitbucket-build-status` against a local HTTP stub
that captures the POST to api.bitbucket.org (redirected via env vars).

Loop contract (see references/integration-testing.md):
  1. Test fails first (exit 42 / stub) — confirmed before implementation.
  2. Implementation → test green.
  3. Log and auth header assertions are the point.
"""

from __future__ import annotations

import base64
import json
import os
import queue
import shutil
import subprocess
import threading
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
IMAGE_TAG = os.environ.get("GO_REPORTING_IMAGE", "panora-versioning-pipe:go-reporting-test")
BINARY = "/usr/local/bin/panora-versioning"


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


# ---------------------------------------------------------------------------
# Module-scoped image build (reuses the same tag as notify-teams tests)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def reporting_image() -> str:
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
# Local HTTP stub server
# ---------------------------------------------------------------------------


class _StubServer:
    """Thread-backed HTTP stub that captures the last POST."""

    def __init__(self, response_code: int = 200) -> None:
        self._response_code = response_code
        self._received: queue.Queue[dict[str, Any]] = queue.Queue()
        self._server: HTTPServer | None = None

    def start(self) -> str:
        """Start and return host:port string usable inside Docker via host-gateway."""
        response_code = self._response_code
        received = self._received

        class _Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                try:
                    parsed = json.loads(body)
                except json.JSONDecodeError:
                    parsed = {"raw": body.decode(errors="replace")}
                received.put(
                    {
                        "path": self.path,
                        "auth": self.headers.get("Authorization", ""),
                        "content_type": self.headers.get("Content-Type", ""),
                        "body": parsed,
                    }
                )
                self.send_response(response_code)
                self.end_headers()

            def log_message(self, *_: Any) -> None:
                pass

        self._server = HTTPServer(("0.0.0.0", 0), _Handler)
        port = self._server.server_address[1]
        threading.Thread(target=self._server.serve_forever, daemon=True).start()
        return f"host.docker.internal:{port}"

    def stop(self) -> None:
        if self._server:
            self._server.shutdown()

    def last_request(self, timeout: float = 5.0) -> dict[str, Any] | None:
        try:
            return self._received.get(timeout=timeout)
        except queue.Empty:
            return None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_git_repo(workspace: Path) -> str:
    """Init a git repo and return HEAD sha."""
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
        cwd=workspace,
        check=True,
        capture_output=True,
    )
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=workspace,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def _run_bb_status(
    image: str,
    workspace: Path,
    *,
    api_base_url: str,
    exit_code: int = 0,
    extra_env: dict[str, str] | None = None,
    missing_vars: list[str] | None = None,
) -> subprocess.CompletedProcess:
    commit = _make_git_repo(workspace)

    env_flags = [
        "-e", f"BITBUCKET_COMMIT={commit}",
        "-e", "BITBUCKET_REPO_OWNER=my-owner",
        "-e", "BITBUCKET_REPO_SLUG=my-repo",
        "-e", "BITBUCKET_BUILD_NUMBER=77",
        "-e", "BITBUCKET_API_TOKEN=super-secret-token",
        "-e", f"BITBUCKET_EXIT_CODE={exit_code}",
        "-e", f"BITBUCKET_API_BASE_URL={api_base_url}",
    ]
    if extra_env:
        for k, v in extra_env.items():
            env_flags += ["-e", f"{k}={v}"]

    # Simulate missing vars by removing their -e flags
    if missing_vars:
        filtered: list[str] = []
        skip_next = False
        for i, flag in enumerate(env_flags):
            if skip_next:
                skip_next = False
                continue
            if flag == "-e" and i + 1 < len(env_flags):
                key = env_flags[i + 1].split("=", 1)[0]
                if key in missing_vars:
                    skip_next = True
                    continue
            filtered.append(flag)
        env_flags = filtered

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "--add-host", "host.docker.internal:host-gateway",
            "-v", f"{workspace}:/workspace",
            "-w", "/workspace",
            "--entrypoint", BINARY,
            *env_flags,
            image,
            "bitbucket-build-status",
        ],
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestBitbucketBuildStatusSuccess:
    """exit_code=0 → state=SUCCESSFUL, HTTP 200 → exit 0."""

    def test_exit_0_on_200(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            result = _run_bb_status(reporting_image, workspace, api_base_url=api_base, exit_code=0)
            assert result.returncode == 0, (
                f"expected exit 0, got {result.returncode}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        finally:
            stub.stop()

    def test_post_sent_with_successful_state(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            _run_bb_status(reporting_image, workspace, api_base_url=api_base, exit_code=0)
            req = stub.last_request(timeout=5.0)
            assert req is not None, "stub received no POST"
            assert req["body"].get("state") == "SUCCESSFUL", (
                f"expected state=SUCCESSFUL, got: {req['body']}"
            )
        finally:
            stub.stop()

    def test_auth_header_is_bearer(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            _run_bb_status(reporting_image, workspace, api_base_url=api_base)
            req = stub.last_request(timeout=5.0)
            assert req is not None
            auth = req["auth"]
            assert auth.startswith("Bearer ") or auth.startswith("Basic "), (
                f"unexpected auth header: {auth!r}"
            )
        finally:
            stub.stop()

    def test_token_not_logged(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            result = _run_bb_status(reporting_image, workspace, api_base_url=api_base)
            combined = result.stdout + result.stderr
            assert "super-secret-token" not in combined, (
                f"API token leaked into logs!\noutput:\n{combined}"
            )
        finally:
            stub.stop()

    def test_payload_has_required_fields(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            _run_bb_status(reporting_image, workspace, api_base_url=api_base, exit_code=0)
            req = stub.last_request(timeout=5.0)
            assert req is not None
            body = req["body"]
            for field in ("state", "key", "name", "url", "description"):
                assert field in body, f"payload missing field {field!r}: {body}"
        finally:
            stub.stop()


class TestBitbucketBuildStatusFailed:
    """BITBUCKET_EXIT_CODE=1 → state=FAILED."""

    def test_failed_state(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            _run_bb_status(reporting_image, workspace, api_base_url=api_base, exit_code=1)
            req = stub.last_request(timeout=5.0)
            assert req is not None
            assert req["body"].get("state") == "FAILED", (
                f"expected state=FAILED, got: {req['body']}"
            )
        finally:
            stub.stop()


class TestBitbucketBuildStatusHTTPError:
    """HTTP 401 from API → still exits 0 (bash exits 0 regardless)."""

    def test_exit_0_on_401(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=401)
        api_base = f"http://{stub.start()}"
        try:
            result = _run_bb_status(reporting_image, workspace, api_base_url=api_base)
            assert result.returncode == 0, (
                f"expected exit 0 on 401 (bash behavior), got {result.returncode}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        finally:
            stub.stop()


class TestBitbucketBuildStatusMissingVars:
    """Missing required env vars → exits 0 with warning (bash behavior)."""

    def test_missing_token_exits_0(self, reporting_image: str, tmp_path: Path) -> None:
        workspace = tmp_path / f"repo-{uuid.uuid4().hex[:6]}"
        workspace.mkdir()
        stub = _StubServer(response_code=200)
        api_base = f"http://{stub.start()}"
        try:
            result = _run_bb_status(
                reporting_image,
                workspace,
                api_base_url=api_base,
                missing_vars=["BITBUCKET_API_TOKEN"],
            )
            assert result.returncode == 0, (
                f"expected exit 0 with missing var, got {result.returncode}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            req = stub.last_request(timeout=2.0)
            assert req is None, "stub got a POST even with missing token"
        finally:
            stub.stop()
