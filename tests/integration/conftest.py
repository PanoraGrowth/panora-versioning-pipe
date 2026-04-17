"""pytest configuration and fixtures for integration tests."""

import os
import uuid
from pathlib import Path

import pytest
import yaml

from helpers.github_client import GitHubClient
from helpers.bitbucket_client import BitbucketClient


SCENARIOS_FILE = Path(__file__).parent / "test-scenarios.yml"


def sandbox_major(base: str) -> int:
    """Return the sandbox major version number for a given base branch name.

    For a base like "sandbox-07", returns 7.
    For "main" or any non-sandbox base, returns 0.
    Each worker in a pytest-xdist run owns its own session + run_id (derived
    from uuid4()), so no cross-worker state sharing occurs.
    """
    if base.startswith("sandbox-"):
        try:
            return int(base.split("-")[1])
        except (IndexError, ValueError):
            return 0
    return 0


def deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base. Override wins on conflicts."""
    result = dict(base)
    for key, value in override.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_scenarios() -> list[dict]:
    """Load test scenarios from YAML file."""
    with open(SCENARIOS_FILE) as f:
        data = yaml.safe_load(f)
    return data["scenarios"]


def scenario_ids(scenarios: list[dict]) -> list[str]:
    """Generate pytest IDs from scenario names."""
    return [s["name"] for s in scenarios]


# Unique run ID for this test session (prevents branch name collisions)
RUN_ID = os.environ.get("TEST_RUN_ID", uuid.uuid4().hex[:8])


@pytest.fixture(scope="session")
def github():
    """GitHub client — shared across all tests in the session."""
    return GitHubClient()


@pytest.fixture(scope="session")
def bitbucket():
    """Bitbucket client — shared across all tests in the session."""
    return BitbucketClient()


@pytest.fixture(scope="session")
def run_id():
    """Unique ID for this test run."""
    return RUN_ID


@pytest.fixture
def branch_name(request, run_id):
    """Generate a unique branch name for each test."""
    # Get scenario name from test parameter if available
    scenario = getattr(request, "param", None)
    name = scenario["name"] if scenario else request.node.name
    return f"test/auto-{name}-{run_id}"
