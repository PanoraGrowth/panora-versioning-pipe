package validation

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Issue describes one commit validation violation.
type Issue struct {
	Commit string
	Reason string
}

func (i Issue) Error() string {
	return fmt.Sprintf("x %s — %s", i.Commit, i.Reason)
}

// ValidatePRTitle checks that the PR title follows the same format as
// conventional commits, or matches a hotfix keyword pattern.
//
// Skipped (returns nil) when:
//   - PR title is empty (Bitbucket, generic CI, push event)
//   - require_commit_types is false in config
//
// In squash merge, the PR title becomes the squash commit subject — the one
// that determines the version bump. Without validation, invalid titles can
// produce incorrect version bumps in production.
//
// Returns error with a detailed message when the title doesn't match.
func ValidatePRTitle(prTitle string, cfg *config.Config) error {
	if prTitle == "" {
		return nil
	}
	if !cfg.RequireCommitTypes() {
		return nil
	}

	fullPattern := buildFullPattern(cfg)
	if fullPattern.MatchString(prTitle) {
		return nil
	}

	if matchesHotfixKeyword(prTitle, cfg) {
		return nil
	}

	return &PRTitleError{
		Title: prTitle,
		Cfg:   cfg,
	}
}

// PRTitleError is returned when PR title validation fails.
type PRTitleError struct {
	Title string
	Cfg   *config.Config
}

func (e *PRTitleError) Error() string {
	types := e.Cfg.CommitTypeNames()
	typesStr := strings.Join(types, ", ")

	var buf strings.Builder
	buf.WriteString("\n==========================================\n")
	buf.WriteString("  ERROR: PR TITLE NOT WELL-FORMED\n")
	buf.WriteString("==========================================\n")
	fmt.Fprintf(&buf, "PR title: %q\n", e.Title)
	buf.WriteString("\n")
	buf.WriteString("The PR title must follow the same format as commits.\n")
	buf.WriteString("In squash merge, the PR title becomes the commit that determines the version bump.\n")
	buf.WriteString("\n")

	if e.Cfg.IsConventional() {
		buf.WriteString("Valid formats:\n")
		buf.WriteString("  - <type>(<scope>): <subject>   (e.g. \"feat(auth): add JWT support\")\n")
		buf.WriteString("  - <type>: <subject>             (e.g. \"fix: resolve token expiry\")\n")
	} else {
		prefixes := e.Cfg.TicketPrefixesPattern()
		if prefixes != "" {
			buf.WriteString("Valid formats:\n")
			example := strings.Split(prefixes, "|")[0]
			fmt.Fprintf(&buf, "  - %s-XXXX - <type>: <message>\n", example)
		} else {
			buf.WriteString("Valid formats:\n")
			buf.WriteString("  - <type>: <message>\n")
		}
	}

	buf.WriteString("  - Hotfix/ prefix                (e.g. \"Hotfix/urgent security patch\")\n")
	buf.WriteString("\n")
	if typesStr != "" {
		fmt.Fprintf(&buf, "Current allowed types: %s\n", typesStr)
		buf.WriteString("\n")
	}

	if e.Cfg.IsConventional() {
		buf.WriteString("Examples:\n")
		buf.WriteString("  - feat(cluster-ecs): add new ECS config\n")
		buf.WriteString("  - fix(alb): correct listener rules\n")
		buf.WriteString("  - chore: update dependencies\n")
	} else {
		buf.WriteString("Examples:\n")
		buf.WriteString("  - feat: add new feature\n")
		buf.WriteString("  - fix: resolve bug\n")
	}
	buf.WriteString("\n")

	return buf.String()
}

// matchesHotfixKeyword checks if the title matches any of the configured
// hotfix keywords. Keywords are shell glob patterns (e.g. "[Hh]otfix/*").
// For simplicity, we use case-sensitive exact string matching on the pattern
// after normalizing common hotfix prefixes.
func matchesHotfixKeyword(title string, cfg *config.Config) bool {
	if len(cfg.Hotfix.Keyword.Values) == 0 {
		return false
	}

	for _, kw := range cfg.Hotfix.Keyword.Values {
		if kw == "" {
			continue
		}
		if simpleGlobMatch(title, kw) {
			return true
		}
	}
	return false
}

