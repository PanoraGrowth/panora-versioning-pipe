package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

const (
	commitTypesPath = "../../config/defaults/commit-types.yml"
	defaultsPath    = "../../config/defaults/defaults.yml"
)

// TestLoadAndMergeNoUserConfig verifies fallback to defaults+commit-types only.
func TestLoadAndMergeNoUserConfig(t *testing.T) {
	// Pass a path that does not exist — LoadRaw returns empty map for missing files.
	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, "/nonexistent/.versioning.yml")
	if err != nil {
		t.Fatalf("LoadAndMerge (no user config): %v", err)
	}
	if len(cfg.CommitTypes) == 0 {
		t.Fatal("commit_types should be non-empty from commit-types.yml")
	}
	// Defaults should be applied.
	if cfg.Commits.Format != "ticket" {
		t.Errorf("commits.format default: got %q, want ticket", cfg.Commits.Format)
	}
	if cfg.Branches.TagOn != "development" {
		t.Errorf("branches.tag_on default: got %q", cfg.Branches.TagOn)
	}
}

// TestLoadAndMergeUserOverride verifies that user config overrides defaults.
func TestLoadAndMergeUserOverride(t *testing.T) {
	dir := t.TempDir()
	userCfg := filepath.Join(dir, ".versioning.yml")
	if err := os.WriteFile(userCfg, []byte(`commits:
  format: "conventional"
changelog:
  mode: "full"
`), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, userCfg)
	if err != nil {
		t.Fatalf("LoadAndMerge: %v", err)
	}
	if cfg.Commits.Format != "conventional" {
		t.Errorf("commits.format: got %q, want conventional", cfg.Commits.Format)
	}
	if cfg.Changelog.Mode != "full" {
		t.Errorf("changelog.mode: got %q, want full", cfg.Changelog.Mode)
	}
	// Other defaults preserved.
	if cfg.Branches.TagOn != "development" {
		t.Errorf("branches.tag_on: got %q, want development", cfg.Branches.TagOn)
	}
}

// TestLoadAndMergeCommitTypeOverrideUpdate verifies patching an existing type.
func TestLoadAndMergeCommitTypeOverrideUpdate(t *testing.T) {
	dir := t.TempDir()
	userCfg := filepath.Join(dir, ".versioning.yml")
	if err := os.WriteFile(userCfg, []byte(`commits:
  format: "conventional"
commit_type_overrides:
  feat:
    emoji: "⭐"
  docs:
    bump: "none"
`), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, userCfg)
	if err != nil {
		t.Fatalf("LoadAndMerge: %v", err)
	}

	var feat, docs *config.CommitType
	for i := range cfg.CommitTypes {
		switch cfg.CommitTypes[i].Name {
		case "feat":
			feat = &cfg.CommitTypes[i]
		case "docs":
			docs = &cfg.CommitTypes[i]
		}
	}
	if feat == nil {
		t.Fatal("feat commit type not found")
	}
	if feat.Emoji != "⭐" {
		t.Errorf("feat.emoji: got %q, want ⭐", feat.Emoji)
	}
	// feat.bump should be unchanged (minor from catalog).
	if feat.Bump != "minor" {
		t.Errorf("feat.bump: got %q, want minor", feat.Bump)
	}
	if docs == nil {
		t.Fatal("docs commit type not found")
	}
	if docs.Bump != "none" {
		t.Errorf("docs.bump: got %q, want none", docs.Bump)
	}
}

// TestLoadAndMergeCommitTypeOverrideAdd verifies appending a new type.
func TestLoadAndMergeCommitTypeOverrideAdd(t *testing.T) {
	dir := t.TempDir()
	userCfg := filepath.Join(dir, ".versioning.yml")
	if err := os.WriteFile(userCfg, []byte(`commits:
  format: "conventional"
commit_type_overrides:
  newtype:
    bump: "patch"
    emoji: "🆕"
`), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, userCfg)
	if err != nil {
		t.Fatalf("LoadAndMerge: %v", err)
	}

	var newtype *config.CommitType
	for i := range cfg.CommitTypes {
		if cfg.CommitTypes[i].Name == "newtype" {
			newtype = &cfg.CommitTypes[i]
			break
		}
	}
	if newtype == nil {
		t.Fatal("newtype was not appended to commit_types")
	}
	if newtype.Bump != "patch" {
		t.Errorf("newtype.bump: got %q, want patch", newtype.Bump)
	}
	if newtype.Emoji != "🆕" {
		t.Errorf("newtype.emoji: got %q, want 🆕", newtype.Emoji)
	}
}

