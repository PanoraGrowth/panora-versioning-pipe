package changelog

import (
	"fmt"
	"os"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

// GenerateLastCommit implements generate-changelog-last-commit.sh.
//
// commits is the full list (filtered for ignore patterns) from the git range.
// routedSHAs are commits already written to per-folder CHANGELOGs.
// nextVersion, headerSuffix, date drive the version header.
// changelogFile is the absolute path to CHANGELOG.md.
func GenerateLastCommit(
	commits []Commit,
	routedSHAs []string,
	nextVersion string,
	headerSuffix string,
	date string,
	changelogFile string,
	cfg *config.Config,
) error {
	// Build routed set for O(1) lookup.
	routedSet := make(map[string]bool, len(routedSHAs))
	for _, sha := range routedSHAs {
		routedSet[sha] = true
	}

	if len(routedSHAs) > 0 {
		log.Info(fmt.Sprintf("Excluding %d commit(s) already routed to per-folder CHANGELOGs", len(routedSHAs)))
	}

	// Determine commits to include based on mode.
	var commitsToInclude []Commit
	if cfg.Changelog.Mode == "full" {
		for _, c := range commits {
			if !routedSet[c.SHA] {
				commitsToInclude = append(commitsToInclude, c)
			}
		}
	} else {
		// last_commit mode: only the last (first in newest-first order) commit from ALL commits.
		// If that commit was routed, nothing goes to root.
		if len(commits) == 0 {
			log.Info("No valid commits found for CHANGELOG")
			return nil
		}
		last := commits[0]
		if routedSet[last.SHA] {
			log.Info("All commits routed to per-folder CHANGELOGs — no root CHANGELOG entry needed")
			return nil
		}
		commitsToInclude = []Commit{last}
	}

	if len(commitsToInclude) == 0 {
		log.Info("No entries to write to root CHANGELOG")
		return nil
	}

	// Build entry lines.
	var entryLines []string
	for _, c := range commitsToInclude {
		lines, err := BuildLastCommitEntry(c, cfg)
		if err != nil {
			return fmt.Errorf("changelog.last-commit build entry: %w", err)
		}
		entryLines = append(entryLines, lines...)
	}

	entries := strings.Join(entryLines, "\n")

	// Compose the full section:
	// ## VERSION[suffix] - DATE\n\nENTRIES\n\n
	section := fmt.Sprintf("## %s%s - %s\n\n%s\n\n", nextVersion, headerSuffix, date, entries)

	log.Info("CHANGELOG entry:")
	fmt.Print(section)

	// Write to file.
	// bash uses echo for both new-file and append cases, which adds a trailing \n.
	// The section already ends with \n\n; echo adds one more → \n\n\n at end.
	if _, err := os.Stat(changelogFile); os.IsNotExist(err) {
		log.Info(fmt.Sprintf("Creating new %s", changelogFile))
		titleLine := cfg.Changelog.Title
		if titleLine == "" {
			titleLine = "Changelog"
		}
		// bash: echo "# Title\n\n---\n\n${ENTRY}" adds trailing \n
		content := fmt.Sprintf("# %s\n\n---\n\n%s\n", titleLine, section)
		if err := os.WriteFile(changelogFile, []byte(content), 0o644); err != nil {
			return fmt.Errorf("changelog.last-commit write new %s: %w", changelogFile, err)
		}
	} else {
		log.Info(fmt.Sprintf("Updating existing %s (appending to end)", changelogFile))
		// bash: echo "${ENTRY}" adds trailing \n
		if err := AppendToFile(changelogFile, section+"\n"); err != nil {
			return fmt.Errorf("changelog.last-commit append %s: %w", changelogFile, err)
		}
	}

	log.Success(fmt.Sprintf("%s updated successfully (appended to end)", changelogFile))
	return nil
}
