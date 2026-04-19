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
