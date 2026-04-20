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

func newGenerateChangelogPerFolderCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "generate-changelog-per-folder",
		Short: "Generate per-folder changelogs from scoped conventional commits",
		RunE:  runGenerateChangelogPerFolder,
	}
}

func runGenerateChangelogPerFolder(cmd *cobra.Command, _ []string) error {
	const op = "generate-changelog-per-folder"

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
		return nil // exit 0 silently — not our scenario
	}

	headerSuffix := ""
	if scenario == "hotfix" {
		headerSuffix = " (Hotfix)"
	}

	cfg, err := config.Load(config.MergedConfigPath)
	if err != nil {
		return fmt.Errorf("%s: %w", op, err)
	}

	if !cfg.Changelog.PerFolder.Enabled {
		log.Info("Per-folder changelogs disabled — skipping")
		return nil
	}

	if !cfg.IsConventional() {
		log.Warn("Per-folder changelogs require commits.format: 'conventional'. Skipping.")
		return nil
	}

	log.Section("GENERATING PER-FOLDER CHANGELOGS")

	nextVersion, err := readStateTrimmed("/tmp/next_version.txt")
	if err != nil {
		return fmt.Errorf("%s: next_version.txt not found: %w", op, err)
	}

	// Get commits
	gitRange := buildGitRange(os.Getenv("CHANGELOG_BASE_REF"))
	rawCommits, err := gitLog(gitRange)
	if err != nil {
		return fmt.Errorf("%s git log: %w", op, err)
	}

	commits := changelog.ParseRawCommits(rawCommits)
	commits, err = changelog.FilterIgnored(commits, cfg.Validation.IgnorePatterns)
	if err != nil {
		return fmt.Errorf("%s filter: %w", op, err)
	}

	if len(commits) == 0 {
		log.Info("No commits to process for per-folder changelogs")
		return nil
	}

	// Respect mode: last_commit uses only the most recent commit
	if cfg.Changelog.Mode != "full" {
		commits = commits[:1]
	}

	repoRoot, _ := os.Getwd()
	date := changelog.FormatDate(cfg.Version.Components.Timestamp.Timezone)

	result, err := changelog.GeneratePerFolder(repoRoot, commits, nextVersion, headerSuffix, date, cfg)
	if err != nil {
		return fmt.Errorf("%s: %w", op, err)
	}

	// Write /tmp/routed_commits.txt
	routedPath := "/tmp/routed_commits.txt"
	if err := os.WriteFile(routedPath, []byte(strings.Join(result.RoutedSHAs, "\n")+"\n"), 0o644); err != nil {
		return fmt.Errorf("%s write routed: %w", op, err)
	}

	// Write /tmp/per_folder_changelogs.txt (append, dedup on read side)
	if len(result.UpdatedFiles) > 0 {
		perFolderPath := "/tmp/per_folder_changelogs.txt"
		f, err := os.OpenFile(perFolderPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
		if err != nil {
			return fmt.Errorf("%s write per_folder_changelogs: %w", op, err)
		}
		for _, path := range result.UpdatedFiles {
			if _, werr := fmt.Fprintln(f, path); werr != nil {
				_ = f.Close()
				return fmt.Errorf("%s write per_folder_changelogs line: %w", op, werr)
			}
		}
		if err := f.Close(); err != nil {
			return fmt.Errorf("%s close per_folder_changelogs: %w", op, err)
		}
	}

	// Summary
	if len(result.UpdatedFiles) > 0 {
		log.Success(fmt.Sprintf("Updated %d per-folder CHANGELOG(s)", len(result.UpdatedFiles)))
		for _, cl := range result.UpdatedFiles {
			log.Info(fmt.Sprintf("  - %s", cl))
		}
	} else {
		log.Info("No per-folder CHANGELOGs updated (no scoped commits matched)")
	}

	if len(result.RoutedSHAs) > 0 {
		log.Info(fmt.Sprintf("%d commit(s) routed to per-folder CHANGELOGs (excluded from root)", len(result.RoutedSHAs)))
	}

	return nil
}
