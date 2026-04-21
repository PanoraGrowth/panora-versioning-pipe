package guardrails

import (
	"bytes"
	"strings"
	"testing"
)

// hotfixCfg returns a Config with major+patch+hotfix_counter enabled, epoch disabled.
// Mirrors the scenario hotfix-patch-bump-regression from EPIC001-068R Fase C.
func hotfixCfg() Config {
	return Config{
		Version: VersionConfig{
			Components: ComponentsConfig{
				Epoch:         ComponentConfig{Enabled: false},
				Major:         ComponentConfig{Enabled: true},
				Patch:         ComponentConfig{Enabled: true},
				HotfixCounter: ComponentConfig{Enabled: true},
			},
		},
	}
}

func runGuardrail(next, latest string, bump BumpType, cfg Config) (warned bool, err error) {
	ctx := RunContext{
		Cfg:       cfg,
		NextTag:   next,
		LatestTag: latest,
		BumpType:  bump,
		Stderr:    &bytes.Buffer{},
		Stdout:    &bytes.Buffer{},
	}
	return AssertNoVersionRegression(ctx)
}

func violationOf(next, latest string, bump BumpType, cfg Config) string {
	ctx := RunContext{
		Cfg:       cfg,
		NextTag:   next,
		LatestTag: latest,
		BumpType:  bump,
		Stderr:    &bytes.Buffer{},
		Stdout:    &bytes.Buffer{},
	}
	_, err := AssertNoVersionRegression(ctx)
	if err == nil {
		return ""
	}
	// Error message format: "version regression: <violation> (next=..., latest=..., bump=...)"
	msg := err.Error()
	if idx := strings.Index(msg, "version regression: "); idx >= 0 {
		rest := msg[idx+len("version regression: "):]
		if end := strings.Index(rest, " ("); end >= 0 {
			return rest[:end]
		}
	}
	return msg
}

// TestParseTagHotfixCounter_4Slot covers the bug fixed in ticket 074:
// parseTag was reading hotfix_counter from the sequential position instead of
// the last slot when tags have more parts than enabled components.
func TestParseTagHotfixCounter_4Slot(t *testing.T) {
	cfg := hotfixCfg()

	cases := []struct {
		name          string
		next          string
		latest        string
		wantPass      bool
		wantViolation string
	}{
		{
			name:     "first hotfix after 2-slot tag",
			next:     "v12.1.0.1",
			latest:   "v12.1",
			wantPass: true,
		},
		{
			name:     "first hotfix after 3-slot tag",
			next:     "v12.1.0.1",
			latest:   "v12.1.0",
			wantPass: true,
		},
		{
			name:     "hotfix counter normal increment",
			next:     "v12.1.0.2",
			latest:   "v12.1.0.1",
			wantPass: true,
		},
		{
			name:          "hotfix counter not incremented (regression real)",
			next:          "v12.1.0.1",
			latest:        "v12.1.0.1",
			wantPass:      false,
			wantViolation: "hotfix_counter_not_incremented",
		},
		{
			name:          "hotfix counter downgrade (regression)",
			next:          "v12.1.0.1",
			latest:        "v12.1.0.2",
			wantPass:      false,
			wantViolation: "hotfix_counter_not_incremented",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := runGuardrail(tc.next, tc.latest, BumpHotfix, cfg)
			if tc.wantPass {
				if err != nil {
					t.Errorf("expected pass, got error: %v", err)
				}
			} else {
				if err == nil {
					t.Errorf("expected block with violation %q, got pass", tc.wantViolation)
					return
				}
				got := violationOf(tc.next, tc.latest, BumpHotfix, cfg)
				if got != tc.wantViolation {
					t.Errorf("expected violation %q, got %q", tc.wantViolation, got)
				}
			}
		})
	}
}
