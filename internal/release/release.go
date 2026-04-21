// Package release implements the check-release-readiness gate.
// It mirrors scripts/release/check-release-readiness.sh exactly:
// each check returns a Result with severity info/warn/block.
// block results cause exit 1; warn and info never block the gate.
package release

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Severity mirrors the bash PASS/FAIL/UNCLEAR semantics.
// block → [FAIL] in output, causes exit 1.
// unclear → [UNCLEAR], never blocks.
// pass → [PASS].
type Severity int

const (
	SeverityPass    Severity = iota
	SeverityUnclear          // [UNCLEAR] — never causes exit 1
	SeverityBlock            // [FAIL]    — causes exit 1
)

// Result is a single check outcome.
type Result struct {
	Name   string
	Sev    Severity
	Reason string // non-empty for FAIL/UNCLEAR
}

func (r Result) String() string {
	switch r.Sev {
	case SeverityBlock:
		return fmt.Sprintf("[FAIL] %s: %s", r.Name, r.Reason)
	case SeverityUnclear:
		return fmt.Sprintf("[UNCLEAR] %s: %s", r.Name, r.Reason)
	default:
		return fmt.Sprintf("[PASS] %s", r.Name)
	}
}

// Report aggregates all check results.
type Report struct {
	Results      []Result
	PassCount    int
	FailCount    int
	UnclearCount int
}

// Blocked returns true when at least one result has severity block.
func (rp *Report) Blocked() bool { return rp.FailCount > 0 }

func (rp *Report) add(r Result) {
	rp.Results = append(rp.Results, r)
	switch r.Sev {
	case SeverityPass:
		rp.PassCount++
	case SeverityBlock:
		rp.FailCount++
	case SeverityUnclear:
		rp.UnclearCount++
	}
}

// Context carries inputs for a readiness check run.
type Context struct {
	RepoRoot string
	BaseRef  string
	Cfg      *config.Config
}

const (
	maxDocAgeDays = 14
	consumerImage = "public.ecr.aws/k5n8p2t3/panora-versioning-pipe"
)

var forbiddenCommitMarkers = []string{
	"[skip ci]",
	"[ci skip]",
	"[no ci]",
	"[skip actions]",
	"[actions skip]",
	"***NO_CI***",
}

