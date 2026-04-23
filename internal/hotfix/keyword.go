// Package hotfix provides the unified keyword matcher used by both PR title
// validation and post-merge scenario detection. Patterns are Go regex syntax
// (regexp stdlib). A literal string without regex metacharacters works as a
// substring match — patterns are NOT anchored, so "URGENT-PATCH" matches any
// subject that contains it.
package hotfix

import (
	"fmt"
	"regexp"
)

// Matcher holds the compiled regex patterns for hotfix keyword detection.
type Matcher struct {
	patterns []*regexp.Regexp
}

// NewMatcher compiles the given patterns into a Matcher. Empty patterns are
// skipped. If any pattern fails to compile, NewMatcher returns an error
// identifying the offending pattern — callers should fail fast at config load
// rather than discover the error at runtime.
func NewMatcher(patterns []string) (*Matcher, error) {
	compiled := make([]*regexp.Regexp, 0, len(patterns))
	for _, p := range patterns {
		if p == "" {
			continue
		}
		re, err := regexp.Compile(p)
		if err != nil {
			return nil, fmt.Errorf("hotfix.NewMatcher: invalid regex %q: %w", p, err)
		}
		compiled = append(compiled, re)
	}
	return &Matcher{patterns: compiled}, nil
}

// Matches reports whether subject matches any of the configured patterns.
// Returns false for an empty matcher or empty subject.
func (m *Matcher) Matches(subject string) bool {
	if m == nil || subject == "" {
		return false
	}
	for _, re := range m.patterns {
		if re.MatchString(subject) {
			return true
		}
	}
	return false
}
