"""Bitbucket API client using the REST API v2.0.

Uses a Repository Access Token (BB_TOKEN) for authentication.
All operations target the test repository (configurable via env vars).
"""

import os
import time

import requests


DEFAULT_WORKSPACE = "panoragrowth"
DEFAULT_REPO = "panora-versioning-pipe-bitbucket"
POLL_INTERVAL = 10  # seconds between status checks
MAX_WAIT = 300  # 5 minutes max wait for pipelines


class BitbucketClient:
    BASE_URL = "https://api.bitbucket.org/2.0"

    def __init__(self, workspace: str | None = None, repo_slug: str | None = None):
        token = os.environ.get("BB_TOKEN")
        if not token:
            raise RuntimeError("BB_TOKEN environment variable is required")
        self.workspace = workspace or os.environ.get("BB_WORKSPACE", DEFAULT_WORKSPACE)
        self.repo_slug = repo_slug or os.environ.get("BB_REPO", DEFAULT_REPO)
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {token}",
        })

    def _url(self, path: str) -> str:
        return f"{self.BASE_URL}/repositories/{self.workspace}/{self.repo_slug}/{path}"

    def _get(self, path: str, **kwargs) -> dict:
        r = self.session.get(self._url(path), **kwargs)
        r.raise_for_status()
        return r.json()

    def _post(self, path: str, **kwargs) -> dict:
        r = self.session.post(self._url(path), **kwargs)
        r.raise_for_status()
        return r.json()

    def _delete(self, path: str) -> None:
        r = self.session.delete(self._url(path))
        # 404 is fine for cleanup (already deleted)
        if r.status_code != 404:
            r.raise_for_status()

    # --- Branch operations ---

    def get_default_branch_sha(self) -> str:
        data = self._get("refs/branches/main")
        return data["target"]["hash"]

    def create_branch(self, name: str, from_sha: str | None = None) -> None:
        sha = from_sha or self.get_default_branch_sha()
        self._post("refs/branches", json={
            "name": name,
            "target": {"hash": sha},
        })

    def delete_branch(self, name: str) -> None:
        try:
            self._delete(f"refs/branches/{name}")
        except Exception:
            pass  # best effort cleanup

    # --- Commit operations ---

    def create_commit(self, branch: str, message: str, files: dict[str, str]) -> str:
        """Create a commit on a branch with the given files.

        Uses the Bitbucket /src endpoint which accepts form data.
        Each file path is a form field with the content as value.
        """
        form_data = {
            "message": message,
            "branch": branch,
        }
        # Files are sent as form fields — path as key, content as value
        for path, content in files.items():
            form_data[path] = content

        r = self.session.post(self._url("src"), data=form_data)
        r.raise_for_status()

        # Get the new commit hash from the branch tip
        branch_data = self._get(f"refs/branches/{branch}")
        return branch_data["target"]["hash"]

    # --- PR operations ---

    def create_pr(self, head: str, base: str, title: str) -> dict:
        data = self._post("pullrequests", json={
            "title": title,
            "source": {"branch": {"name": head}},
            "destination": {"branch": {"name": base}},
            "close_source_branch": False,
        })
        return {"number": data["id"], "url": data["links"]["html"]["href"]}

    def merge_pr(self, pr_number: int, method: str = "squash",
                 message: str | None = None) -> None:
        """Merge PR. Bitbucket strategies: squash, merge_commit, fast_forward.

        Unlike GitHub, Bitbucket squash merge defaults to "Merged in branch
        (pull request #N)" which loses the original commit message.
        Pass `message` to preserve the conventional commit subject.
        """
        strategy_map = {
            "squash": "squash",
            "merge": "merge_commit",
        }
        body = {
            "merge_strategy": strategy_map.get(method, "squash"),
            "close_source_branch": False,
        }
        if message:
            body["message"] = message
        self._post(f"pullrequests/{pr_number}/merge", json=body)

    def close_pr(self, pr_number: int) -> None:
        try:
            self._post(f"pullrequests/{pr_number}/decline")
        except Exception:
            pass

    # --- Pipeline / build status ---

    def wait_for_checks(self, pr_number: int, timeout: int = MAX_WAIT) -> str:
        """Wait for PR pipeline to complete. Returns 'pass' or 'fail'.

        Polls the PR build statuses endpoint. Bitbucket Pipelines reports
        status as SUCCESSFUL, FAILED, INPROGRESS, or STOPPED.
        """
        terminal_states = {"SUCCESSFUL", "FAILED", "STOPPED"}
        deadline = time.time() + timeout
        while time.time() < deadline:
            data = self._get(f"pullrequests/{pr_number}/statuses")
            values = data.get("values", [])

            if values:
                all_terminal = all(
                    s.get("state", "").upper() in terminal_states
                    for s in values
                )
                if all_terminal:
                    all_pass = all(
                        s.get("state", "").upper() == "SUCCESSFUL"
                        for s in values
                    )
                    return "pass" if all_pass else "fail"

            time.sleep(POLL_INTERVAL)

        raise TimeoutError(f"PR #{pr_number} checks did not complete within {timeout}s")

    def get_latest_pipeline(self) -> dict | None:
        """Get the latest pipeline run."""
        data = self._get("pipelines/?sort=-created_on&pagelen=1")
        values = data.get("values", [])
        return values[0] if values else None

    def wait_for_main_pipeline(self, previous_uuid: str | None = None,
                               timeout: int = MAX_WAIT) -> bool:
        """Wait for a new pipeline on main to complete.

        If previous_uuid is provided, skips that run and waits for a new one.
        Returns True if the pipeline succeeded.
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            pipeline = self.get_latest_pipeline()
            if pipeline:
                pipe_uuid = pipeline["uuid"]
                state_name = pipeline["state"]["name"]

                # Skip the previous pipeline
                if previous_uuid and pipe_uuid == previous_uuid:
                    time.sleep(POLL_INTERVAL)
                    continue

                if state_name == "COMPLETED":
                    result = pipeline["state"].get("result", {}).get("name", "")
                    return result == "SUCCESSFUL"
                elif state_name in ("ERROR", "HALTED"):
                    return False

            time.sleep(POLL_INTERVAL)

        raise TimeoutError(f"Main pipeline did not complete within {timeout}s")

    # --- Tag operations ---

    def get_latest_tag(self) -> str | None:
        """Get the most recently created tag."""
        data = self._get("refs/tags?sort=-target.date&pagelen=1")
        values = data.get("values", [])
        return values[0]["name"] if values else None

    def wait_for_new_tag(self, previous_tag: str | None,
                         timeout: int = MAX_WAIT) -> str:
        """Poll until a new tag appears that differs from previous_tag."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            current = self.get_latest_tag()
            if current and current != previous_tag:
                return current
            time.sleep(POLL_INTERVAL)
        raise TimeoutError(
            f"No new tag appeared after {timeout}s. Last tag: {previous_tag}"
        )

    def delete_tag(self, tag_name: str) -> None:
        try:
            self._delete(f"refs/tags/{tag_name}")
        except Exception:
            pass

    # --- File content ---

    def get_file_content(self, path: str, ref: str = "main") -> str | None:
        """Get raw file content from the repo at a given ref."""
        r = self.session.get(self._url(f"src/{ref}/{path}"))
        if r.status_code != 200:
            return None
        return r.text