// Run executes all readiness checks and returns a Report.
func Run(ctx Context) Report {
	var rp Report

	rp.add(checkChangelogHasEntry(ctx))
	rp.add(checkReadmeTimestamp(ctx))
	rp.add(checkArchitectureTimestamp(ctx))
	rp.add(checkCommitHygiene(ctx))
	rp.add(checkExampleImageURLs(ctx))
	rp.add(checkBitbucketExampleImage(ctx))

	return rp
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func git(repoRoot string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = repoRoot
	out, err := cmd.Output()
	return strings.TrimRight(string(out), "\n"), err
}

// prChangedFiles returns the list of files changed between BASE_REF and HEAD.
// Returns ("", errUnclear) when BASE_REF is unreachable.
func prChangedFiles(ctx Context) ([]string, error) {
	base, err := git(ctx.RepoRoot, "merge-base", ctx.BaseRef, "HEAD")
	if err != nil || base == "" {
		return nil, fmt.Errorf("cannot compute diff against %s", ctx.BaseRef)
	}
	out, err := git(ctx.RepoRoot, "diff", "--name-only", base, "HEAD")
	if err != nil {
		return nil, fmt.Errorf("git diff failed: %w", err)
	}
	if out == "" {
		return nil, nil
	}
	return strings.Split(out, "\n"), nil
}

// prCommitMessages returns all commit message bodies in the PR range.
func prCommitMessages(ctx Context) (string, error) {
	base, err := git(ctx.RepoRoot, "merge-base", ctx.BaseRef, "HEAD")
	if err != nil || base == "" {
		return "", fmt.Errorf("cannot compute commit range against %s", ctx.BaseRef)
	}
	out, err := git(ctx.RepoRoot, "log", "--format=%B%x1e", base+"..HEAD")
	if err != nil {
		return "", fmt.Errorf("git log failed: %w", err)
	}
	return out, nil
}

// fileTouchedInPR returns (true, nil) if target is in the changed files list,
// (false, nil) if not, or ("", err) if BASE_REF is unreachable.
func fileTouchedInPR(ctx Context, target string) (bool, error) {
	changed, err := prChangedFiles(ctx)
	if err != nil {
		return false, err
	}
	for _, f := range changed {
		if f == target {
			return true, nil
		}
	}
	return false, nil
}

// checkDocTimestamp validates **Last updated:** YYYY-MM-DD within maxDocAgeDays.
func checkDocTimestamp(ctx Context, name, file string) Result {
	touched, err := fileTouchedInPR(ctx, file)
	if err != nil {
		return Result{Name: name, Sev: SeverityUnclear, Reason: err.Error()}
	}
	if !touched {
		return Result{Name: name, Sev: SeverityPass}
	}
	data, err := os.ReadFile(filepath.Join(ctx.RepoRoot, file))
	if err != nil {
		return Result{Name: name, Sev: SeverityBlock, Reason: fmt.Sprintf("%s modified in PR but missing from tree", file)}
	}
	re := regexp.MustCompile(`\*\*Last updated:\*\*\s+(\d{4}-\d{2}-\d{2})`)
	m := re.FindSubmatch(data)
	if m == nil {
		return Result{Name: name, Sev: SeverityBlock, Reason: fmt.Sprintf("%s modified but no '**Last updated:** YYYY-MM-DD' line", file)}
	}
	stamp := string(m[1])
	t, err := time.Parse("2006-01-02", stamp)
	if err != nil {
		return Result{Name: name, Sev: SeverityUnclear, Reason: fmt.Sprintf("could not parse date %q", stamp)}
	}
	ageDays := int(time.Since(t).Hours() / 24)
	if ageDays < 0 {
		return Result{Name: name, Sev: SeverityBlock, Reason: fmt.Sprintf("%s timestamp %s is in the future", file, stamp)}
	}
	if ageDays > maxDocAgeDays {
		return Result{Name: name, Sev: SeverityBlock, Reason: fmt.Sprintf("%s timestamp %s is %d days old (max %d)", file, stamp, ageDays, maxDocAgeDays)}
	}
	return Result{Name: name, Sev: SeverityPass}
}

// ---------------------------------------------------------------------------
// Individual checks — mirror bash functions exactly
// ---------------------------------------------------------------------------

// a. CHANGELOG.md modified in this PR, OR PR is docs/meta-only.
func checkChangelogHasEntry(ctx Context) Result {
	const name = "changelog_has_entry"
	changed, err := prChangedFiles(ctx)
	if err != nil {
		return Result{Name: name, Sev: SeverityUnclear, Reason: err.Error()}
	}
	if len(changed) == 0 {
		return Result{Name: name, Sev: SeverityPass}
	}
	for _, f := range changed {
		if f == "CHANGELOG.md" {
			return Result{Name: name, Sev: SeverityPass}
		}
	}
	// Docs-only PRs don't need a CHANGELOG bump.
	codeRe := regexp.MustCompile(`^(cmd/|internal/|config/|Dockerfile$|Makefile$|tests/|go\.mod$|go\.sum$)`)
	for _, f := range changed {
		if codeRe.MatchString(f) {
			return Result{Name: name, Sev: SeverityBlock, Reason: "code files changed but CHANGELOG.md untouched"}
		}
	}
	return Result{Name: name, Sev: SeverityPass}
}

// b. README.md freshness (when touched).
func checkReadmeTimestamp(ctx Context) Result {
	return checkDocTimestamp(ctx, "readme_timestamp", "README.md")
}

// c. docs/architecture/README.md freshness (when touched).
func checkArchitectureTimestamp(ctx Context) Result {
	return checkDocTimestamp(ctx, "architecture_timestamp", "docs/architecture/README.md")
}

// d. No forbidden CI-skip substrings in PR commit messages.
func checkCommitHygiene(ctx Context) Result {
	const name = "commit_hygiene"
	messages, err := prCommitMessages(ctx)
	if err != nil {
		return Result{Name: name, Sev: SeverityUnclear, Reason: err.Error()}
	}
	if messages == "" {
		return Result{Name: name, Sev: SeverityPass}
	}
	var offenders []string
	for _, marker := range forbiddenCommitMarkers {
		if strings.Contains(messages, marker) {
			offenders = append(offenders, "'"+marker+"'")
		}
	}
	if len(offenders) > 0 {
		return Result{
			Name:   name,
			Sev:    SeverityBlock,
			Reason: "forbidden substrings found in PR commit messages: " + strings.Join(offenders, " "),
		}
	}
	return Result{Name: name, Sev: SeverityPass}
}

// e. examples/github-actions/*.yml all reference the current consumer image.
func checkExampleImageURLs(ctx Context) Result {
	const name = "example_image_urls"
	dir := filepath.Join(ctx.RepoRoot, "examples", "github-actions")
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return Result{Name: name, Sev: SeverityUnclear, Reason: dir + " missing"}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return Result{Name: name, Sev: SeverityUnclear, Reason: "could not read " + dir}
	}

	imageLineRe := regexp.MustCompile(`(?i)(docker://|image:\s*)\S+`)
	var bad []string
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".yml" {
			continue
		}
		path := filepath.Join(dir, e.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		imageLines := imageLineRe.FindAllString(string(data), -1)
		if len(imageLines) == 0 {
			continue
		}
		hasConsumer := false
		for _, l := range imageLines {
			if strings.Contains(l, consumerImage) {
				hasConsumer = true
			}
		}
		if !hasConsumer {
			bad = append(bad, e.Name())
			continue
		}
		// Reject any image reference that ISN'T the expected consumer image.
		otherImageRe := regexp.MustCompile(`(?i)(docker://|image:\s*)(\S+/)+`)
		for _, l := range imageLines {
			if !strings.Contains(l, consumerImage) && otherImageRe.MatchString(l) {
				bad = append(bad, e.Name())
				break
			}
		}
	}
	if len(bad) > 0 {
		return Result{Name: name, Sev: SeverityBlock, Reason: "unexpected image reference in: " + strings.Join(bad, " ")}
	}
	return Result{Name: name, Sev: SeverityPass}
}

