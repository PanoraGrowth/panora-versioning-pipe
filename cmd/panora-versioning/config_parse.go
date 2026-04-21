package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/gitops"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

func newConfigParseCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "config-parse",
		Short: "Parse and merge .versioning.yml into /tmp/.versioning-merged.yml",
		Long: `Reads commit-types.yml, defaults.yml, and the repository .versioning.yml
(if present), merges them in order, applies commit_type_overrides, and writes
the result to /tmp/.versioning-merged.yml.

Merge order: commit-types.yml * defaults.yml * .versioning.yml
Maps: later files override earlier. Arrays: later file replaces entirely.
commit_type_overrides: patch or append entries in commit_types by name.`,
		RunE: runConfigParse,
	}
}

func runConfigParse(cmd *cobra.Command, _ []string) error {
	commitTypesPath, err := config.ResolveBundledFile(config.CommitTypesFile)
	if err != nil {
		return fmt.Errorf("config-parse: %w", err)
	}
	defaultsPath, err := config.ResolveBundledFile(config.DefaultsFile)
	if err != nil {
		return fmt.Errorf("config-parse: %w", err)
	}

	// User config: .versioning.yml in the git repo root.
	// Absence is OK — falls back to defaults+commit-types only.
	repoRoot := repoRootOrCwd()
	userConfigPath := filepath.Join(repoRoot, ".versioning.yml")

	outputPath := config.MergedConfigPath
	if v := os.Getenv("PANORA_MERGED_CONFIG"); v != "" {
		outputPath = v
	}

	log.Section("PARSING CONFIG")
	log.Plain(fmt.Sprintf("commit-types: %s", commitTypesPath))
	log.Plain(fmt.Sprintf("defaults:     %s", defaultsPath))
	if _, statErr := os.Stat(userConfigPath); statErr == nil {
		log.Plain(fmt.Sprintf("user config:  %s", userConfigPath))
	} else {
		log.Plain("user config:  (absent — using defaults only)")
	}
	log.Plain(fmt.Sprintf("output:       %s", outputPath))

	cfg, err := config.LoadAndMerge(commitTypesPath, defaultsPath, userConfigPath)
	if err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "config-parse: %v\n", err)
		os.Exit(1)
	}

	if err := config.WriteMergedConfig(cfg, outputPath); err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "config-parse: %v\n", err)
		os.Exit(1)
	}

	log.Plain(fmt.Sprintf("merged config written (%d commit_types)", len(cfg.CommitTypes)))
	return nil
}

// repoRootOrCwd returns the git repository working-tree root, falling back to CWD.
func repoRootOrCwd() string {
	repo, err := gitops.Open(".")
	if err == nil {
		return repo.Path()
	}
	cwd, _ := os.Getwd()
	return cwd
}