// TestLoadAndMergeCustomTypesFixture uses the custom-types.yml fixture end-to-end.
func TestLoadAndMergeCustomTypesFixture(t *testing.T) {
	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, fixtureDir+"/custom-types.yml")
	if err != nil {
		t.Fatalf("LoadAndMerge custom-types: %v", err)
	}

	// feat emoji overridden to 🆕
	var feat, docs *config.CommitType
	for i := range cfg.CommitTypes {
		switch cfg.CommitTypes[i].Name {
		case "feat":
			feat = &cfg.CommitTypes[i]
		case "docs":
			docs = &cfg.CommitTypes[i]
		}
	}
	if feat == nil {
		t.Fatal("feat not found")
	}
	if feat.Emoji != "🆕" {
		t.Errorf("feat.emoji: got %q, want 🆕", feat.Emoji)
	}
	if docs == nil {
		t.Fatal("docs not found")
	}
	if docs.Bump != "none" {
		t.Errorf("docs.bump: got %q, want none", docs.Bump)
	}

	// infra bump overridden to minor (was patch in catalog).
	var infra *config.CommitType
	for i := range cfg.CommitTypes {
		if cfg.CommitTypes[i].Name == "infra" {
			infra = &cfg.CommitTypes[i]
			break
		}
	}
	if infra == nil {
		t.Fatal("infra not found")
	}
	if infra.Bump != "minor" {
		t.Errorf("infra.bump: got %q, want minor", infra.Bump)
	}
}

// TestApplyOverridesUpdateAndAdd verifies ApplyOverrides directly.
func TestApplyOverridesUpdateAndAdd(t *testing.T) {
	cfg := &config.Config{
		CommitTypes: []config.CommitType{
			{Name: "feat", Bump: "minor", Emoji: "🚀"},
			{Name: "fix", Bump: "patch", Emoji: "🐛"},
		},
		CommitTypeOverrides: map[string]config.CommitTypeOverride{
			"feat":    {Emoji: "⭐"},
			"newtype": {Bump: "patch", Emoji: "🆕"},
		},
	}

	if err := config.ApplyOverrides(cfg); err != nil {
		t.Fatalf("ApplyOverrides: %v", err)
	}

	if len(cfg.CommitTypes) != 3 {
		t.Fatalf("commit_types len: got %d, want 3", len(cfg.CommitTypes))
	}

	// feat emoji updated, bump preserved.
	if cfg.CommitTypes[0].Emoji != "⭐" {
		t.Errorf("feat.emoji: got %q", cfg.CommitTypes[0].Emoji)
	}
	if cfg.CommitTypes[0].Bump != "minor" {
		t.Errorf("feat.bump: got %q (should be unchanged)", cfg.CommitTypes[0].Bump)
	}

	// newtype appended.
	newtype := cfg.CommitTypes[2]
	if newtype.Name != "newtype" {
		t.Errorf("appended name: got %q, want newtype", newtype.Name)
	}
	if newtype.Bump != "patch" {
		t.Errorf("newtype.bump: got %q, want patch", newtype.Bump)
	}
}

// TestWriteMergedConfig verifies that WriteMergedConfig produces readable YAML.
func TestWriteMergedConfig(t *testing.T) {
	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, "/nonexistent/.versioning.yml")
	if err != nil {
		t.Fatalf("LoadAndMerge: %v", err)
	}

	out := filepath.Join(t.TempDir(), "merged.yml")
	if err := config.WriteMergedConfig(cfg, out); err != nil {
		t.Fatalf("WriteMergedConfig: %v", err)
	}

	// Round-trip: re-read and verify key fields.
	cfg2, err := config.Load(out)
	if err != nil {
		t.Fatalf("Load after write: %v", err)
	}
	if cfg2.Commits.Format != cfg.Commits.Format {
		t.Errorf("commits.format: got %q, want %q", cfg2.Commits.Format, cfg.Commits.Format)
	}
	if len(cfg2.CommitTypes) != len(cfg.CommitTypes) {
		t.Errorf("commit_types len: got %d, want %d", len(cfg2.CommitTypes), len(cfg.CommitTypes))
	}
}
