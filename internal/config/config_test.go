package config_test

import (
	"strings"
	"testing"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// fixtureDir is the path to the shared test fixtures.
const fixtureDir = "../../tests/fixtures"

type fixtureCase struct {
	file  string
	check func(t *testing.T, c *config.Config)
}

func TestLoadFixtures(t *testing.T) {
	cases := []fixtureCase{
		{
			file: "minimal.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Commits.Format != "ticket" {
					t.Errorf("commits.format: got %q, want %q", c.Commits.Format, "ticket")
				}
				// Defaults applied
				if c.Changelog.Mode != "last_commit" {
					t.Errorf("changelog.mode default: got %q", c.Changelog.Mode)
				}
				if c.Validation.HotfixTitleRequired != "error" {
					t.Errorf("validation.hotfix_title_required default: got %q", c.Validation.HotfixTitleRequired)
				}
				if !c.RequireCommitTypes() {
					t.Error("validation.require_commit_types default: want true")
				}
				if c.Branches.TagOn != "development" {
					t.Errorf("branches.tag_on default: got %q", c.Branches.TagOn)
				}
			},
		},
		{
			file: "conventional-full.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Commits.Format != "conventional" {
					t.Errorf("commits.format: got %q", c.Commits.Format)
				}
				if c.Changelog.Mode != "full" {
					t.Errorf("changelog.mode: got %q", c.Changelog.Mode)
				}
				if !c.Changelog.UseEmojis {
					t.Error("changelog.use_emojis: want true")
				}
				if !c.RequireCommitTypes() {
					t.Error("validation.require_commit_types: want true")
				}
			},
		},
		{
			file: "monorepo.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Commits.Format != "conventional" {
					t.Errorf("commits.format: got %q", c.Commits.Format)
				}
				if !c.Changelog.PerFolder.Enabled {
					t.Error("changelog.per_folder.enabled: want true")
				}
				if len(c.Changelog.PerFolder.Folders) != 2 {
					t.Errorf("per_folder.folders: got %d, want 2", len(c.Changelog.PerFolder.Folders))
				}
				if c.Changelog.PerFolder.ScopeMatching != "suffix" {
					t.Errorf("per_folder.scope_matching: got %q", c.Changelog.PerFolder.ScopeMatching)
				}
				if c.Changelog.PerFolder.Fallback != "root" {
					t.Errorf("per_folder.fallback: got %q", c.Changelog.PerFolder.Fallback)
				}
			},
		},
		{
			file: "monorepo-glob-folders.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Changelog.PerFolder.Enabled {
					t.Error("changelog.per_folder.enabled: want true")
				}
				if len(c.Changelog.PerFolder.Folders) != 1 {
					t.Errorf("per_folder.folders: got %d, want 1", len(c.Changelog.PerFolder.Folders))
				}
			},
		},
		{
			file: "monorepo-file-path-fallback.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Changelog.PerFolder.Fallback != "file_path" {
					t.Errorf("per_folder.fallback: got %q", c.Changelog.PerFolder.Fallback)
				}
				if c.Changelog.PerFolder.ScopeMatching != "exact" {
					t.Errorf("per_folder.scope_matching: got %q", c.Changelog.PerFolder.ScopeMatching)
				}
				if len(c.Changelog.PerFolder.Folders) != 3 {
					t.Errorf("per_folder.folders: got %d, want 3", len(c.Changelog.PerFolder.Folders))
				}
			},
		},
		{
			file: "monorepo-version-file-groups.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.VersionFile.Enabled {
					t.Error("version_file.enabled: want true")
				}
				if len(c.VersionFile.Groups) != 3 {
					t.Errorf("version_file.groups: got %d, want 3", len(c.VersionFile.Groups))
				}
				g := c.VersionFile.Groups[0]
				if g.Name != "frontend" {
					t.Errorf("groups[0].name: got %q", g.Name)
				}
				if len(g.TriggerPaths) != 2 {
					t.Errorf("groups[0].trigger_paths: got %d, want 2", len(g.TriggerPaths))
				}
				if len(g.Files) != 1 {
					t.Errorf("groups[0].files: got %d, want 1", len(g.Files))
				}
			},
		},
		{
			file: "all-components.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Version.Components.Epoch.Enabled {
					t.Error("version.components.epoch.enabled: want true")
				}
				if c.Version.Components.Epoch.Initial != 1 {
					t.Errorf("version.components.epoch.initial: got %d", c.Version.Components.Epoch.Initial)
				}
				if !c.Version.Components.Timestamp.Enabled {
					t.Error("version.components.timestamp.enabled: want true")
				}
				if c.Version.Components.Timestamp.Format != "%Y%m%d%H%M%S" {
					t.Errorf("timestamp.format: got %q", c.Version.Components.Timestamp.Format)
				}
			},
		},
		{
			file: "with-hotfix-counter.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Version.TagPrefixV {
					t.Error("version.tag_prefix_v: want true")
				}
				if !c.Version.Components.HotfixCounter.Enabled {
					t.Error("version.components.hotfix_counter.enabled: want true")
				}
				if c.Version.Components.Timestamp.Enabled {
					t.Error("version.components.timestamp.enabled: want false")
				}
			},
		},
		{
			file: "hotfix-counter-disabled.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Version.Components.HotfixCounter.Enabled {
					t.Error("version.components.hotfix_counter.enabled: want false")
				}
			},
		},
		{
			file: "hotfix-title-warn.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Validation.HotfixTitleRequired != "warn" {
					t.Errorf("validation.hotfix_title_required: got %q", c.Validation.HotfixTitleRequired)
				}
				if len(c.Branches.HotfixTargets) != 1 {
					t.Errorf("branches.hotfix_targets: got %d, want 1", len(c.Branches.HotfixTargets))
				}
			},
		},
		{
			file: "ticket-based.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Commits.Format != "ticket" {
					t.Errorf("commits.format: got %q", c.Commits.Format)
				}
				if len(c.Tickets.Prefixes) != 2 {
					t.Errorf("tickets.prefixes: got %d, want 2", len(c.Tickets.Prefixes))
				}
				if !c.Tickets.Required {
					t.Error("tickets.required: want true")
				}
				if c.Tickets.URL != "https://tickets.example.com" {
					t.Errorf("tickets.url: got %q", c.Tickets.URL)
				}
			},
		},
		{
			file: "validation-disabled.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.RequireCommitTypes() {
					t.Error("validation.require_commit_types: want false")
				}
				if c.Changelog.Mode != "full" {
					t.Errorf("changelog.mode: got %q", c.Changelog.Mode)
				}
			},
		},
		{
			file: "guardrails-allow-regression.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Validation.AllowVersionRegression {
					t.Error("validation.allow_version_regression: want true")
				}
				if !c.Version.TagPrefixV {
					t.Error("version.tag_prefix_v: want true")
				}
				if !c.Version.Components.HotfixCounter.Enabled {
					t.Error("version.components.hotfix_counter.enabled: want true")
				}
			},
		},
		{
			file: "semver.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Version.TagPrefixV {
					t.Error("version.tag_prefix_v: want true")
				}
				if c.Version.Components.Epoch.Enabled {
					t.Error("version.components.epoch.enabled: want false")
				}
				if !c.Version.Components.Major.Enabled {
					t.Error("version.components.major.enabled: want true")
				}
			},
		},
		{
			file: "custom-branches.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Branches.TagOn != "dev" {
					t.Errorf("branches.tag_on: got %q", c.Branches.TagOn)
				}
				if len(c.Branches.HotfixTargets) != 2 {
					t.Errorf("branches.hotfix_targets: got %d, want 2", len(c.Branches.HotfixTargets))
				}
			},
		},
		{
			file: "custom-types.yml",
			check: func(t *testing.T, c *config.Config) {
				if len(c.CommitTypeOverrides) != 3 {
					t.Errorf("commit_type_overrides: got %d entries, want 3", len(c.CommitTypeOverrides))
				}
				if c.CommitTypeOverrides["docs"].Bump != "none" {
					t.Errorf("commit_type_overrides.docs.bump: got %q", c.CommitTypeOverrides["docs"].Bump)
				}
				if c.CommitTypeOverrides["infra"].Bump != "minor" {
					t.Errorf("commit_type_overrides.infra.bump: got %q", c.CommitTypeOverrides["infra"].Bump)
				}
			},
		},
		{
			file: "multi-keyword.yml",
			check: func(t *testing.T, c *config.Config) {
				kws := c.HotfixKeywords()
				if len(kws) != 3 {
					t.Errorf("hotfix.keyword patterns: got %d, want 3", len(kws))
				}
			},
		},
		{
			file: "no-timestamp.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Version.Components.Timestamp.Enabled {
					t.Error("version.components.timestamp.enabled: want false")
				}
				if !c.Version.Components.Epoch.Enabled {
					t.Error("version.components.epoch.enabled: want true")
				}
			},
		},
		{
			file: "with-timestamp.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Version.Components.Timestamp.Enabled {
					t.Error("version.components.timestamp.enabled: want true")
				}
				if c.Version.Components.Timestamp.Timezone != "UTC" {
					t.Errorf("timestamp.timezone: got %q", c.Version.Components.Timestamp.Timezone)
				}
			},
		},
		{
			file: "with-v-prefix.yml",
			check: func(t *testing.T, c *config.Config) {
				if !c.Version.TagPrefixV {
					t.Error("version.tag_prefix_v: want true")
				}
				if c.Version.Components.Timestamp.Enabled {
					t.Error("version.components.timestamp.enabled: want false")
				}
			},
		},
		{
			file: "tag-on-equals-hotfix-target.yml",
			check: func(t *testing.T, c *config.Config) {
				if c.Branches.TagOn != "main" {
					t.Errorf("branches.tag_on: got %q", c.Branches.TagOn)
				}
				if len(c.Branches.HotfixTargets) != 1 || c.Branches.HotfixTargets[0] != "main" {
					t.Errorf("branches.hotfix_targets: got %v", c.Branches.HotfixTargets)
				}
				kws := c.HotfixKeywords()
				if len(kws) != 3 {
					t.Errorf("hotfix keywords: got %d, want 3", len(kws))
				}
			},
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.file, func(t *testing.T) {
			path := fixtureDir + "/" + tc.file
			c, err := config.Load(path)
			if err != nil {
				t.Fatalf("Load(%q): %v", tc.file, err)
			}
			tc.check(t, c)
		})
	}
}

