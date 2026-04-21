package versioning

import (
	"testing"
)

// TestNextVersionHotfix_SchemaAware validates schema-aware hotfix tag emission
// (ticket 074 parte 2). nextHotfixVersion must delegate to buildVersionString —
// no hardcoded 4-slot format, no "base=0" placeholder.
//
// Cases marked [legacy] use latestTag in the old 4-slot format (v1.0.0.N)
// produced by earlier Go pipe versions. They are still read correctly via the
// parseVersionSlots legacy compat path (hotfix_counter from last slot), and
// re-emitted in the current schema (3-slot when epoch disabled).
//
// Pre-074 expected values are noted inline for historical reference.
func TestNextVersionHotfix_SchemaAware(t *testing.T) {
	cfg := VersionConfig{
		MajorEnabled:         true,
		MajorInitial:         0,
		PatchEnabled:         true,
		PatchInitial:         0,
		HotfixCounterEnabled: true,
		HotfixCounterInitial: 0,
		TagPrefixV:           true,
	}

	cases := []struct {
		name      string
		latestTag string
		want      string
	}{
		{
			// Pre-074: "v0.0.0.1" (4-slot with base=0 placeholder — was the bug)
			name:      "cold start",
			latestTag: "",
			want:      "v0.0.1",
		},
		{
			// latestTag is 3-slot: major=1, patch=0, hotfixCounter=0 → incr → 1 → "v1.0.1"
			// Pre-074: "v1.0.0.1" (4-slot, treated "0" as base slot)
			name:      "first hotfix on 3-part tag",
			latestTag: "v1.0.0",
			want:      "v1.0.1",
		},
		{
			// [legacy] latestTag is old-format 4-slot: hotfix_counter read from last slot (3) → incr → 4
			// Re-emitted as 3-slot per current schema. Pre-074: "v1.0.0.4"
			name:      "increment existing hotfix counter (legacy 4-slot)",
			latestTag: "v1.0.0.3",
			want:      "v1.0.4",
		},
		{
			// [legacy] hotfix_counter=9 from last slot → incr → 10 → "v2.5.10". Pre-074: "v2.5.1.10"
			name:      "hotfix counter wraps correctly from high base (legacy 4-slot)",
			latestTag: "v2.5.1.9",
			want:      "v2.5.10",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := NextVersion(tc.latestTag, BumpHotfix, cfg)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// TestNextVersionHotfix_NewCases covers the 6 acceptance criteria cases
// from ticket 074 parte 2.
func TestNextVersionHotfix_NewCases(t *testing.T) {
	t.Run("cold start 3-slot schema epoch off", func(t *testing.T) {
		cfg := VersionConfig{
			MajorEnabled:         true,
			MajorInitial:         1,
			PatchEnabled:         true,
			PatchInitial:         0,
			HotfixCounterEnabled: true,
			HotfixCounterInitial: 0,
			TagPrefixV:           true,
		}
		got, err := NextVersion("", BumpHotfix, cfg)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v1.0.1" {
			t.Errorf("got %q, want %q", got, "v1.0.1")
		}
	})

	t.Run("cold start 4-slot schema epoch on", func(t *testing.T) {
		cfg := VersionConfig{
			EpochEnabled:         true,
			EpochInitial:         1,
			MajorEnabled:         true,
			MajorInitial:         12,
			PatchEnabled:         true,
			PatchInitial:         1,
			HotfixCounterEnabled: true,
			HotfixCounterInitial: 0,
			TagPrefixV:           true,
		}
		got, err := NextVersion("", BumpHotfix, cfg)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v1.12.1.1" {
			t.Errorf("got %q, want %q", got, "v1.12.1.1")
		}
	})

	t.Run("latest 2-slot hotfix bump", func(t *testing.T) {
		cfg := VersionConfig{
			MajorEnabled:         true,
			MajorInitial:         0,
			PatchEnabled:         true,
			PatchInitial:         0,
			HotfixCounterEnabled: true,
			HotfixCounterInitial: 0,
			TagPrefixV:           true,
		}
		got, err := NextVersion("v12.1", BumpHotfix, cfg)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v12.1.1" {
			t.Errorf("got %q, want %q", got, "v12.1.1")
		}
	})

	t.Run("latest 3-slot hotfix bump", func(t *testing.T) {
		cfg := VersionConfig{
			MajorEnabled:         true,
			MajorInitial:         0,
			PatchEnabled:         true,
			PatchInitial:         0,
			HotfixCounterEnabled: true,
			HotfixCounterInitial: 0,
			TagPrefixV:           true,
		}
		got, err := NextVersion("v12.1.5", BumpHotfix, cfg)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v12.1.6" {
			t.Errorf("got %q, want %q", got, "v12.1.6")
		}
	})

	t.Run("latest legacy 4-slot compat re-emitted as 3-slot", func(t *testing.T) {
		// v12.1.0.1: legacy 4-slot, hotfix_counter=1 (last slot).
		// Schema: epoch off → 3-slot. Incr → 2. Emits "v12.1.2".
		cfg := VersionConfig{
			MajorEnabled:         true,
			MajorInitial:         0,
			PatchEnabled:         true,
			PatchInitial:         0,
			HotfixCounterEnabled: true,
			HotfixCounterInitial: 0,
			TagPrefixV:           true,
		}
		got, err := NextVersion("v12.1.0.1", BumpHotfix, cfg)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v12.1.2" {
			t.Errorf("got %q, want %q", got, "v12.1.2")
		}
	})

	t.Run("epoch on latest 4-slot hotfix bump", func(t *testing.T) {
		cfg := VersionConfig{
			EpochEnabled:         true,
			EpochInitial:         0,
			MajorEnabled:         true,
			MajorInitial:         0,
			PatchEnabled:         true,
			PatchInitial:         0,
			HotfixCounterEnabled: true,
			HotfixCounterInitial: 0,
			TagPrefixV:           true,
		}
		got, err := NextVersion("v1.12.1.3", BumpHotfix, cfg)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v1.12.1.4" {
			t.Errorf("got %q, want %q", got, "v1.12.1.4")
		}
	})
}

