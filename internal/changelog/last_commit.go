package changelog

import (
	"fmt"
	"os"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

// GenerateLastCommit generates the root CHANGELOG.md entry.
//
// Reads commits filtered by ignore patterns, excludes commits already listed in
// /tmp/routed_commits.txt, and writes/appends to the configured CHANGELOG file.
//
// repoRoot is the git working directory (/workspace in container).
// nextVersion must be non-empty.
// baseRef is CHANGELOG_BASE_REF env (empty = all commits from HEAD).
// headerSuffix is "" for dev releases, " (Hotfix)" for hotfix.
func GenerateLastCommit(cfg *config.Config, repoRoot, nextVersion, baseRef, headerSuffix string) error {
	const op = "changelog.last-commit"

	log.Section("GENERATING CHANGELOG")
	log.Info(fmt.Sprintf("Mode: %s", cfg.Changelog.Mode))
	log.Info(fmt.Sprintf("Version: %s", nextVersion))
	fmt.Println()

	allCommits, err := getCommits(baseRef, cfg.Validation.IgnorePatterns)
	if err != nil {
		return fmt.Errorf("%s: get commits: %w", op, err)
	}

	if len(allCommits) == 0 {
		log.Info("No valid commits found for CHANGELOG")
		return nil
	}

	routedSHAs := loadRoutedCommits()
	if len(routedSHAs) > 0 {
		log.Info(fmt.Sprintf("Excluding %d commit(s) already routed to per-folder CHANGELOGs", len(routedSHAs)))
	}

	var toInclude []RawCommit

	if cfg.Changelog.Mode == "full" {
		for _, c := range allCommits {
			if !routedSHAs[c.SHA] {
				toInclude = append(toInclude, c)
			}
		}
	} else {
		// last_commit mode: only the most recent commit
		last := allCommits[0]
		if !routedSHAs[last.SHA] {
			toInclude = []RawCommit{last}
		}
	}

	if len(toInclude) == 0 {
		log.Info("All commits routed to per-folder CHANGELOGs — no root CHANGELOG entry needed")
		return nil
	}

	tz := cfg.Version.Components.Timestamp.Timezone
	if tz == "" {
		tz = "UTC"
	}
	date := formatDate(tz)
	header := buildVersionHeader(nextVersion, headerSuffix, date)

	var entryLines []string
	for _, commit := range toInclude {
		entryLines = append(entryLines, buildFlatEntryLines(cfg, commit))
	}
	entries := strings.Join(entryLines, "\n")
	changelogEntry := fmt.Sprintf("%s\n\n%s\n\n", header, entries)

	log.Info("CHANGELOG entry:")
	fmt.Println(changelogEntry)

	// Write/append to CHANGELOG file
	changelogFile := cfg.Changelog.File
	if changelogFile == "" {
		changelogFile = "CHANGELOG.md"
	}
	if !strings.HasPrefix(changelogFile, "/") {
		changelogFile = repoRoot + "/" + changelogFile
	}

	existing, readErr := os.ReadFile(changelogFile)
	if readErr != nil && !os.IsNotExist(readErr) {
		return fmt.Errorf("%s: read %s: %w", op, changelogFile, readErr)
	}

	if os.IsNotExist(readErr) || len(existing) == 0 {
		log.Info(fmt.Sprintf("Creating new %s", cfg.Changelog.File))
		title := cfg.Changelog.Title
		if title == "" {
			title = "Changelog"
		}
		content := fmt.Sprintf("# %s\n\n---\n\n%s", title, changelogEntry)
		if err := os.WriteFile(changelogFile, []byte(content), 0644); err != nil {
			return fmt.Errorf("%s: write %s: %w", op, changelogFile, err)
		}
	} else {
		log.Info(fmt.Sprintf("Updating existing %s (appending to end)", cfg.Changelog.File))
		newContent := append(existing, []byte(changelogEntry)...)
		if err := os.WriteFile(changelogFile, newContent, 0644); err != nil {
			return fmt.Errorf("%s: append %s: %w", op, changelogFile, err)
		}
	}

	log.Success(fmt.Sprintf("%s updated successfully (appended to end)", cfg.Changelog.File))
	log.Info("")
	log.Info("Note: New entries are added at the END of CHANGELOG")
	log.Info("This prevents merge conflicts with main/pre-production")

	return nil
}

// loadRoutedCommits reads /tmp/routed_commits.txt and returns a set of SHAs.
func loadRoutedCommits() map[string]bool {
	data, err := os.ReadFile("/tmp/routed_commits.txt")
	if err != nil || len(data) == 0 {
		return map[string]bool{}
	}
	result := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			result[line] = true
		}
	}
	return result
}