// TestLoadMalformed verifies that a malformed YAML returns an error.
func TestLoadMalformed(t *testing.T) {
	_, err := config.Load("testdata/malformed.yml")
	if err == nil {
		t.Fatal("expected error for malformed YAML, got nil")
	}
}

// TestLoadFailsFastOnInvalidHotfixKeyword verifies that Load surfaces an
// invalid regex pattern in hotfix.keyword as a config error rather than
// silently degrading at runtime. Ticket 083 explicitly requires fail-fast.
func TestLoadFailsFastOnInvalidHotfixKeyword(t *testing.T) {
	_, err := config.Load("testdata/invalid-hotfix-keyword.yml")
	if err == nil {
		t.Fatal("expected error for invalid hotfix.keyword regex, got nil")
	}
	if !strings.Contains(err.Error(), "hotfix.keyword") {
		t.Errorf("error should mention 'hotfix.keyword', got: %v", err)
	}
	if !strings.Contains(err.Error(), "hotfix(*") {
		t.Errorf("error should name the offending pattern 'hotfix(*', got: %v", err)
	}
}

// TestDefaultsSnapshot verifies that Defaults() on a minimal config produces expected values.
func TestDefaultsSnapshot(t *testing.T) {
	c, err := config.Load(fixtureDir + "/minimal.yml")
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	// Commits
	if c.Commits.Format != "ticket" {
		t.Errorf("commits.format: got %q", c.Commits.Format)
	}
	// Changelog
	if c.Changelog.Mode != "last_commit" {
		t.Errorf("changelog.mode: got %q", c.Changelog.Mode)
	}
	if c.Changelog.File != "CHANGELOG.md" {
		t.Errorf("changelog.file: got %q", c.Changelog.File)
	}
	if c.Changelog.Title != "Changelog" {
		t.Errorf("changelog.title: got %q", c.Changelog.Title)
	}
	if !c.Changelog.IncludeCommitLink {
		t.Error("changelog.include_commit_link: want true")
	}
	if !c.Changelog.IncludeTicketLink {
		t.Error("changelog.include_ticket_link: want true")
	}
	if !c.Changelog.IncludeAuthor {
		t.Error("changelog.include_author: want true")
	}
	// Validation
	if !c.RequireCommitTypes() {
		t.Error("validation.require_commit_types default: want true")
	}
	if c.Validation.HotfixTitleRequired != "error" {
		t.Errorf("validation.hotfix_title_required: got %q", c.Validation.HotfixTitleRequired)
	}
	// Branches
	if c.Branches.TagOn != "development" {
		t.Errorf("branches.tag_on: got %q", c.Branches.TagOn)
	}
	if len(c.Branches.HotfixTargets) != 2 {
		t.Errorf("branches.hotfix_targets: got %d, want 2", len(c.Branches.HotfixTargets))
	}
	// Version defaults — major + patch enabled, epoch + timestamp + hotfix_counter off
	if !c.Version.Components.Major.Enabled {
		t.Error("version.components.major.enabled default: want true")
	}
	if !c.Version.Components.Patch.Enabled {
		t.Error("version.components.patch.enabled default: want true")
	}
	if c.Version.Components.Epoch.Enabled {
		t.Error("version.components.epoch.enabled default: want false")
	}
	if !c.Version.Components.HotfixCounter.Enabled {
		t.Error("version.components.hotfix_counter.enabled default: want true")
	}
	if c.Version.Components.Timestamp.Enabled {
		t.Error("version.components.timestamp.enabled default: want false")
	}
	// Hotfix keywords
	kws := c.HotfixKeywords()
	if len(kws) != 3 {
		t.Errorf("default hotfix keywords: got %d, want 3", len(kws))
	}
	// Validation ignore_patterns
	if len(c.Validation.IgnorePatterns) != 6 {
		t.Errorf("validation.ignore_patterns: got %d, want 6", len(c.Validation.IgnorePatterns))
	}
}
