"""Integration test for GO-04: notify-teams subcommand.

Runs `panora-versioning notify-teams` against a local HTTP stub server.
The stub captures the POST and lets us assert payload shape and headers
without hitting a real Teams webhook.

Loop contract (see references/integration-testing.md):
  1. Test fails first (exit 42 / stub) — confirmed before implementation.
  2. Implementation → test green.
  3. Log assertions are the point — exit code alone is not enough.
"""

from __future__ import annotations

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

PAYLOAD_TEMPLATE = """{{
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "type": "AdaptiveCard",
  "version": "1.4",
  "body": [
    {{
      "type": "TextBlock",
      "text": "$NOTIFICATION_TITLE"
    }},
    {{
      "type": "TextBlock",
      "text": "$NOTIFICATION_SUBTITLE"
    }},
    {{
      "type": "TextBlock",
      "text": "$BITBUCKET_BRANCH / $BITBUCKET_PR_ID / $BITBUCKET_COMMIT_SHORT / $BITBUCKET_PR_AUTHOR"
    }}
  ],
  "actions": [
    {{
      "type": "Action.OpenUrl",
      "title": "View Pipeline",
      "url": "https://bitbucket.org/$BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG/pipelines/results/$BITBUCKET_BUILD_NUMBER"
    }}
  ]
}}"""


def _docker_available() -> bool:
    return shutil.which("docker") is not None


pytestmark = pytest.mark.skipif(
    not _docker_available(),
    reason="docker CLI not available",
)


# ---------------------------------------------------------------------------
# Module-scoped image build
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
    """Thread-backed HTTP stub that captures the last POST body and status code."""

    def __init__(self, response_code: int = 200) -> None:
        self._response_code = response_code
        self._received: queue.Queue[dict[str, Any]] = queue.Queue()
        self._server: HTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self) -> str:
        """Start the server on an OS-assigned port; return host:port."""
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
                        "content_type": self.headers.get("Content-Type", ""),
                        "body": parsed,
                    }
                )
                self.send_response(response_code)
                self.end_headers()

            def log_message(self, *_: Any) -> None:  # silence default access log
                pass

        self._server = HTTPServer(("0.0.0.0", 0), _Handler)
        port = self._server.server_address[1]
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
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


def _write_config(tmp: Path, teams_enabled: bool = True) -> None:
    """Write a minimal .versioning-merged.yml with Teams settings."""
    enabled_str = "true" if teams_enabled else "false"
    (tmp / ".versioning-merged.yml").write_text(
        f"notifications:\n"
        f"  teams:\n"
        f"    enabled: {enabled_str}\n"
        f"    on_success: true\n"
        f"    on_failure: true\n"
        f"    payload_template: /tmp/webhook_payload.json\n"
    )


def _write_payload_template(tmp: Path) -> None:
    (tmp / "webhook_payload.json").write_text(PAYLOAD_TEMPLATE)


