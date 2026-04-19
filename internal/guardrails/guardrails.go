package guardrails

import (
	"fmt"
	"io"
	"os"
	"strings"
)

// BumpType mirrors the bump_type values produced by calculate-version.sh.
type BumpType string

const (
	BumpEpoch  BumpType = "epoch"
	BumpMajor  BumpType = "major"
	BumpMinor  BumpType = "minor"
	BumpPatch  BumpType = "patch"
	BumpHotfix BumpType = "hotfix"
)

// RunContext carries the inputs for a full guardrail run.
type RunContext struct {
	Cfg       Config
	NextTag   string
	LatestTag string
	BumpType  BumpType
	Stderr    io.Writer
	Stdout    io.Writer
}

// guardrailLog emits a structured GUARDRAIL log line to stderr.
// Format matches the bash contract: GUARDRAIL name=X result=Y key=value ...
func guardrailLog(w io.Writer, name, result string, pairs ...string) {
	var sb strings.Builder
	sb.WriteString("GUARDRAIL name=")
	sb.WriteString(name)
	sb.WriteString(" result=")
	sb.WriteString(result)
	for i := 0; i+1 < len(pairs); i += 2 {
		sb.WriteString(" ")
		sb.WriteString(pairs[i])
		sb.WriteString("=")
		sb.WriteString(pairs[i+1])
	}
	_, _ = fmt.Fprintln(w, sb.String())
}

// parsedComponents holds numeric version components extracted from a tag.
type parsedComponents struct {
	epoch         int64
	major         int64
	minor         int64
	patch         int64
	hotfixCounter int64
}

// parseTag strips the v-prefix, parses via Masterminds/semver, and extracts
// the component values the guardrail rules need.
//
// Component mapping (mirrors parse_version_components in config-parser.sh):
//   - epoch enabled  → semver Major = epoch, Minor = major, Patch = patch
//   - epoch disabled → semver Major = major, Minor = patch, Patch = hotfix_counter
//   - hotfix_counter → trailing pre-release or 4th dot-separated field
//
// In practice the tags are dot-separated numerics (not real semver), so we
// use the semver library only for value extraction, not precedence comparison.
func parseTag(tag string, cfg Config) (parsedComponents, error) {
	stripped := strings.TrimPrefix(tag, "v")

	// Use Masterminds/semver to parse. It handles 3-part versions well;
	// for 4-part (epoch.major.patch.hotfix) we need manual extraction.
	parts := strings.Split(stripped, ".")

	getField := func(idx int) int64 {
		if idx >= len(parts) {
			return 0
		}
		var v int64
		_, _ = fmt.Sscanf(parts[idx], "%d", &v)
		return v
	}

	var pc parsedComponents
	pos := 0

	if cfg.Version.Components.Epoch.Enabled {
		pc.epoch = getField(pos)
		pos++
	}

	if cfg.Version.Components.Major.Enabled {
		pc.major = getField(pos)
		pos++
	}

	if cfg.Version.Components.Patch.Enabled {
		pc.patch = getField(pos)
		pos++
	}

	if cfg.Version.Components.HotfixCounter.Enabled {
		pc.hotfixCounter = getField(pos)
	}

	return pc, nil
}

// AssertNoVersionRegression checks that next is consistent with the declared
// bump_type relative to latest, following the bump-aware rules from ticket 060.
//
// Returns nil on pass, a non-nil error on block. When the escape hatch
// allow_version_regression is active, a warning is logged and nil is returned
// (the pipeline continues). A second bool return signals whether the result
// was a warning (exit 2 in bash).
func AssertNoVersionRegression(ctx RunContext) (warned bool, err error) {
	const name = "no_version_regression"

	nextTag := strings.TrimSpace(ctx.NextTag)
	latestTag := strings.TrimSpace(ctx.LatestTag)
	bump := ctx.BumpType

	// Pass cases where comparison is not applicable.
	if nextTag == "" {
		guardrailLog(ctx.Stderr, name, "pass", "reason", "no_next_tag")
		return false, nil
	}
	if bump == "" {
		guardrailLog(ctx.Stderr, name, "pass", "reason", "no_bump", "next", nextTag)
		return false, nil
	}
	if latestTag == "" {
		guardrailLog(ctx.Stderr, name, "pass", "reason", "cold_start", "next", nextTag, "bump", string(bump))
		return false, nil
	}

	next, err := parseTag(nextTag, ctx.Cfg)
	if err != nil {
		return false, fmt.Errorf("guardrails: parse next tag %q: %w", nextTag, err)
	}
	latest, err := parseTag(latestTag, ctx.Cfg)
	if err != nil {
		return false, fmt.Errorf("guardrails: parse latest tag %q: %w", latestTag, err)
	}

	violation := checkViolation(bump, next, latest)

	if violation == "" {
		guardrailLog(ctx.Stderr, name, "pass", "bump", string(bump), "next", nextTag, "latest", latestTag)
		return false, nil
	}

	if ctx.Cfg.Validation.AllowVersionRegression {
		guardrailLog(ctx.Stderr, name, "warned",
			"violation", violation,
			"bump", string(bump),
			"next", nextTag,
			"latest", latestTag,
			"override", "allow_version_regression",
		)
		_, _ = fmt.Fprintf(ctx.Stderr, "⚠️  Version regression allowed by validation.allow_version_regression=true: %s vs %s (%s)\n",
			nextTag, latestTag, violation)
		return true, nil
	}

	guardrailLog(ctx.Stderr, name, "blocked",
		"violation", violation,
		"bump", string(bump),
		"next", nextTag,
		"latest", latestTag,
	)
	_, _ = fmt.Fprintf(ctx.Stderr, "ERROR: Version regression blocked: computed tag %s is inconsistent with bump=%s relative to latest tag %s (violation: %s).\n",
		nextTag, bump, latestTag, violation)
	_, _ = fmt.Fprintf(ctx.Stderr, "ERROR: This usually means version.components.*.initial was misconfigured or the namespace filter excluded the latest tag.\n")
	_, _ = fmt.Fprintf(ctx.Stderr, "ERROR: To allow an intentional downgrade, set validation.allow_version_regression: true in .versioning.yml.\n")

	return false, fmt.Errorf("version regression: %s (next=%s, latest=%s, bump=%s)", violation, nextTag, latestTag, bump)
}

