package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/changelog"
)

func newUpdateChangelogCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "update-changelog",
		Short: "Stage, commit, and push CHANGELOG and version files",
		RunE:  runUpdateChangelog,
	}
}

func runUpdateChangelog(cmd *cobra.Command, _ []string) error {
	const op = "update-changelog"

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

	if scenario != "development_release" && scenario != "hotfix" {
		return nil
	}

	nextVersionPath := "/tmp/next_version.txt"
	if _, err := os.Stat(nextVersionPath); os.IsNotExist(err) {
		return nil // nothing to do
	}

	nextVersion := readStateStr("/tmp/next_version.txt")
	bumpType := readStateStr("/tmp/bump_type.txt")

	repoPath, _ := os.Getwd()
	// Changelog file from config (default CHANGELOG.md)
	changelogFile := "CHANGELOG.md"
	// Try to load from config but don't fail if config missing
	if _, err := os.Stat("/tmp/.versioning-merged.yml"); err == nil {
		if cfg, err2 := loadConfigSafe(); err2 == nil && cfg.Changelog.File != "" {
			changelogFile = cfg.Changelog.File
		}
	}

	opts := changelog.UpdateOptions{
		ChangelogFile:            changelogFile,
		VersionFilesModifiedPath: "/tmp/version_files_modified.txt",
		PerFolderChangelogsPath:  "/tmp/per_folder_changelogs.txt",
		NextVersion:              nextVersion,
		BumpType:                 bumpType,
		VersioningBranch:         os.Getenv("VERSIONING_BRANCH"),
		VersioningTargetBranch:   os.Getenv("VERSIONING_TARGET_BRANCH"),
		PRID:                     os.Getenv("VERSIONING_PR_ID"),
		FlagPath:                 "/tmp/changelog_committed.flag",
		RepoPath:                 repoPath,
	}

	if err := changelog.CommitAndFlag(opts); err != nil {
		return fmt.Errorf("%s: %w", op, err)
	}
	return nil
}

func readStateStr(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}