def _run_notify_teams(
    image: str,
    tmp_path: Path,
    trigger_type: str,
    webhook_url: str,
    *,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    tmp_dir = tmp_path / "tmp"
    tmp_dir.mkdir(exist_ok=True)
    _write_config(tmp_dir)
    _write_payload_template(tmp_dir)

    env_flags = [
        "-e", f"TEAMS_WEBHOOK_URL={webhook_url}",
        "-e", "VERSIONING_COMMIT=abc1234567890",
        "-e", "VERSIONING_PR_ID=42",
        "-e", "VERSIONING_BRANCH=feat/test-branch",
        "-e", "BITBUCKET_REPO_SLUG=my-repo",
        "-e", "BITBUCKET_WORKSPACE=my-workspace",
        "-e", "BITBUCKET_BUILD_NUMBER=99",
    ]
    if extra_env:
        for k, v in extra_env.items():
            env_flags += ["-e", f"{k}={v}"]

    return subprocess.run(
        [
            "docker", "run", "--rm",
            "--add-host", "host.docker.internal:host-gateway",
            "-v", f"{tmp_dir}:/tmp",
            "--entrypoint", BINARY,
            *env_flags,
            image,
            "notify-teams",
            trigger_type,
        ],
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestNotifyTeamsSuccess:
    """notify-teams success → exit 0, correct POST, no secret in logs."""

    def test_exit_0_on_200(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            result = _run_notify_teams(reporting_image, tmp_path, "success", url)
            assert result.returncode == 0, (
                f"expected exit 0, got {result.returncode}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        finally:
            stub.stop()

    def test_post_sent_to_stub(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            _run_notify_teams(reporting_image, tmp_path, "success", url)
            req = stub.last_request(timeout=5.0)
            assert req is not None, "stub received no POST — binary never sent the request"
            assert req["content_type"] == "application/json", (
                f"expected application/json, got {req['content_type']!r}"
            )
        finally:
            stub.stop()

    def test_payload_is_valid_json(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            _run_notify_teams(reporting_image, tmp_path, "success", url)
            req = stub.last_request(timeout=5.0)
            assert req is not None
            # body is already parsed by the stub — if it parsed, it was valid JSON
            assert isinstance(req["body"], dict), f"payload is not a dict: {req['body']!r}"
        finally:
            stub.stop()

    def test_log_contains_sent(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            result = _run_notify_teams(reporting_image, tmp_path, "success", url)
            combined = result.stdout + result.stderr
            assert "teams" in combined.lower(), (
                f"log missing Teams mention\noutput:\n{combined}"
            )
        finally:
            stub.stop()

    def test_webhook_url_not_logged(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        addr = stub.start()
        url = f"http://{addr}/webhook/{uuid.uuid4().hex}"
        try:
            result = _run_notify_teams(reporting_image, tmp_path, "success", url)
            combined = result.stdout + result.stderr
            assert url not in combined, (
                f"webhook URL leaked into logs!\noutput:\n{combined}"
            )
        finally:
            stub.stop()


class TestNotifyTeamsFailure:
    """notify-teams with server returning 500 → still exits 0 (bash behavior)."""

    def test_exit_0_on_500(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=500)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            result = _run_notify_teams(reporting_image, tmp_path, "success", url)
            # bash exits 0 even on 500 (only warns) — Go must preserve this
            assert result.returncode == 0, (
                f"expected exit 0 on 500 (bash behavior), got {result.returncode}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        finally:
            stub.stop()


class TestNotifyTeamsFailureTrigger:
    """notify-teams failure trigger → different title in payload."""

    def test_failure_payload_title(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            _run_notify_teams(reporting_image, tmp_path, "failure", url)
            req = stub.last_request(timeout=5.0)
            assert req is not None
            # The payload text should contain failure-related content
            body_str = json.dumps(req["body"]).lower()
            assert "failed" in body_str or "failure" in body_str or "❌" in body_str, (
                f"failure payload missing failure indicator\nbody: {body_str}"
            )
        finally:
            stub.stop()


class TestNotifyTeamsDisabled:
    """When Teams is disabled in config, binary exits 0 without POSTing."""

    def test_disabled_no_post(self, reporting_image: str, tmp_path: Path) -> None:
        stub = _StubServer(response_code=200)
        url = f"http://{stub.start()}/webhook/{uuid.uuid4().hex}"
        try:
            # Overwrite config with enabled=false
            tmp_dir = tmp_path / "tmp"
            tmp_dir.mkdir(exist_ok=True)
            (tmp_dir / ".versioning-merged.yml").write_text(
                "notifications:\n"
                "  teams:\n"
                "    enabled: false\n"
                "    on_success: true\n"
                "    on_failure: true\n"
                "    payload_template: /tmp/webhook_payload.json\n"
            )
            _write_payload_template(tmp_dir)

            result = subprocess.run(
                [
                    "docker", "run", "--rm",
                    "--add-host", "host.docker.internal:host-gateway",
                    "-v", f"{tmp_dir}:/tmp",
                    "--entrypoint", BINARY,
                    "-e", f"TEAMS_WEBHOOK_URL={url}",
                    "-e", "VERSIONING_COMMIT=abc1234567890",
                    "-e", "VERSIONING_PR_ID=42",
                    "-e", "VERSIONING_BRANCH=feat/test",
                    reporting_image,
                    "notify-teams", "success",
                ],
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0
            req = stub.last_request(timeout=2.0)
            assert req is None, "stub received POST even though Teams is disabled"
        finally:
            stub.stop()


class TestNotifyTeamsNoWebhookUrl:
    """When TEAMS_WEBHOOK_URL is missing, binary exits 0 (bash skips silently)."""

    def test_no_url_exits_0(self, reporting_image: str, tmp_path: Path) -> None:
        tmp_dir = tmp_path / "tmp"
        tmp_dir.mkdir(exist_ok=True)
        _write_config(tmp_dir)
        _write_payload_template(tmp_dir)

        result = subprocess.run(
            [
                "docker", "run", "--rm",
                "-v", f"{tmp_dir}:/tmp",
                "--entrypoint", BINARY,
                "-e", "VERSIONING_COMMIT=abc1234567890",
                "-e", "VERSIONING_PR_ID=42",
                "-e", "VERSIONING_BRANCH=feat/test",
                reporting_image,
                "notify-teams", "success",
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"expected exit 0 when URL missing, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
