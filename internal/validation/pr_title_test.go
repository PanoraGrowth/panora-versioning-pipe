package validation

import (
	"strings"
	"testing"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

func ptrBool(b bool) *bool {
	return &b
}

func TestValidatePRTitle(t *testing.T) {
	tests := []struct {
		name    string
		title   string
		cfg     *config.Config
		wantErr bool
	}{
		{
			name:  "conventional valid with scope",
			title: "feat(auth): add JWT support",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
					{Name: "chore", Bump: "none"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
			},
			wantErr: false,
		},
		{
			name:  "conventional valid without scope",
			title: "fix: resolve token expiry",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
					{Name: "chore", Bump: "none"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
			},
			wantErr: false,
		},
		{
			name:  "invalid title - not conventional",
			title: "Development (#17)",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
					{Name: "chore", Bump: "none"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
			},
			wantErr: true,
		},
		{
			name:  "invalid title - another example",
			title: "Add feature",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
					{Name: "chore", Bump: "none"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
			},
			wantErr: true,
		},
		{
			name:  "empty title - skip validation",
			title: "",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
			},
			wantErr: false,
		},
		{
			name:  "require_commit_types false - skip validation",
			title: "random garbage",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(false),
				},
			},
			wantErr: false,
		},
		{
			name:  "hotfix keyword match",
			title: "Hotfix/urgent security patch",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
				Hotfix: config.HotfixConfig{
					Keyword: config.HotfixKeywordList{
						Values: []string{`^[Hh]otfix/`},
					},
				},
			},
			wantErr: false,
		},
		{
			name:  "hotfix keyword lowercase",
			title: "hotfix/fix for critical bug",
			cfg: &config.Config{
				Commits: config.CommitsConfig{
					Format: "conventional",
				},
				CommitTypes: []config.CommitType{
					{Name: "feat", Bump: "minor"},
					{Name: "fix", Bump: "patch"},
				},
				Validation: config.ValidationConfig{
					RequireCommitTypes: ptrBool(true),
				},
				Hotfix: config.HotfixConfig{
					Keyword: config.HotfixKeywordList{
						Values: []string{`^[Hh]otfix/`},
					},
				},
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePRTitle(tt.title, tt.cfg)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidatePRTitle(%q, cfg) error = %v, wantErr %v",
					tt.title, err, tt.wantErr)
			}

			// Verify error message format when validation fails
			if err != nil && tt.wantErr {
				errMsg := err.Error()
				if !strings.Contains(errMsg, "NOT WELL-FORMED") {
					t.Errorf("error message missing 'NOT WELL-FORMED': %s", errMsg)
				}
				if !strings.Contains(errMsg, tt.title) {
					t.Errorf("error message missing PR title %q: %s", tt.title, errMsg)
				}
			}
		})
	}
}

// TestMatchesHotfixKeywordIntegration covers the wrapper matchesHotfixKeyword
// against the canonical default patterns. Full Matcher coverage lives in
// internal/hotfix/keyword_test.go.
func TestMatchesHotfixKeywordIntegration(t *testing.T) {
	cfg := &config.Config{
		Hotfix: config.HotfixConfig{
			Keyword: config.HotfixKeywordList{
				Values: []string{
					`^hotfix(\(|:)`,
					`^[Hh]otfix/`,
					`URGENT-PATCH`,
				},
			},
		},
	}
	cases := []struct {
		title string
		want  bool
	}{
		{"hotfix: foo", true},
		{"hotfix(scope): foo", true},
		{"Hotfix/branch-from-pr", true},
		{"hotfix/branch-from-pr", true},
		{"URGENT-PATCH: emergency rollback", true},
		{"contains URGENT-PATCH inline", true},
		{"feat: nothing here", false},
		{"", false},
	}
	for _, tc := range cases {
		if got := matchesHotfixKeyword(tc.title, cfg); got != tc.want {
			t.Errorf("matchesHotfixKeyword(%q) = %v, want %v", tc.title, got, tc.want)
		}
	}
}

// TestMatchesHotfixKeywordInvalidRegexNoMatch verifies that an invalid regex
// in config makes the wrapper return false (no match) rather than panic. The
// canonical fail-fast for invalid patterns belongs in config load, not here.
func TestMatchesHotfixKeywordInvalidRegexNoMatch(t *testing.T) {
	cfg := &config.Config{
		Hotfix: config.HotfixConfig{
			Keyword: config.HotfixKeywordList{
				Values: []string{`hotfix(*`},
			},
		},
	}
	if matchesHotfixKeyword("hotfix(scope): x", cfg) {
		t.Error("invalid regex must yield no match in the wrapper")
	}
}
