"""GitHub API client wrapping the `gh` CLI.

Uses the already-authenticated gh CLI to avoid token management.
All operations target the test repository (configurable via env var).
"""

import json
import os
import subprocess
import time


DEFAULT_REPO = "PanoraGrowth/panora-versioning-pipe-test"
POLL_INTERVAL = 10  # seconds between status checks
MAX_WAIT = 300  # 5 minutes max wait for pipelines


class GitHubClient:
    def __init__(self, repo: str | None = None):
        self.repo = repo or os.environ.get("TEST_REPO", DEFAULT_REPO)

    def _gh(self, args: list[str], check: bool = True) -> str:
        """Run a gh CLI command and return stdout."""
        cmd = ["gh"] + args + ["-R", self.repo]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if check and result.returncode != 0:
            raise RuntimeError(
                f"gh command failed: {' '.join(cmd)}\n"
                f"stderr: {result.stderr}\nstdout: {result.stdout}"
            )
        return result.stdout.strip()

    def _gh_api(self, endpoint: str, method: str = "GET", fields: dict | None = None) -> dict:
        """Call the GitHub REST API via gh api."""
        cmd = ["gh", "api", f"repos/{self.repo}/{endpoint}"]
        if method != "GET":
            cmd += ["--method", method]
        if fields:
            for k, v in fields.items():
                cmd += ["-f", f"{k}={v}"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            raise RuntimeError(f"gh api failed: {endpoint}\n{result.stderr}")
        return json.loads(result.stdout) if result.stdout.strip() else {}

    # --- Branch operations ---

    def get_default_branch_sha(self) -> str:
        data = self._gh_api("git/ref/heads/main")
        return data["object"]["sha"]

    def create_branch(self, name: str, from_sha: str | None = None) -> None:
        sha = from_sha or self.get_default_branch_sha()
        self._gh_api(
            "git/refs",
            method="POST",
            fields={"ref": f"refs/heads/{name}", "sha": sha},
        )

    def delete_branch(self, name: str) -> None:
        try:
            subprocess.run(
                ["gh", "api", f"repos/{self.repo}/git/refs/heads/{name}",
                 "--method", "DELETE"],
                capture_output=True, text=True, timeout=30,
            )
        except Exception:
            pass  # best effort cleanup

    # --- Commit operations ---

    def create_commit(self, branch: str, message: str, files: dict[str, str]) -> str:
        """Create a commit on a branch with the given files.

        Uses the Git Data API (trees + commits) to avoid needing a local clone.
        Sends JSON via stdin to handle nested objects (tree array).
        """
        # Get current branch tip
        ref_data = self._gh_api(f"git/ref/heads/{branch}")
        parent_sha = ref_data["object"]["sha"]
        parent_commit = self._gh_api(f"git/commits/{parent_sha}")
        base_tree = parent_commit["tree"]["sha"]

        # Create blobs for each file
        tree_items = []
        for path, content in files.items():
            blob_payload = json.dumps({"content": content, "encoding": "utf-8"})
            blob_result = subprocess.run(
                ["gh", "api", f"repos/{self.repo}/git/blobs", "--method", "POST", "--input", "-"],
                input=blob_payload, capture_output=True, text=True, timeout=60,
            )
            if blob_result.returncode != 0:
                raise RuntimeError(f"Create blob failed: {blob_result.stderr}")
            blob = json.loads(blob_result.stdout)
            tree_items.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})

        # Create tree (JSON via stdin for nested array)
        tree_payload = json.dumps({"base_tree": base_tree, "tree": tree_items})
        tree_result = subprocess.run(
            ["gh", "api", f"repos/{self.repo}/git/trees", "--method", "POST", "--input", "-"],
            input=tree_payload, capture_output=True, text=True, timeout=60,
        )
        if tree_result.returncode != 0:
            raise RuntimeError(f"Create tree failed: {tree_result.stderr}")
        tree_data = json.loads(tree_result.stdout)

        # Create commit (JSON via stdin for parents array)
        commit_payload = json.dumps({
            "message": message,
            "tree": tree_data["sha"],
            "parents": [parent_sha],
        })
        commit_result = subprocess.run(
            ["gh", "api", f"repos/{self.repo}/git/commits", "--method", "POST", "--input", "-"],
            input=commit_payload, capture_output=True, text=True, timeout=60,
        )
        if commit_result.returncode != 0:
            raise RuntimeError(f"Create commit failed: {commit_result.stderr}")
        commit = json.loads(commit_result.stdout)

        # Update branch ref
        ref_payload = json.dumps({"sha": commit["sha"]})
        subprocess.run(
            ["gh", "api", f"repos/{self.repo}/git/refs/heads/{branch}",
             "--method", "PATCH", "--input", "-"],
            input=ref_payload, capture_output=True, text=True, timeout=30,
        )

        return commit["sha"]

    # --- PR operations ---

    def create_pr(self, head: str, base: str, title: str) -> dict:
        output = self._gh(["pr", "create", "--head", head, "--base", base,
                           "--title", title, "--body", "Automated integration test"])
        # gh pr create returns the PR URL — extract number
        pr_number = output.strip().split("/")[-1]
        return {"number": int(pr_number), "url": output.strip()}

    def merge_pr(
        self, pr_number: int, method: str = "squash", subject: str | None = None,
    ) -> None:
        """Merge PR using gh CLI with --admin to bypass branch protection.

        Note: --admin bypasses rulesets but still generates push events
        that trigger workflows when used with the CLI (not always true
        with the REST API PUT endpoint).

        subject: override the commit subject for squash merges (gh --subject).
        """
        cmd = ["pr", "merge", str(pr_number), f"--{method}", "--admin"]
        if subject:
            cmd.extend(["--subject", subject])
        self._gh(cmd)

    def close_pr(self, pr_number: int) -> None:
        try:
            self._gh(["pr", "close", str(pr_number)], check=False)
        except Exception:
            pass

    # --- Check / workflow status ---

    def wait_for_checks(self, pr_number: int, timeout: int = MAX_WAIT) -> str:
        """Wait for PR checks to complete. Returns 'pass' or 'fail'.

        gh pr checks --json fields: name, state, bucket, description, event, link, startedAt, completedAt, workflow.
        state values: SUCCESS, FAILURE, PENDING, QUEUED, etc.
        Terminal states: SUCCESS, FAILURE, CANCELLED, SKIPPED, STALE, ERROR, STARTUP_FAILURE, NEUTRAL, TIMED_OUT, ACTION_REQUIRED.
        """
        terminal_states = {"SUCCESS", "FAILURE", "CANCELLED", "SKIPPED", "STALE",
                           "ERROR", "STARTUP_FAILURE", "NEUTRAL", "TIMED_OUT", "ACTION_REQUIRED"}
        deadline = time.time() + timeout
        while time.time() < deadline:
            result = subprocess.run(
                ["gh", "pr", "checks", str(pr_number), "-R", self.repo, "--json",
                 "name,state"],
                capture_output=True, text=True, timeout=30,
            )
            if result.returncode != 0 or not result.stdout.strip():
                time.sleep(POLL_INTERVAL)
                continue

            checks = json.loads(result.stdout)
            if not checks:
                time.sleep(POLL_INTERVAL)
                continue

            # Check if all checks reached a terminal state
            all_done = all(c.get("state", "").upper() in terminal_states for c in checks)
            if not all_done:
                time.sleep(POLL_INTERVAL)
                continue

            # All done — check if all succeeded
            all_pass = all(c.get("state", "").upper() == "SUCCESS" for c in checks)
            return "pass" if all_pass else "fail"

        raise TimeoutError(f"PR #{pr_number} checks did not complete within {timeout}s")

    def dispatch_tag_workflow(self) -> None:
        """Manually trigger tag-on-merge via workflow_dispatch.

        Used as fallback when the push event doesn't trigger the workflow
        (GitHub race condition with paths-ignore after CHANGELOG pushes).
        """
        subprocess.run(
            ["gh", "workflow", "run", "tag-on-merge.yml", "-R", self.repo,
             "--ref", "main"],
            capture_output=True, text=True, timeout=60,
        )

    def get_latest_workflow_run_id(self) -> int | None:
        """Get the database ID of the latest tag-on-merge workflow run."""
        result = subprocess.run(
            ["gh", "run", "list", "-R", self.repo, "--workflow", "tag-on-merge.yml",
             "--limit", "1", "--json", "databaseId"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return None
        runs = json.loads(result.stdout)
        return runs[0]["databaseId"] if runs else None

    def wait_for_tag_workflow(self, previous_run_id: int | None = None,
                              timeout: int = MAX_WAIT) -> bool:
        """Wait for a NEW tag-on-merge workflow run to complete.

        If previous_run_id is provided, waits until a run with a DIFFERENT ID
        appears and completes. This prevents returning early when seeing a
        previously completed run.
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            result = subprocess.run(
                ["gh", "run", "list", "-R", self.repo, "--workflow", "tag-on-merge.yml",
                 "--limit", "1", "--json", "databaseId,status,conclusion"],
                capture_output=True, text=True, timeout=60,
            )
            if result.returncode != 0:
                time.sleep(POLL_INTERVAL)
                continue

            runs = json.loads(result.stdout)
            if not runs:
                time.sleep(POLL_INTERVAL)
                continue

            run = runs[0]

            # If we're waiting for a NEW run, skip if it's the same old one
            if previous_run_id and run["databaseId"] == previous_run_id:
                time.sleep(POLL_INTERVAL)
                continue

            # We found a new (or any) run — wait for it to complete
            if run["status"] == "completed":
                return run["conclusion"] == "success"

            time.sleep(POLL_INTERVAL)

        raise TimeoutError("Tag workflow did not complete")

    # --- Tag operations ---

    def get_latest_tag(self) -> str | None:
        """Get the most recent tag by date."""
        result = subprocess.run(
            ["gh", "api", f"repos/{self.repo}/tags", "--jq", ".[0].name"],
            capture_output=True, text=True, timeout=30,
        )
        return result.stdout.strip() if result.stdout.strip() else None

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
            subprocess.run(
                ["gh", "api", f"repos/{self.repo}/git/refs/tags/{tag_name}",
                 "--method", "DELETE"],
                capture_output=True, text=True, timeout=30,
            )
        except Exception:
            pass

    # --- File content ---

    def get_file_content(self, path: str, ref: str = "main") -> str | None:
        """Get file content from the repo at a given ref."""
        result = subprocess.run(
            ["gh", "api", f"repos/{self.repo}/contents/{path}?ref={ref}",
             "-H", "Accept: application/vnd.github.raw+json"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return None
        return result.stdout