// checkViolation applies the per-bump-type rules and returns the violation name
// or empty string if the assertion passes.
func checkViolation(bump BumpType, next, latest parsedComponents) string {
	switch bump {
	case BumpEpoch:
		if next.epoch <= latest.epoch {
			return "epoch_not_incremented"
		}

	case BumpMajor:
		if next.major <= latest.major {
			return "major_not_incremented"
		}
		if next.epoch < latest.epoch {
			return "epoch_regressed"
		}

	case BumpMinor, BumpPatch:
		if next.patch <= latest.patch {
			return "patch_not_incremented"
		}
		if next.major < latest.major {
			return "major_regressed"
		}
		if next.epoch < latest.epoch {
			return "epoch_regressed"
		}

	case BumpHotfix:
		sameBase := next.epoch == latest.epoch &&
			next.major == latest.major &&
			next.patch == latest.patch

		if sameBase {
			if next.hotfixCounter <= latest.hotfixCounter {
				return "hotfix_counter_not_incremented"
			}
		} else {
			// Tuple comparison: higher-order component dominates.
			if next.epoch > latest.epoch {
				// epoch increased → entire base is greater, valid
			} else if next.epoch < latest.epoch {
				return "epoch_regressed"
			} else if next.major > latest.major {
				// same epoch, major increased → valid regardless of patch
			} else if next.major < latest.major {
				return "major_regressed"
			} else if next.patch < latest.patch {
				return "patch_regressed"
			}
		}

	default:
		// Unknown bump type — log pass with reason, don't crash pipeline.
		return ""
	}

	return ""
}

// Run executes all registered guardrails in order.
// Returns a slice of errors (one per blocking guardrail).
func Run(ctx RunContext) []error {
	var errs []error

	warned, err := AssertNoVersionRegression(ctx)
	if err != nil {
		errs = append(errs, err)
	}
	_ = warned // exit 2 semantics are handled at the cmd layer

	return errs
}

// readStateLine reads a state file from the given path, returning "" if the
// file doesn't exist (mirrors bash `read_state ... || echo ""`).
func readStateLine(path string) string {
	if path == "" {
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	line := strings.TrimSpace(string(data))
	// Strip the trailing newline that bash state files carry.
	return strings.SplitN(line, "\n", 2)[0]
}

// LoadRunContext builds a RunContext from env / config. Called by both subcommands.
func LoadRunContext(stdout, stderr io.Writer) (RunContext, error) {
	cfgPath := MergedConfigPath()
	cfg, err := LoadConfig(cfgPath)
	if err != nil {
		return RunContext{}, err
	}

	nextTag := readStateLine(StateFilePath("PANORA_STATE_NEXT_VERSION", "/tmp/next_version.txt"))
	latestTag := readStateLine(StateFilePath("PANORA_STATE_LATEST_TAG", "/tmp/latest_tag.txt"))
	bumpRaw := readStateLine(StateFilePath("PANORA_STATE_BUMP_TYPE", "/tmp/bump_type.txt"))

	return RunContext{
		Cfg:       cfg,
		NextTag:   nextTag,
		LatestTag: latestTag,
		BumpType:  BumpType(bumpRaw),
		Stdout:    stdout,
		Stderr:    stderr,
	}, nil
}
