// Package versioning implements semver bump calculation for the panora pipe.
// All functions are pure (no I/O) — the cmd layer owns file reads/writes.
package versioning

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// BumpType is the strength of a version bump.
type BumpType string

const (
	BumpNone   BumpType = "none"
	BumpPatch  BumpType = "patch"
	BumpMinor  BumpType = "minor"
	BumpMajor  BumpType = "major"
	BumpHotfix BumpType = "hotfix"
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

// versionSlots holds the parsed numeric components of a version tag.
// Slot positions follow the enabled component order: [epoch?][major][patch?][hotfix_counter?]
type versionSlots struct {
	epoch         int64
	major         int64
	patch         int64
	hotfixCounter int64
}

// parseVersionSlots parses a tag string into numeric slots given the schema config.
// It strips the v-prefix and splits on ".". Slot assignment follows the active
// component order: epoch (if enabled), major, patch (if enabled), hotfix_counter
// (if enabled and present).
func parseVersionSlots(tag string, cfg VersionConfig) (versionSlots, error) {
	stripped := strings.TrimPrefix(tag, "v")
	parts := strings.Split(stripped, ".")
	var vs versionSlots

	idx := 0
	parsePart := func(name string) (int64, error) {
		if idx >= len(parts) {
			return 0, nil
		}
		v, err := strconv.ParseInt(parts[idx], 10, 64)
		if err != nil {
			return 0, fmt.Errorf("versioning: parse slot %s in %q: %w", name, tag, err)
		}
		idx++
		return v, nil
	}

	var err error
	if cfg.EpochEnabled {
		if vs.epoch, err = parsePart("epoch"); err != nil {
			return vs, err
		}
	}
	if cfg.MajorEnabled {
		if vs.major, err = parsePart("major"); err != nil {
			return vs, err
		}
	}
	if cfg.PatchEnabled {
		if vs.patch, err = parsePart("patch"); err != nil {
			return vs, err
		}
	}
	if cfg.HotfixCounterEnabled {
		// Legacy 4-slot tags (e.g. v12.1.0.1 with a "base" slot) have more parts
		// than enabled components. Read hotfix_counter from the last slot in that case.
		if idx < len(parts) {
			enabledCount := idx + 1
			if len(parts) > enabledCount {
				// More parts than components — counter is in the last slot.
				last := len(parts) - 1
				v, err := strconv.ParseInt(parts[last], 10, 64)
				if err != nil {
					return vs, fmt.Errorf("versioning: parse slot hotfix_counter (last) in %q: %w", tag, err)
				}
				vs.hotfixCounter = v
			} else {
				if vs.hotfixCounter, err = parsePart("hotfix_counter"); err != nil {
					return vs, err
				}
			}
		}
	}
	return vs, nil
}

// buildVersionString constructs a dot-separated tag from slots, following only
// enabled components. Mirrors bash build_version_string / build_full_tag logic.
// hotfix_counter is appended only when it is enabled AND > 0.
func buildVersionString(vs versionSlots, cfg VersionConfig) string {
	var parts []string
	if cfg.EpochEnabled {
		parts = append(parts, strconv.FormatInt(vs.epoch, 10))
	}
	if cfg.MajorEnabled {
		parts = append(parts, strconv.FormatInt(vs.major, 10))
	}
	if cfg.PatchEnabled {
		parts = append(parts, strconv.FormatInt(vs.patch, 10))
	}
	if cfg.HotfixCounterEnabled && vs.hotfixCounter > 0 {
		parts = append(parts, strconv.FormatInt(vs.hotfixCounter, 10))
	}
	return strings.Join(parts, ".")
}

// NextVersion computes the next version string given the latest tag (which may
// be empty for a cold start) and the bump type. Uses the VersionConfig schema
// to determine which slot to increment — mirrors bash calculate-version.sh logic
// (post-ticket-042: BumpMinor and BumpPatch both increment the patch slot, i.e.
// the 3rd active component, as the "minor" label is a commit-type concern only).
func NextVersion(latestTag string, bump BumpType, cfg VersionConfig) (string, error) {
	prefix := ""
	if cfg.TagPrefixV {
		prefix = "v"
	}

	// Hotfix uses a 4-component dot-separated tag — dedicated handler.
	if bump == BumpHotfix {
		return nextHotfixVersion(latestTag, prefix, cfg)
	}

	var vs versionSlots

	if latestTag == "" {
		// Cold start: seed from initial values.
		vs = versionSlots{
			epoch:         int64(cfg.EpochInitial),
			major:         int64(cfg.MajorInitial),
			patch:         int64(cfg.PatchInitial),
			hotfixCounter: int64(cfg.HotfixCounterInitial),
		}
	} else {
		var err error
		vs, err = parseVersionSlots(latestTag, cfg)
		if err != nil {
			return "", fmt.Errorf("versioning.NextVersion: %w", err)
		}
	}

	switch bump {
	case BumpMajor:
		vs.major++
		vs.patch = 0
		vs.hotfixCounter = 0
	case BumpMinor:
		// Post-ticket-042: "minor" bump (feat/feature) increments the patch slot
		// (3rd active component). There is no separate "minor" numeric slot.
		vs.patch++
		vs.hotfixCounter = 0
	case BumpPatch:
		vs.patch++
		vs.hotfixCounter = 0
	case BumpNone:
		// No version change.
	default:
		return "", fmt.Errorf("versioning.NextVersion: unknown bump %q", bump)
	}

	return prefix + buildVersionString(vs, cfg), nil
}

// nextHotfixVersion handles the BumpHotfix case. Delegates rendering to
// buildVersionString so the emitted tag always matches the enabled schema
// (no hardcoded slots, no "base=0" placeholder).
//
// Legacy 4-slot tags (e.g. v12.1.0.1 from earlier pipe versions) are
// handled by parseVersionSlots which extracts hotfix_counter from the last
// slot in that case. The emitted tag is re-collapsed to the current schema.
func nextHotfixVersion(latestTag, prefix string, cfg VersionConfig) (string, error) {
	var vs versionSlots

	if latestTag == "" {
		vs = versionSlots{
			epoch:         int64(cfg.EpochInitial),
			major:         int64(cfg.MajorInitial),
			patch:         int64(cfg.PatchInitial),
			hotfixCounter: int64(cfg.HotfixCounterInitial) + 1,
		}
	} else {
		var err error
		vs, err = parseVersionSlots(latestTag, cfg)
		if err != nil {
			return "", fmt.Errorf("versioning.nextHotfixVersion: %w", err)
		}
		vs.hotfixCounter++
	}

	return prefix + buildVersionString(vs, cfg), nil
}
