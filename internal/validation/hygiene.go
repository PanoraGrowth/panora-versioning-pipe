// Package validation implements commit-message validation and hygiene checks.
// Both validate-commits and check-commit-hygiene share this package;
// the commit parser (subject extraction) is the shared piece.
package validation

import (
	"fmt"
	"regexp"
	"strings"
)

// forbiddenPatterns are the GitHub Actions workflow-skip substrings that
// check-commit-hygiene detects. Detection is case-insensitive.
var forbiddenPatterns = []string{
	"[skip ci]",
	"[ci skip]",
	"[no ci]",
	"[skip actions]",
	"[actions skip]",
	"skip-checks: true",
}

const (
	exemptTrailer     = "X-Intentional-Skip-CI: true"
	pipeSubjectPrefix = `^chore\((release|hotfix)\):`
)

var pipeSubjectRe = regexp.MustCompile(pipeSubjectPrefix)

// HygieneIssue describes one forbidden-pattern finding.
type HygieneIssue struct {
	Label   string // human label for the message context (e.g. "commit message")
	Pattern string // the forbidden pattern found
}

func (h HygieneIssue) Error() string {
	return fmt.Sprintf("ERROR: %s contains forbidden substring: %s", h.Label, h.Pattern)
}

// CheckMessage checks a single commit message (subject + optional body).
// Returns nil when clean, or a slice of HygieneIssue when one or more
// forbidden patterns are found.
//
// Exemptions:
//   - Subject starts with chore(release): or chore(hotfix): → skip
//   - Body contains "X-Intentional-Skip-CI: true" on its own line → skip
func CheckMessage(msg, label string) []HygieneIssue {
	subject := subjectLine(msg)

	if pipeSubjectRe.MatchString(subject) {
		return nil
	}
	if containsExemptTrailer(msg) {
		return nil
	}

	var issues []HygieneIssue
	lower := strings.ToLower(msg)
	for _, p := range forbiddenPatterns {
		if strings.Contains(lower, strings.ToLower(p)) {
			issues = append(issues, HygieneIssue{Label: label, Pattern: p})
		}
	}
	return issues
}

// RemediationText is the block appended to stderr when any issue is found.
// Mirrors the bash print_remediation output verbatim (CONTRIBUTING.md reference
// and safe-alternative list are the two things bats asserts on).
const RemediationText = `
This commit or PR contains one or more GitHub Actions workflow-skip
substrings. GitHub Actions substring-matches these anywhere in the
message (case-insensitive) and will silently skip every workflow on
the resulting push. That is exactly how PR #34 landed on main without
a tag, a CHANGELOG, or a release image (see Finding #16).

See: CONTRIBUTING.md — "Commit Message Hygiene" section.

Safe alternatives when documenting the behavior:
  - skip-ci              (with a dash)
  - "skip ci"            (in quotes, without brackets)
  - the CI skip directive
  - the atomic push marker
  - the workflow-skip pragma

Intentional exemption: add the trailer
  X-Intentional-Skip-CI: true
on its own line in the commit body (or PR body). The exemption is
logged and reviewed — use it only when a skip is genuinely desired.`

// UsageText is the help text for check-commit-hygiene, mirroring the bash script.
const UsageText = `Usage:
  check-commit-hygiene -m "commit message"
  check-commit-hygiene -f path/to/commit-message-file

Lints a commit message for GitHub Actions workflow-skip substrings.
Exits 0 when clean, 1 when a forbidden substring is found, 2 on usage
or argument errors.

Exemption: include the trailer ` + "`X-Intentional-Skip-CI: true`" + ` on its
own line in the commit body to bypass the lint for that specific
message. Use sparingly — the trailer documents the intent.

Pipe-authored commits whose subject starts with ` + "`chore(release):`" + ` or
` + "`chore(hotfix):`" + ` are allowed to contain the skip markers. These are
the atomic-push circuit breakers that MUST keep working.`

func subjectLine(msg string) string {
	if idx := strings.IndexByte(msg, '\n'); idx >= 0 {
		return msg[:idx]
	}
	return msg
}

func containsExemptTrailer(msg string) bool {
	for _, line := range strings.Split(msg, "\n") {
		if line == exemptTrailer {
			return true
		}
	}
	return false
}
