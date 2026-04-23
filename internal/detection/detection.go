// Package detection classifies a pipeline run into a scenario kind and writes
// /tmp/scenario.env. The logic mirrors detect-scenario.sh exactly — same
// branch dispatch order, same hotfix keyword matching. No git API calls:
// all git information is passed in via DetectContext.
package detection

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/hotfix"
)

// Kind is the detected pipeline scenario.
type Kind string

const (
	KindDevelopmentRelease Kind = "development_release"
	KindHotfix             Kind = "hotfix"
	KindPromotionToMain    Kind = "promotion_to_main"
	KindUnknown            Kind = "unknown"
)

// Scenario holds the detected result.
type Scenario struct {
	Kind Kind
}

// ToEnv serializes the scenario into a sorted key=value map for scenario.env.
// Keys are sorted so the output is deterministic (diff-stable).
func (s Scenario) ToEnv() map[string]string {
	return map[string]string{
		"SCENARIO": string(s.Kind),
	}
}

// WriteEnvFile writes the scenario fields to path in sorted key=value format,
// matching the bash output byte-for-byte.
func WriteEnvFile(path string, s Scenario) error {
	env := s.ToEnv()

	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	var sb strings.Builder
	for _, k := range keys {
		sb.WriteString(k)
		sb.WriteByte('=')
		sb.WriteString(env[k])
		sb.WriteByte('\n')
	}

	if err := os.WriteFile(path, []byte(sb.String()), 0o644); err != nil {
		return fmt.Errorf("detection.WriteEnvFile %s: %w", path, err)
	}
	return nil
}

// DetectContext holds all inputs the detection needs. Keeping it as a struct
// (no interface) matches the ticket's anti-premature-interface rule.
type DetectContext struct {
	// SourceBranch is VERSIONING_BRANCH.
	SourceBranch string
	// TargetBranch is VERSIONING_TARGET_BRANCH. Empty means branch context.
	TargetBranch string
	// Commit is VERSIONING_COMMIT (defaults to "HEAD").
	Commit string
	// WorkDir is the git working directory (cwd in bash).
	WorkDir string
	// Config is the parsed versioning config.
	Config Config
}

// Config holds the fields detect-scenario.sh reads from the merged YAML.
type Config struct {
	TagBranch          string
	HotfixTargets      []string
	HotfixKeywords     []string // Go regex patterns (regexp stdlib).
	HotfixBranchPrefix string   // Branch prefix used to detect hotfix sources, e.g. "hotfix/".
}

// isHotfixTarget returns true when branch is in the hotfix_targets list.
func (c Config) isHotfixTarget(branch string) bool {
	for _, t := range c.HotfixTargets {
		if t == branch {
			return true
		}
	}
	return false
}

// matchesHotfixKeyword checks whether subject matches any configured pattern
// via the unified hotfix.Matcher. Compilation errors are treated as "no match"
// here — config load is the canonical place to surface invalid regex.
func matchesHotfixKeyword(subject string, patterns []string) bool {
	m, err := hotfix.NewMatcher(patterns)
	if err != nil {
		return false
	}
	return m.Matches(subject)
}

// matchesHotfixBranch checks whether branch starts with the hotfix branch prefix.
func matchesHotfixBranch(branch, prefix string) bool {
	return strings.HasPrefix(branch, prefix)
}

// extractBranchFromMergeSubject extracts the source branch name from a
// GitHub-style merge commit subject:
// "Merge pull request #N from org/hotfix/fix-auth" → "hotfix/fix-auth"
// Returns "" when the subject does not match the expected format.
func extractBranchFromMergeSubject(subject string) string {
	if !strings.HasPrefix(subject, "Merge pull request #") {
		return ""
	}
	fromIdx := strings.Index(subject, " from ")
	if fromIdx < 0 {
		return ""
	}
	rest := subject[fromIdx+6:]
	slashIdx := strings.Index(rest, "/")
	if slashIdx < 0 {
		return ""
	}
	return rest[slashIdx+1:]
}

// headCommitSubject returns the subject of the given commit using the git CLI.
// Mirrors: git log -1 --format='%s' "$COMMIT"
func headCommitSubject(workDir, commit string) string {
	out, err := exec.Command("git", "-C", workDir, "log", "-1", "--format=%s", commit).Output()
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(out), "\n")
}

