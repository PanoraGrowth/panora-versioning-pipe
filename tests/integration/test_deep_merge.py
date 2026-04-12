"""Unit tests for the deep_merge helper in conftest.py."""

import pytest

from conftest import deep_merge


class TestDeepMerge:
    """Covers all spec scenarios for deep_merge."""

    def test_nested_override_preserves_base_keys(self):
        """SCENARIO 1: nested dict override preserves sibling keys in base."""
        base = {
            "version": {
                "tag_prefix_v": True,
                "components": {"major": {"enabled": True}, "minor": {"enabled": True}},
            },
            "branches": {"tag_on": "main"},
        }
        override = {
            "version": {"components": {"patch": {"enabled": True}}},
        }
        result = deep_merge(base, override)
        # Override key added
        assert result["version"]["components"]["patch"] == {"enabled": True}
        # Base keys preserved
        assert result["version"]["components"]["major"] == {"enabled": True}
        assert result["version"]["components"]["minor"] == {"enabled": True}
        assert result["version"]["tag_prefix_v"] is True
        assert result["branches"]["tag_on"] == "main"

    def test_empty_override_returns_base(self):
        """SCENARIO 2: empty override does not modify base."""
        base = {"a": 1, "b": {"c": 2}}
        assert deep_merge(base, {}) == base

    def test_none_like_empty_override(self):
        """SCENARIO 2b: empty dict as override — same as no override."""
        base = {"x": {"y": 3}}
        result = deep_merge(base, {})
        assert result == base

    def test_new_key_added_without_losing_existing(self):
        """SCENARIO 3: new key in override is added alongside existing keys."""
        base = {"a": 1}
        override = {"b": 2}
        result = deep_merge(base, override)
        assert result == {"a": 1, "b": 2}

    def test_override_wins_on_conflict(self):
        """SCENARIO 4: override value wins when same key has different value."""
        base = {"a": 1, "b": {"c": "old"}}
        override = {"a": 99, "b": {"c": "new"}}
        result = deep_merge(base, override)
        assert result["a"] == 99
        assert result["b"]["c"] == "new"

    def test_override_scalar_replaces_dict(self):
        """Override with scalar replaces a dict in base (override wins)."""
        base = {"a": {"nested": True}}
        override = {"a": "flat"}
        result = deep_merge(base, override)
        assert result["a"] == "flat"

    def test_override_dict_replaces_scalar(self):
        """Override with dict replaces a scalar in base (override wins)."""
        base = {"a": "flat"}
        override = {"a": {"nested": True}}
        result = deep_merge(base, override)
        assert result["a"] == {"nested": True}

    def test_empty_base(self):
        """Empty base — override becomes the result."""
        override = {"a": {"b": 1}}
        assert deep_merge({}, override) == override

    def test_deeply_nested_merge(self):
        """Three levels deep — merge propagates correctly."""
        base = {"l1": {"l2": {"l3": {"keep": True, "replace": "old"}}}}
        override = {"l1": {"l2": {"l3": {"replace": "new", "add": "yes"}}}}
        result = deep_merge(base, override)
        assert result["l1"]["l2"]["l3"] == {
            "keep": True,
            "replace": "new",
            "add": "yes",
        }

    def test_does_not_mutate_base(self):
        """Ensure base dict is not mutated by the merge."""
        base = {"a": {"b": 1}}
        override = {"a": {"c": 2}}
        deep_merge(base, override)
        assert base == {"a": {"b": 1}}

    def test_does_not_mutate_override(self):
        """Ensure override dict is not mutated by the merge."""
        base = {"a": {"b": 1}}
        override = {"a": {"c": 2}}
        deep_merge(base, override)
        assert override == {"a": {"c": 2}}

    def test_list_override_wins(self):
        """Lists are NOT deep-merged — override wins entirely."""
        base = {"folders": ["a", "b"]}
        override = {"folders": ["c"]}
        result = deep_merge(base, override)
        assert result["folders"] == ["c"]
