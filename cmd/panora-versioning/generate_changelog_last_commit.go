package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/changelog"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

func newGenerateChangelogLastCommitCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "generate-changelog-last-commit",
		Short: "Generate root CHANGELOG entry from last or all commits",
		RunE:  runGenerateChangelogLastCommit,
	}
}

func runGenerateChangelogLastCommit(cmd *cobra.Command, _ []string) error {
	const op = "generate-changelog-last-commit"

	// Load scenario
	scenario := os.Getenv("SCENARIO")
	if scenario == "" {
		data, err := os.ReadFile("/tmp/scenario.env")
		if err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				if strings.HasPrefix(line, "SCENARIO=") {
					scenario = strings.TrimPrefix(line, "SCENARIO=")
					scenario = strings.TrimSpace(scenario)
				}
			}
		}
	}

	switch scenario {
	case "development_release", "hotfix":
	default:
		return nil
	}

	headerSuffix := ""
	if scenario == "hotfix" {
		headerSuffix = " (Hotfix)"
	}

	log.Section("GENERATING CHANGELOG")

	cfg, err := config.Load(config.MergedConfigPath)
	if err != nil {
		return fmt.Errorf("%s: %w", op, err)
	}

	nextVersion, err := readStateTrimmed("/tmp/next_version.txt")
	if err != nil {
		return fmt.Errorf("%s: next_version.txt not found: %w", op, err)
	}

	log.Info(fmt.Sprintf("Mode: %s", cfg.Changelog.Mode))
	log.Info(fmt.Sprintf("Version: %s", nextVersion))
	fmt.Println()

	gitRange := buildGitRange(os.Getenv("CHANGELOG_BASE_REF"))
	rawCommits, err := gitLog(gitRange)
	if err != nil {
		return fmt.Errorf("%s git log: %w", op, err)
	}

	allCommits := changelog.ParseRawCommits(rawCommits)
	allCommits, err = changelog.FilterIgnored(allCommits, cfg.Validation.IgnorePatterns)
	if err != nil {
		return fmt.Errorf("%s filter: %w", op, err)
	}

	if len(allCommits) == 0 {
		log.Info("No valid commits found for CHANGELOG")
		return nil
	}

	// Load routed commits from per-folder generator
	routedLines, _ := changelog.ReadLines("/tmp/routed_commits.txt")

	date := changelog.FormatDate(cfg.Version.Components.Timestamp.Timezone)
	changelogFile := cfg.Changelog.File
	if changelogFile == "" {
		changelogFile = "CHANGELOG.md"
	}

	return changelog.GenerateLastCommit(allCommits, routedLines, nextVersion, headerSuffix, date, changelogFile, cfg)
}