// commitParents returns the parent hashes of commit using the git CLI.
// Mirrors: git log -1 --format='%P' "$COMMIT"
func commitParents(workDir, commit string) []string {
	out, err := exec.Command("git", "-C", workDir, "log", "-1", "--format=%P", commit).Output()
	if err != nil {
		return nil
	}
	raw := strings.TrimRight(string(out), "\n")
	if raw == "" {
		return nil
	}
	return strings.Fields(raw)
}

// parentSubject returns the commit subject for hash using git CLI.
func parentSubject(workDir, hash string) string {
	out, err := exec.Command("git", "-C", workDir, "log", "-1", "--format=%s", hash).Output()
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(out), "\n")
}

// Detect classifies the pipeline run described by ctx into a Scenario.
// It mirrors detect-scenario.sh's logic exactly: branch context when
// TargetBranch is empty, PR context otherwise.
func Detect(ctx DetectContext) (Scenario, error) {
	cfg := ctx.Config
	hotfixPrefix := cfg.HotfixBranchPrefix
	if hotfixPrefix == "" {
		hotfixPrefix = "hotfix/"
	}
	commit := ctx.Commit
	if commit == "" {
		commit = "HEAD"
	}

	// ── Branch context (no PR target) ──────────────────────────────────────
	if ctx.TargetBranch == "" {
		headSubject := headCommitSubject(ctx.WorkDir, commit)
		parents := commitParents(ctx.WorkDir, commit)

		// Check 1: HEAD subject matches hotfix keyword.
		if matchesHotfixKeyword(headSubject, cfg.HotfixKeywords) {
			return Scenario{Kind: KindHotfix}, nil
		}

		// Checks 2 and 3 only for merge commits (2+ parents).
		if len(parents) >= 2 {
			// Check 2: recover source branch from GitHub-style merge subject.
			mergedBranch := extractBranchFromMergeSubject(headSubject)
			if mergedBranch != "" && matchesHotfixBranch(mergedBranch, hotfixPrefix) {
				return Scenario{Kind: KindHotfix}, nil
			}

			// Check 3: second parent commit subject.
			branchParentSubject := parentSubject(ctx.WorkDir, parents[1])
			if matchesHotfixKeyword(branchParentSubject, cfg.HotfixKeywords) {
				return Scenario{Kind: KindHotfix}, nil
			}
		}

		return Scenario{Kind: KindDevelopmentRelease}, nil
	}

	// ── PR context: dispatch on target branch ───────────────────────────────
	target := ctx.TargetBranch
	source := ctx.SourceBranch
	tagBranch := cfg.TagBranch

	if target == tagBranch && cfg.isHotfixTarget(target) {
		// tag_on == hotfix_target: hotfix/ source wins over development_release.
		if matchesHotfixBranch(source, hotfixPrefix) {
			return Scenario{Kind: KindHotfix}, nil
		}
		return Scenario{Kind: KindDevelopmentRelease}, nil
	}

	if target == tagBranch {
		return Scenario{Kind: KindDevelopmentRelease}, nil
	}

	if cfg.isHotfixTarget(target) {
		if matchesHotfixBranch(source, hotfixPrefix) {
			return Scenario{Kind: KindHotfix}, nil
		}
		if source == tagBranch {
			return Scenario{Kind: KindPromotionToMain}, nil
		}
		return Scenario{Kind: KindUnknown}, nil
	}

	return Scenario{Kind: KindUnknown}, nil
}

// LoadConfig parses a .versioning.yml (or /tmp/.versioning-merged.yml) via the
// canonical config.Load loader and maps the fields detect-scenario needs.
func LoadConfig(path string) (Config, error) {
	cfg, err := config.Load(path)
	if err != nil {
		return Config{}, fmt.Errorf("detection.LoadConfig %s: %w", path, err)
	}
	return Config{
		TagBranch:          cfg.Branches.TagOn,
		HotfixTargets:      cfg.Branches.HotfixTargets,
		HotfixKeywords:     cfg.Hotfix.Keyword.Values,
		HotfixBranchPrefix: cfg.Hotfix.BranchPrefix,
	}, nil
}

// FindConfig locates the versioning config to use for detection.
// Priority: /tmp/.versioning-merged.yml (already processed by bash),
// then .versioning.yml in workDir.
func FindConfig(workDir string) (string, error) {
	merged := "/tmp/.versioning-merged.yml"
	if _, err := os.Stat(merged); err == nil {
		return merged, nil
	}
	local := filepath.Join(workDir, ".versioning.yml")
	if _, err := os.Stat(local); err == nil {
		return local, nil
	}
	return "", fmt.Errorf("detection.FindConfig: no config found (tried %s and %s)", merged, local)
}