// simpleGlobMatch does simple glob matching for * and ? wildcards.
// This mirrors the shell case pattern logic used in the bash validator.
func simpleGlobMatch(s, pattern string) bool {
	// No wildcards — exact match
	if !strings.ContainsAny(pattern, "*?") {
		return s == pattern
	}

	// * matches any sequence of characters (including empty)
	// ? matches exactly one character
	// Convert glob to regex for simplicity
	regexPattern := strings.NewReplacer(
		".", "\\.",
		"*", ".*",
		"?", ".",
		"[", "\\[",
		"]", "\\]",
		"(", "\\(",
		")", "\\)",
		"+", "\\+",
		"^", "\\^",
		"$", "\\$",
	).Replace(pattern)

	re := regexp.MustCompile("^" + regexPattern + "$")
	return re.MatchString(s)
}

// ValidateCommits checks commits against the rules in cfg and returns all
// violations. An empty slice means all commits are valid.
//
// Mirrors the logic in scripts/validation/validate-commits.sh:
//   - VALIDATION 1: ticket prefix (when require_ticket_prefix + has prefixes)
//   - VALIDATION 2: full format (when require_commit_types; scope driven by
//     changelog.mode: "full" = all commits, "last_commit" = last only)
func ValidateCommits(commits []string, cfg *config.Config) []Issue {
	if len(commits) == 0 {
		return nil
	}
	if !cfg.RequireCommitTypes() {
		return nil
	}

	fullPattern := buildFullPattern(cfg)

	if cfg.RequireCommitTypesForAll() {
		return validateAll(commits, fullPattern)
	}
	// last_commit mode: only the first element (newest) must be typed
	return validateLast(commits, fullPattern)
}

// FilterIgnored removes commits matching any of the ignore_patterns from the
// validated list. This replicates the grep -vE $IGNORE_PATTERN pipe in bash.
func FilterIgnored(commits []string, patterns []string) []string {
	if len(patterns) == 0 {
		return commits
	}
	combined := strings.Join(patterns, "|")
	re, err := regexp.Compile(combined)
	if err != nil {
		// Invalid pattern — skip filtering rather than crash
		return commits
	}
	out := commits[:0:len(commits)]
	for _, c := range commits {
		if !re.MatchString(c) {
			out = append(out, c)
		}
	}
	return out
}

// buildFullPattern builds the regex that a well-formed commit subject must match.
// Mirrors build_ticket_full_pattern in config-parser.sh.
func buildFullPattern(cfg *config.Config) *regexp.Regexp {
	types := cfg.CommitTypeNames()
	typeAlt := strings.Join(types, "|")
	if typeAlt == "" {
		typeAlt = "feat|fix|chore|docs|refactor|test|style|ci|build|perf|revert|breaking|feature|hotfix|security|infra|deploy|config|deps|migration|rollback|data|compliance|audit|regulatory|iac|release|wip|experiment"
	}

	var pattern string
	if cfg.IsConventional() {
		// ^(type1|type2|...)(scope)?: subject
		pattern = fmt.Sprintf(`^(%s)(\(.+\))?!?:`, typeAlt)
	} else {
		prefixes := cfg.TicketPrefixesPattern()
		if prefixes != "" {
			// ^(AM|TECH)-[0-9]+ - (type1|type2|...):
			pattern = fmt.Sprintf(`^(%s)-[0-9]+ - (%s):`, prefixes, typeAlt)
		} else {
			// No prefix: bare "type: msg" or "anything - type: msg"
			pattern = fmt.Sprintf(`^.* - (%s):|^(%s):`, typeAlt, typeAlt)
		}
	}
	return regexp.MustCompile(pattern)
}

func validateAll(commits []string, re *regexp.Regexp) []Issue {
	var issues []Issue
	for _, c := range commits {
		if !re.MatchString(c) {
			issues = append(issues, Issue{Commit: c, Reason: "commit type missing or invalid"})
		}
	}
	return issues
}

func validateLast(commits []string, re *regexp.Regexp) []Issue {
	last := commits[0] // newest-first order from git log
	if !re.MatchString(last) {
		return []Issue{{Commit: last, Reason: "last commit type missing or invalid"}}
	}
	return nil
}
