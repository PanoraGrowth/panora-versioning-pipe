package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/changelog"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/state"
)

func newGenerateChangelogPerFolderCmd() *cobra.Command {
	return &cobra.Command{
		Use:          "generate-changelog-per-folder",
		Short:        "Generate per-folder CHANGELOG.md files from scoped commits",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			env, err := state.LoadEnv(scenarioEnvPath)
			if err != nil {
				return fmt.Errorf("generate-changelog-per-folder: load scenario: %w", err)
			}
			scenario := env["SCENARIO"]

			switch scenario {
			case "development_release", "hotfix":
			default:
				return nil
			}

			headerSuffix := ""
			if scenario == "hotfix" {
				headerSuffix = " (Hotfix)"
			}

			nextVersion, err := state.ReadLine(nextVersionPath)
			if err != nil {
				return fmt.Errorf("generate-changelog-per-folder: version file not found. Run calculate-version first")
			}

			cfg, err := config.Load(config.MergedConfigPath)
			if err != nil {
				return fmt.Errorf("generate-changelog-per-folder: %w", err)
			}

			baseRef := os.Getenv("CHANGELOG_BASE_REF")
			repoRoot, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("generate-changelog-per-folder: getwd: %w", err)
			}

			return changelog.GeneratePerFolder(cfg, repoRoot, nextVersion, baseRef, headerSuffix)
		},
	}
}
