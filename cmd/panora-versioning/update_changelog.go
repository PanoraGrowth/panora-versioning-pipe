package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/changelog"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/state"
)

func newUpdateChangelogCmd() *cobra.Command {
	return &cobra.Command{
		Use:          "update-changelog",
		Short:        "Stage and commit changelog changes to the feature branch",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			env, err := state.LoadEnv(scenarioEnvPath)
			if err != nil {
				return fmt.Errorf("update-changelog: load scenario: %w", err)
			}
			scenario := env["SCENARIO"]

			if scenario != "development_release" && scenario != "hotfix" {
				return nil
			}

			// If no next_version.txt, nothing to do (matches bash behaviour)
			nextVersion, err := state.ReadLine(nextVersionPath)
			if err != nil {
				return nil
			}

			bumpType, err := state.ReadLine(bumpTypePath)
			if err != nil {
				bumpType = "patch"
			}

			cfg, err := config.Load(config.MergedConfigPath)
			if err != nil {
				return fmt.Errorf("update-changelog: %w", err)
			}

			branch := os.Getenv("VERSIONING_BRANCH")
			prID := os.Getenv("VERSIONING_PR_ID")
			targetBranch := os.Getenv("VERSIONING_TARGET_BRANCH")

			repoRoot, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("update-changelog: getwd: %w", err)
			}

			return changelog.CommitAndPush(cfg, repoRoot, nextVersion, bumpType, branch, prID, targetBranch)
		},
	}
}
