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

func TestNextVersionDoesNotBrakeExistingBumps(t *testing.T) {
	cfg := VersionConfig{
		MajorEnabled: true,
		PatchEnabled: true,
		TagPrefixV:   true,
	}

	cases := []struct {
		bump BumpType
		tag  string
		want string
	}{
		{BumpMinor, "v1.0.0", "v1.1.0"},
		{BumpPatch, "v1.0.0", "v1.0.1"},
		{BumpMajor, "v1.0.0", "v2.0.0"},
	}

	for _, tc := range cases {
		got, err := NextVersion(tc.tag, tc.bump, cfg)
		if err != nil {
			t.Fatalf("bump=%s: unexpected error: %v", tc.bump, err)
		}
		if got != tc.want {
			t.Errorf("bump=%s: got %q, want %q", tc.bump, got, tc.want)
		}
	}
}