// h. Bitbucket example mirrors the same image.
func checkBitbucketExampleImage(ctx Context) Result {
	const name = "bitbucket_example_image"
	file := filepath.Join(ctx.RepoRoot, "examples", "bitbucket", "bitbucket-pipelines.yml")
	data, err := os.ReadFile(file)
	if err != nil {
		return Result{Name: name, Sev: SeverityUnclear, Reason: filepath.Base(file) + " missing"}
	}
	if !strings.Contains(string(data), consumerImage) {
		return Result{Name: name, Sev: SeverityBlock, Reason: file + " does not reference " + consumerImage}
	}
	imageRe := regexp.MustCompile(`(?m)^\s*image:\s*(\S+)`)
	matches := imageRe.FindAllSubmatch(data, -1)
	var others []string
	for _, m := range matches {
		img := string(m[1])
		if img != consumerImage && !strings.HasPrefix(img, consumerImage+":") {
			others = append(others, img)
		}
	}
	if len(others) > 0 {
		return Result{
			Name:   name,
			Sev:    SeverityBlock,
			Reason: file + " has non-matching image references: " + strings.Join(others, " "),
		}
	}
	return Result{Name: name, Sev: SeverityPass}
}

// ---------------------------------------------------------------------------
// LoadContext builds a Context from env + filesystem.
// ---------------------------------------------------------------------------

func LoadContext() (Context, error) {
	repoRoot, err := gitRepoRoot()
	if err != nil {
		return Context{}, fmt.Errorf("release: not inside a git repo: %w", err)
	}
	baseRef := os.Getenv("BASE_REF")
	if baseRef == "" {
		baseRef = "origin/main"
	}
	cfgPath := "/tmp/.versioning-merged.yml"
	cfg, err := config.Load(cfgPath)
	if err != nil {
		return Context{}, err
	}
	return Context{RepoRoot: repoRoot, BaseRef: baseRef, Cfg: cfg}, nil
}

func gitRepoRoot() (string, error) {
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	root := strings.TrimRight(string(out), "\n")
	return root, nil
}

// FormatSummary returns the summary line in bash-compatible format.
func FormatSummary(rp Report) string {
	return fmt.Sprintf("summary: %d pass, %d fail, %d unclear",
		rp.PassCount, rp.FailCount, rp.UnclearCount)
}

// FormatGitHubStepSummary returns the markdown table for GITHUB_STEP_SUMMARY.
func FormatGitHubStepSummary(rp Report) string {
	var sb strings.Builder
	sb.WriteString("## Release Readiness Gate\n\n")
	sb.WriteString("| status | check |\n")
	sb.WriteString("| --- | --- |\n")
	for _, r := range rp.Results {
		var status, check string
		s := r.String()
		if idx := strings.Index(s, "] "); idx >= 0 {
			status = s[:idx+1]
			check = s[idx+2:]
		} else {
			status = s
		}
		fmt.Fprintf(&sb, "| %s | %s |\n", status, check)
	}
	sb.WriteString("\n")
	fmt.Fprintf(&sb, "**Summary:** %d pass · %d fail · %d unclear\n",
		rp.PassCount, rp.FailCount, rp.UnclearCount)
	return sb.String()
}
