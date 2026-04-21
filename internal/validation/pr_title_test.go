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
						Values: []string{"Hotfix/*", "hotfix/*"},
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
						Values: []string{"Hotfix/*", "hotfix/*"},
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

func TestSimpleGlobMatch(t *testing.T) {
	tests := []struct {
		s       string
		pattern string
		want    bool
	}{
		{"Hotfix/something", "Hotfix/*", true},
		{"hotfix/something", "hotfix/*", true},
		{"hotfix/fix for critical", "hotfix/*", true},
		{"other/something", "Hotfix/*", false},
		{"Hotfix", "Hotfix/*", false},
		{"exactmatch", "exactmatch", true},
		{"exactmatch", "exact", false},
		{"a", "?", true},
		{"ab", "?", false},
		{"abc", "a?c", true},
		{"ac", "a?c", false},
		{"anything", "a*g", true},
		{"ag", "a*g", true},
		{"", "a*g", false},
	}

	for _, tt := range tests {
		t.Run(tt.s+"_"+tt.pattern, func(t *testing.T) {
			if got := simpleGlobMatch(tt.s, tt.pattern); got != tt.want {
				t.Errorf("simpleGlobMatch(%q, %q) = %v, want %v",
					tt.s, tt.pattern, got, tt.want)
			}
		})
	}
}
