package hotfix_test

import (
	"strings"
	"testing"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/hotfix"
)

func TestMatcherSinglePatternPositiveAndNegative(t *testing.T) {
	m, err := hotfix.NewMatcher([]string{`^hotfix:`})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	if !m.Matches("hotfix: urgent fix") {
		t.Error("expected match for 'hotfix: urgent fix'")
	}
	if m.Matches("feat: new feature") {
		t.Error("expected no match for 'feat: new feature'")
	}
}

func TestMatcherInvalidRegexFailsFast(t *testing.T) {
	_, err := hotfix.NewMatcher([]string{`hotfix(*`})
	if err == nil {
		t.Fatal("expected error for invalid regex 'hotfix(*', got nil")
	}
	if !strings.Contains(err.Error(), `hotfix(*`) {
		t.Errorf("error should name the offending pattern, got: %v", err)
	}
}

func TestMatcherMultiplePatternsMatchIfAny(t *testing.T) {
	m, err := hotfix.NewMatcher([]string{
		`^hotfix(\(|:)`,
		`^[Hh]otfix/`,
		`URGENT-PATCH`,
	})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}

	cases := []struct {
		subject string
		want    bool
	}{
		{"hotfix: foo", true},
		{"hotfix(scope): foo", true},
		{"Hotfix/branch-name", true},
		{"hotfix/branch-name", true},
		{"URGENT-PATCH: rollback failing deploy", true},
		{"contains URGENT-PATCH inline", true},
		{"feat: nothing here", false},
		{"random subject", false},
	}
	for _, tc := range cases {
		if got := m.Matches(tc.subject); got != tc.want {
			t.Errorf("Matches(%q) = %v, want %v", tc.subject, got, tc.want)
		}
	}
}

func TestMatcherDefaultPatternsCoverExpectedCases(t *testing.T) {
	// Mirrors the defaults shipped in config/defaults/defaults.yml and
	// internal/config/config.go. If these defaults change, update both.
	defaults := []string{
		`^hotfix(\(|:)`,
		`^[Hh]otfix/`,
		`URGENT-PATCH`,
	}
	m, err := hotfix.NewMatcher(defaults)
	if err != nil {
		t.Fatalf("NewMatcher(defaults): %v", err)
	}

	mustMatch := []string{
		"hotfix: urgent thing",
		"hotfix(auth): rotate keys",
		"Hotfix/urgent security patch",
		"hotfix/branch-from-pr",
		"URGENT-PATCH: emergency rollback",
	}
	for _, s := range mustMatch {
		if !m.Matches(s) {
			t.Errorf("default patterns should match %q, did not", s)
		}
	}

	mustNotMatch := []string{
		"feat(auth): add JWT",
		"fix: minor nit",
		"chore: update deps",
		"",
	}
	for _, s := range mustNotMatch {
		if m.Matches(s) {
			t.Errorf("default patterns should not match %q, did", s)
		}
	}
}

func TestMatcherEmptyPatternsAreSkipped(t *testing.T) {
	m, err := hotfix.NewMatcher([]string{"", `^hotfix:`, ""})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	if !m.Matches("hotfix: x") {
		t.Error("expected match after skipping empty patterns")
	}
}

func TestMatcherNoPatternsNeverMatches(t *testing.T) {
	m, err := hotfix.NewMatcher(nil)
	if err != nil {
		t.Fatalf("NewMatcher(nil): %v", err)
	}
	if m.Matches("hotfix: anything") {
		t.Error("matcher with no patterns must not match")
	}
}

func TestMatcherNilSafe(t *testing.T) {
	var m *hotfix.Matcher
	if m.Matches("hotfix: x") {
		t.Error("nil matcher must not match")
	}
}