func TestBumpHotfixConstant(t *testing.T) {
	if string(BumpHotfix) != "hotfix" {
		t.Errorf("BumpHotfix must equal %q, got %q", "hotfix", BumpHotfix)
	}
}

// TestNextVersionSchemaAware validates schema-aware slot bumping.
// Schema: major+patch (epoch disabled, hotfix_counter disabled).
// Tags are 2-slot: major.patch (e.g. v1.0, v1.1, v2.0).
// A 3-slot tag like v1.0.0 is parsed as major=1, patch=0 (3rd part ignored
// — no active slot for it in this schema).
func TestNextVersionSchemaAware(t *testing.T) {
	cfg := VersionConfig{
		MajorEnabled: true,
		PatchEnabled: true,
		TagPrefixV:   true,
	}

	cases := []struct {
		name string
		bump BumpType
		tag  string
		want string
	}{
		// BumpMinor (feat): post-ticket-042 bumps patch slot (3rd active slot)
		{"minor from 2-slot tag", BumpMinor, "v1.0", "v1.1"},
		// BumpPatch (fix): same slot as minor
		{"patch from 2-slot tag", BumpPatch, "v1.0", "v1.1"},
		// BumpMajor: major+1, patch resets
		{"major from 2-slot tag", BumpMajor, "v1.0", "v2.0"},
		// Tags with 3 parts are parsed by active slots only: major=1, patch=0
		{"minor from 3-slot tag (3rd ignored)", BumpMinor, "v1.0.0", "v1.1"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := NextVersion(tc.tag, tc.bump, cfg)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// TestNextVersionEpochMajorPatch validates the FINDING MEDIUM fix.
// Schema: epoch+major+patch (3 active slots). BumpMinor (feat) must increment
// the patch slot (3rd slot), not semver minor (2nd slot).
// Before this fix: Go produced v0.1.0 from cold start. Bash: v0.0.1.
func TestNextVersionEpochMajorPatch(t *testing.T) {
	cfg := VersionConfig{
		EpochEnabled: true,
		EpochInitial: 0,
		MajorEnabled: true,
		MajorInitial: 0,
		PatchEnabled: true,
		PatchInitial: 0,
		TagPrefixV:   true,
	}

	cases := []struct {
		name string
		bump BumpType
		tag  string
		want string
	}{
		{"feat cold start → v0.0.1", BumpMinor, "", "v0.0.1"},
		{"fix cold start → v0.0.1", BumpPatch, "", "v0.0.1"},
		{"feat from v0.0.1 → v0.0.2", BumpMinor, "v0.0.1", "v0.0.2"},
		{"major from v0.0.5 → v0.1.0", BumpMajor, "v0.0.5", "v0.1.0"},
		{"major resets patch → v1.0.0 from v0.3.7", BumpMajor, "v0.3.7", "v0.4.0"},
		// Schema epoch+major: epoch namespace rotation
		{"epoch major initial=1 cold start minor", BumpMinor, "", "v0.0.1"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := NextVersion(tc.tag, tc.bump, cfg)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}
