// Package changelog implements per-folder and flat changelog generation,
// and the staging+commit step for the versioning pipe.
//
// Pure functions (no I/O) are in this file.
// I/O-heavy functions are in per_folder.go, last_commit.go, update.go.
package changelog

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// RawCommit holds the raw log fields as emitted by git log.
type RawCommit struct {
	SHA     string
	Author  string
	Subject string
}

// extractScope parses the conventional commit scope from a subject line.
// "feat(api): ..." → "api". Returns "" for unscoped commits.
func extractScope(subject string) string {
	re := regexp.MustCompile(`^[a-z]+\(([^)]+)\):`)
	m := re.FindStringSubmatch(subject)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// extractType parses the commit type from a subject line.
// "feat(api): ..." → "feat", "fix: ..." → "fix".
func extractType(subject string) string {
	re := regexp.MustCompile(`^([a-z]+)[\(:]`)
	m := re.FindStringSubmatch(subject)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// cleanMessage strips the type/scope prefix from a commit subject.
// "feat(api): add endpoint" → "add endpoint"
func cleanMessage(subject string) string {
	re := regexp.MustCompile(`^[a-z]+(\([^)]*\))?: `)
	cleaned := re.ReplaceAllString(subject, "")
	return cleaned
}

// shortSHA returns the 7-char short hash for a full SHA by calling `git log`.
func shortSHA(sha string) string {
	out, err := exec.Command("git", "log", "-1", sha, "--pretty=format:%h").Output()
	if err != nil || len(out) == 0 {
		if len(sha) >= 7 {
			return sha[:7]
		}
		return sha
	}
	return strings.TrimSpace(string(out))
}

// commitTypeEmoji returns the emoji for a commit type from config, or "".
func commitTypeEmoji(cfg *config.Config, commitType string) string {
	for _, ct := range cfg.CommitTypes {
		if ct.Name == commitType {
			return ct.Emoji
		}
	}
	return ""
}

// buildEntryLinePerFolder builds the per-folder format:
// "- [emoji ]**type**: message\n  _author_\n  [Commit: short](url/sha)"
func buildEntryLinePerFolder(cfg *config.Config, commit RawCommit) string {
	commitType := extractType(commit.Subject)
	clean := cleanMessage(commit.Subject)

	emojiPrefix := ""
	if cfg.Changelog.UseEmojis {
		emoji := commitTypeEmoji(cfg, commitType)
		if emoji != "" && emoji != "null" {
			emojiPrefix = emoji + " "
		}
	}

	entry := fmt.Sprintf("- %s**%s**: %s\n  _%s_", emojiPrefix, commitType, clean, commit.Author)

	if cfg.Changelog.CommitURL != "" {
		short := shortSHA(commit.SHA)
		entry += fmt.Sprintf("\n  [Commit: %s](%s/%s)", short, cfg.Changelog.CommitURL, commit.SHA)
	}

	return entry
}

// buildFlatEntryLines builds the multi-line block for one commit in flat mode.
// Matches bash generate-changelog-last-commit.sh output format exactly.
func buildFlatEntryLines(cfg *config.Config, commit RawCommit) string {
	short := shortSHA(commit.SHA)
	subject := commit.Subject

	// Extract ticket ID if prefixes configured
	ticketID := ""
	if len(cfg.Tickets.Prefixes) > 0 {
		pattern := cfg.TicketPrefixesPattern()
		if pattern != "" {
			re := regexp.MustCompile(fmt.Sprintf(`(%s)-[0-9]+`, pattern))
			ticketID = re.FindString(subject)
		}
	}

	// Build emoji prefix
	emojiPrefix := ""
	if cfg.Changelog.UseEmojis {
		ctype := extractType(subject)
		emoji := commitTypeEmoji(cfg, ctype)
		if emoji != "" && emoji != "null" {
			emojiPrefix = emoji + " "
		}
	}

	var line string
	if ticketID != "" {
		// "- **TICKET-123** - rest of message"
		rest := subject
		idx := strings.Index(subject, "- ")
		if idx >= 0 {
			rest = subject[idx+2:]
		}
		line = fmt.Sprintf("- %s**%s** - %s", emojiPrefix, ticketID, rest)
	} else {
		line = fmt.Sprintf("- %s%s", emojiPrefix, subject)
	}

	if cfg.Changelog.IncludeAuthor {
		line += fmt.Sprintf("\n  - _%s_", commit.Author)
	}

	if cfg.Changelog.IncludeTicketLink && cfg.Tickets.URL != "" && ticketID != "" {
		label := cfg.Changelog.TicketLinkLabel
		if label == "" {
			label = "View ticket"
		}
		line += fmt.Sprintf("\n  - [%s](%s/%s)", label, cfg.Tickets.URL, ticketID)
	}

	if cfg.Changelog.IncludeCommitLink && cfg.Changelog.CommitURL != "" {
		line += fmt.Sprintf("\n  - [Commit: %s](%s/%s)", short, cfg.Changelog.CommitURL, commit.SHA)
	}

	return line
}

// formatDate returns YYYY-MM-DD in the given timezone.
func formatDate(tz string) string {
	loc, err := time.LoadLocation(tz)
	if err != nil {
		loc = time.UTC
	}
	return time.Now().In(loc).Format("2006-01-02")
}

// buildVersionHeader builds the "## vX.Y.Z - YYYY-MM-DD" header line.
func buildVersionHeader(version, headerSuffix, date string) string {
	return fmt.Sprintf("## %s%s - %s", version, headerSuffix, date)
}
