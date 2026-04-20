// Package changelog implements the three changelog generators that were
// previously bash scripts: generate-changelog-per-folder,
// generate-changelog-last-commit, and update-changelog.
//
// Pure functions (parsing + rendering) are separated from I/O functions
// (file reads/writes, git operations) so the rendering logic can be tested
// without file system side effects.
package changelog

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Commit is the I/O unit passed between generators.
// SHA is the full 40-char hash; Subject is the one-line commit message.
type Commit struct {
	SHA     string
	Author  string
	Subject string
}

// ParseRawCommits parses the output of:
//
//	git log <range> --no-merges --pretty=format:"%H|%an|%s"
//
// into a []Commit. Empty lines are skipped.
func ParseRawCommits(raw string) []Commit {
	var out []Commit
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 3)
		if len(parts) != 3 {
			continue
		}
		out = append(out, Commit{
			SHA:     parts[0],
			Author:  parts[1],
			Subject: parts[2],
		})
	}
	return out
}

// FilterIgnored removes commits whose Subject matches any of the ignore
// patterns (anchored at the start of the subject, same as bash awk).
func FilterIgnored(commits []Commit, patterns []string) ([]Commit, error) {
	if len(patterns) == 0 {
		return commits, nil
	}
	combined := strings.Join(patterns, "|")
	re, err := regexp.Compile(combined)
	if err != nil {
		return nil, fmt.Errorf("changelog.FilterIgnored compile %q: %w", combined, err)
	}
	out := commits[:0:len(commits)]
	for _, c := range commits {
		if !re.MatchString(c.Subject) {
			out = append(out, c)
		}
	}
	return out, nil
}

// ShortHash returns the 7-char short hash via git rev-parse (shell-out, same
// as bash `git log -1 <sha> --pretty=format:"%h"`).
func ShortHash(sha string) (string, error) {
	out, err := exec.Command("git", "log", "-1", sha, "--pretty=format:%h").Output()
	if err != nil {
		return "", fmt.Errorf("changelog.ShortHash %s: %w", sha, err)
	}
	return strings.TrimSpace(string(out)), nil
}

