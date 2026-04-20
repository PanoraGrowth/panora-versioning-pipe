package versioning

import (
	"testing"
)

func TestNextVersionHotfix(t *testing.T) {
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
			name:      "cold start",
			latestTag: "",
			want:      "v0.0.0.1",
		},
		{
			name:      "first hotfix on 3-part tag",
			latestTag: "v1.0.0",
			want:      "v1.0.0.1",
		},
		{
			name:      "increment existing hotfix counter",
			latestTag: "v1.0.0.3",
			want:      "v1.0.0.4",
		},
		{
			name:      "hotfix counter wraps correctly from high base",
			latestTag: "v2.5.1.9",
			want:      "v2.5.1.10",
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
