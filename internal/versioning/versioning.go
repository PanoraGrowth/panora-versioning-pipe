// Package versioning implements semver bump calculation for the panora pipe.
// All functions are pure (no I/O) — the cmd layer owns file reads/writes.
package versioning

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/Masterminds/semver/v3"
)

// BumpType is the strength of a version bump.
type BumpType string

const (
	BumpNone  BumpType = "none"
	BumpPatch BumpType = "patch"
	BumpMinor BumpType = "minor"
	BumpMajor BumpType = "major"
)

// CommitType mirrors the catalog entry from commit-types.yml / merged config.
type CommitType struct {
	Name string   `yaml:"name"`
	Bump BumpType `yaml:"bump"`
}

// BumpConfig holds the commit-type catalog used for bump detection.
type BumpConfig struct {
	CommitTypes []CommitType
}

// VersionConfig holds version component settings from the merged YAML.
type VersionConfig struct {
	EpochEnabled         bool
	EpochInitial         int
	MajorEnabled         bool
	MajorInitial         int
	PatchEnabled         bool
	PatchInitial         int
	HotfixCounterEnabled bool
	HotfixCounterInitial int
	TagPrefixV           bool
}

// Commit is the caller's view of a git commit — Subject + Body.
type Commit struct {
	Subject string
	Body    string
}

// breakingRe matches `feat!:`, `fix!:`, etc. — the `!` breaking-change marker.
var breakingRe = regexp.MustCompile(`^[a-z]+(\(.+\))?!:`)

// isBreaking returns true when the commit signals a breaking change via `!`
// suffix or the "BREAKING CHANGE:" footer in the body.
func isBreaking(c Commit) bool {
	if breakingRe.MatchString(c.Subject) {
		return true
	}
	return strings.Contains(c.Body, "BREAKING CHANGE:")
}

// commitPrefix extracts the type prefix from a conventional commit subject
// (e.g. "feat(api): add thing" → "feat"). Returns "" for non-conventional.
func commitPrefix(subject string) string {
	re := regexp.MustCompile(`^([a-z]+)(\(.+\))?!?:\s`)
	m := re.FindStringSubmatch(subject)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// DetermineBump walks commits and returns the highest bump type found.
// Breaking changes (! or BREAKING CHANGE:) always produce BumpMajor.
// Early-return on major.
func DetermineBump(commits []Commit, cfg BumpConfig) BumpType {
	prefixBump := make(map[string]BumpType, len(cfg.CommitTypes))
	for _, ct := range cfg.CommitTypes {
		prefixBump[ct.Name] = ct.Bump
	}

	best := BumpNone
	for _, c := range commits {
		if isBreaking(c) {
			return BumpMajor
		}
		prefix := commitPrefix(c.Subject)
		if bump, ok := prefixBump[prefix]; ok {
			if bumpRank(bump) > bumpRank(best) {
				best = bump
			}
			if best == BumpMajor {
				return BumpMajor
			}
		}
	}
	return best
}

func bumpRank(b BumpType) int {
	switch b {
	case BumpMajor:
		return 3
	case BumpMinor:
		return 2
	case BumpPatch:
		return 1
	default:
		return 0
	}
}

// LatestTagFilter builds the regexp that selects tags inside the
// epoch.initial + major.initial namespace (ticket 055 / 059 logic).
// Mirrors bash build_initial_prefix_regex exactly:
//   - Epoch disabled: anchor on major.initial only when major.initial > 0.
//   - Epoch enabled:  anchor on epoch.initial.major.initial only when at least one > 0.
//   - Otherwise:      prefix-only match (all tags in the right prefix).
func LatestTagFilter(cfg VersionConfig) *regexp.Regexp {
	prefix := ""
	if cfg.TagPrefixV {
		prefix = "v"
	}

	var anchor string
	if cfg.EpochEnabled {
		if cfg.EpochInitial > 0 || cfg.MajorInitial > 0 {
			anchor = fmt.Sprintf(`%d\.%d\.`, cfg.EpochInitial, cfg.MajorInitial)
		}
	} else {
		if cfg.MajorInitial > 0 {
			anchor = fmt.Sprintf(`%d\.`, cfg.MajorInitial)
		}
	}

	return regexp.MustCompile(fmt.Sprintf(`^%s%s`, prefix, anchor))
}

// NextVersion computes the next version string given the latest tag (which may
// be empty for a cold start) and the bump type. Returns an error if the latest
// tag cannot be parsed as semver.
func NextVersion(latestTag string, bump BumpType, cfg VersionConfig) (string, error) {
	prefix := ""
	if cfg.TagPrefixV {
		prefix = "v"
	}

	var base *semver.Version

	if latestTag == "" {
		raw := fmt.Sprintf("%d.%d.%d", cfg.MajorInitial, cfg.PatchInitial, 0)
		v, err := semver.NewVersion(raw)
		if err != nil {
			return "", fmt.Errorf("versioning.NextVersion cold-start: %w", err)
		}
		base = v
	} else {
		tagToParse := strings.TrimPrefix(latestTag, "v")
		v, err := semver.NewVersion(tagToParse)
		if err != nil {
			return "", fmt.Errorf("versioning.NextVersion parse %q: %w", latestTag, err)
		}
		base = v
	}

	var next semver.Version
	switch bump {
	case BumpMajor:
		next = base.IncMajor()
	case BumpMinor:
		next = base.IncMinor()
	case BumpPatch:
		next = base.IncPatch()
	case BumpNone:
		return prefix + base.Original(), nil
	default:
		return "", fmt.Errorf("versioning.NextVersion: unknown bump %q", bump)
	}

	return prefix + next.String(), nil
}