// ExtractScope returns the conventional-commit scope from a subject like
// "feat(auth): add login" → "auth". Returns "" when no scope is found.
func ExtractScope(subject string) string {
	// Pattern: type(scope): message
	re := regexp.MustCompile(`^[a-z]+\(([^)]+)\):`)
	m := re.FindStringSubmatch(subject)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// ExtractType returns the commit type from a conventional commit subject.
// "feat(auth): add login" → "feat". Returns "" for non-conventional.
func ExtractType(subject string) string {
	re := regexp.MustCompile(`^([a-z]+)[\(:]`)
	m := re.FindStringSubmatch(subject)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// CleanSubject strips the "type(scope): " or "type: " prefix from a
// conventional commit subject, returning only the description.
func CleanSubject(subject string) string {
	// "feat(scope): msg" → "msg"
	re := regexp.MustCompile(`^[a-z]+\([^)]*\):\s*`)
	clean := re.ReplaceAllString(subject, "")
	if clean != subject {
		return clean
	}
	// "feat: msg" → "msg"
	re2 := regexp.MustCompile(`^[a-z]+:\s*`)
	return re2.ReplaceAllString(subject, "")
}

// EmojiForType returns the emoji configured for a commit type, or "".
func EmojiForType(cfg *config.Config, commitType string) string {
	for _, ct := range cfg.CommitTypes {
		if ct.Name == commitType {
			return ct.Emoji
		}
	}
	return ""
}

// FormatDate returns today's date in YYYY-MM-DD, respecting the timezone from
// config (same as bash `export TZ=...; date +%Y-%m-%d`).
func FormatDate(timezone string) string {
	if timezone == "" {
		timezone = "UTC"
	}
	loc, err := time.LoadLocation(timezone)
	if err != nil {
		loc = time.UTC
	}
	return time.Now().In(loc).Format("2006-01-02")
}

// BuildPerFolderEntry builds the markdown bullet for a per-folder CHANGELOG.
// Format matches bash generate-changelog-per-folder.sh exactly:
//
//   - [emoji ]**type**: clean_msg
//     _Author_
//     [Commit: shortHash](commitURL/sha)  ← only when commitURL != ""
func BuildPerFolderEntry(c Commit, cfg *config.Config) (string, error) {
	commitType := ExtractType(c.Subject)
	cleanMsg := CleanSubject(c.Subject)

	emojiPrefix := ""
	if cfg.Changelog.UseEmojis {
		emoji := EmojiForType(cfg, commitType)
		if emoji != "" && emoji != "null" {
			emojiPrefix = emoji + " "
		}
	}

	entry := fmt.Sprintf("- %s**%s**: %s\n  _%s_", emojiPrefix, commitType, cleanMsg, c.Author)

	if cfg.Changelog.CommitURL != "" {
		short, err := ShortHash(c.SHA)
		if err != nil {
			return "", err
		}
		entry += fmt.Sprintf("\n  [Commit: %s](%s/%s)", short, cfg.Changelog.CommitURL, c.SHA)
	}

	return entry, nil
}

// BuildLastCommitEntry builds the markdown lines for a root CHANGELOG entry.
// Matches bash generate-changelog-last-commit.sh line-by-line.
func BuildLastCommitEntry(c Commit, cfg *config.Config) ([]string, error) {
	var lines []string

	ticketID := ""
	if len(cfg.Tickets.Prefixes) > 0 {
		pattern := strings.Join(cfg.Tickets.Prefixes, "|")
		re := regexp.MustCompile(fmt.Sprintf(`(%s)-[0-9]+`, pattern))
		m := re.FindString(c.Subject)
		ticketID = m
	}

	emojiPrefix := ""
	if cfg.Changelog.UseEmojis {
		commitType := ExtractType(c.Subject)
		emoji := EmojiForType(cfg, commitType)
		if emoji != "" && emoji != "null" {
			emojiPrefix = emoji + " "
		}
	}

	if ticketID != "" {
		// bash: echo "- ${EMOJI_PREFIX}**${TICKET_ID}** - ${commit_msg#*- }"
		afterDash := c.Subject
		if idx := strings.Index(c.Subject, " - "); idx >= 0 {
			afterDash = c.Subject[idx+3:]
		}
		lines = append(lines, fmt.Sprintf("- %s**%s** - %s", emojiPrefix, ticketID, afterDash))
	} else {
		lines = append(lines, fmt.Sprintf("- %s%s", emojiPrefix, c.Subject))
	}

	if cfg.Changelog.IncludeAuthor {
		lines = append(lines, fmt.Sprintf("  - _%s_", c.Author))
	}

	if cfg.Changelog.IncludeTicketLink && cfg.Tickets.URL != "" && ticketID != "" {
		label := cfg.Changelog.TicketLinkLabel
		if label == "" {
			label = "View ticket"
		}
		lines = append(lines, fmt.Sprintf("  - [%s](%s/%s)", label, cfg.Tickets.URL, ticketID))
	}

	if cfg.Changelog.IncludeCommitLink && cfg.Changelog.CommitURL != "" {
		short, err := ShortHash(c.SHA)
		if err != nil {
			return nil, err
		}
		lines = append(lines, fmt.Sprintf("  - [Commit: %s](%s/%s)", short, cfg.Changelog.CommitURL, c.SHA))
	}

	return lines, nil
}

// ReadLines reads a file and returns non-empty trimmed lines. Returns nil when
// the file does not exist (not an error — callers use nil as "no entries").
func ReadLines(path string) ([]string, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("changelog.ReadLines %s: %w", path, err)
	}
	defer func() { _ = f.Close() }()

	var lines []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if l := strings.TrimSpace(sc.Text()); l != "" {
			lines = append(lines, l)
		}
	}
	return lines, sc.Err()
}

// WriteLines atomically writes lines to path (one per line, trailing newline).
func WriteLines(path string, lines []string) error {
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

// AppendToFile appends content to path, creating it if necessary.
func AppendToFile(path, content string) error {
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("changelog.AppendToFile %s: %w", path, err)
	}
	_, werr := f.WriteString(content)
	if cerr := f.Close(); cerr != nil && werr == nil {
		return cerr
	}
	return werr
}

// EnsureParentDir creates the parent directory of path if it doesn't exist.
func EnsureParentDir(path string) error {
	return os.MkdirAll(filepath.Dir(path), 0o755)
}
