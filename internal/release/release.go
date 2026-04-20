// Package release implements the check-release-readiness gate.
//
// Each check is a plain function returning a Severity + reason. Check
// aggregates all results into a Report. Severity "block" causes exit 1;
// "warn" and "info" are surfaced but never block.
package release

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Severity classifies a check result.
type Severity string

const (
	SeverityPass    Severity = "pass"
	SeverityInfo    Severity = "info"
	SeverityWarn    Severity = "warn"
	SeverityBlock   Severity = "block"
	SeverityUnclear Severity = "unclear"
)

// Result holds the outcome of a single readiness check.
type Result struct {
	Name     string
	Severity Severity
	Reason   string
}

// Report aggregates all check results.
type Report struct {
	Results      []Result
	PassCount    int
	FailCount    int
	UnclearCount int
}

// Context carries inputs for a readiness run.
type Context struct {
	Cfg      *config.Config
	RepoRoot string
	BaseRef  string
	Stdout   io.Writer
	Stderr   io.Writer
}

const (
	maxDocAgeDays    = 14
	minUnitTestCount = 207
	consumerImage    = "public.ecr.aws/k5n8p2t3/panora-versioning-pipe"
)

var forbiddenCIMarkers = []string{
	"[skip ci]",
	"[ci skip]",
	"[no ci]",
	"[skip actions]",
	"[actions skip]",
	"***NO_CI***",
}

// Check runs all readiness checks and returns a Report.
func Check(ctx Context) (Report, error) {
	type checkFn func(Context) (Severity, string)
	checks := []struct {
		name string
		fn   checkFn
	}{
		{"workdir_clean", workdirClean},
		{"version_files_exist", missingVersionFiles},
		{"changelog_has_entry", checkChangelogHasEntry},
		{"readme_timestamp", func(c Context) (Severity, string) {
			return checkDocTimestamp(c, "README.md")
		}},
		{"architecture_timestamp", func(c Context) (Severity, string) {
			return checkDocTimestamp(c, "docs/architecture/README.md")
		}},
		{"commit_hygiene", checkCommitHygiene},
		{"unit_test_count", checkUnitTestCount},
		{"defaults_keys_have_getters", checkDefaultsKeysHaveGetters},
		{"example_image_urls", checkExampleImageURLs},
		{"bitbucket_example_image", checkBitbucketExampleImage},
	}

	var r Report
	for _, c := range checks {
		sev, reason := c.fn(ctx)
		r.Results = append(r.Results, Result{Name: c.name, Severity: sev, Reason: reason})
		switch sev {
		case SeverityBlock:
			r.FailCount++
		case SeverityUnclear:
			r.UnclearCount++
		default:
			r.PassCount++
		}
	}
	return r, nil
}

// HasBlockingResult returns true if any result has block severity.
func HasBlockingResult(r Report) bool {
	return r.FailCount > 0
}

// Print writes the report to w in bash-compatible format.
func Print(r Report, w io.Writer) {
	for _, res := range r.Results {
		switch res.Severity {
		case SeverityPass:
			fmt.Fprintf(w, "[PASS] %s\n", res.Name)
		case SeverityInfo:
			fmt.Fprintf(w, "[INFO] %s: %s\n", res.Name, res.Reason)
		case SeverityWarn:
			fmt.Fprintf(w, "[WARN] %s: %s\n", res.Name, res.Reason)
		case SeverityBlock:
			fmt.Fprintf(w, "[FAIL] %s: %s\n", res.Name, res.Reason)
		case SeverityUnclear:
			fmt.Fprintf(w, "[UNCLEAR] %s: %s\n", res.Name, res.Reason)
		}
	}
	fmt.Fprintln(w)
	fmt.Fprintln(w, "------------------------------------------")
	fmt.Fprintf(w, "summary: %d pass, %d fail, %d unclear\n", r.PassCount, r.FailCount, r.UnclearCount)
	fmt.Fprintln(w, "------------------------------------------")
}

func gitRun(ctx Context, args ...string) ([]byte, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = ctx.RepoRoot
	return cmd.Output()
}

func prChangedFiles(ctx Context) ([]string, bool) {
	base, err := gitRun(ctx, "merge-base", ctx.BaseRef, "HEAD")
	if err != nil {
		return nil, false
	}
	baseHash := strings.TrimSpace(string(base))
	out, err := gitRun(ctx, "diff", "--name-only", baseHash, "HEAD")
	if err != nil {
		return nil, false
	}
	var files []string
	for _, f := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if f != "" {
			files = append(files, f)
		}
	}
	return files, true
}

func prCommitMessages(ctx Context) (string, bool) {
	base, err := gitRun(ctx, "merge-base", ctx.BaseRef, "HEAD")
	if err != nil {
		return "", false
	}
	baseHash := strings.TrimSpace(string(base))
	out, err := gitRun(ctx, "log", "--format=%B%x1e", baseHash+"..HEAD")
	if err != nil {
		return "", false
	}
	return string(out), true
}

var codePathPattern = regexp.MustCompile(`^(scripts/|pipe\.sh$|Dockerfile$|Makefile$|tests/)`)

func checkChangelogHasEntry(ctx Context) (Severity, string) {
	changed, ok := prChangedFiles(ctx)
	if !ok {
		return SeverityUnclear, "cannot compute diff against " + ctx.BaseRef
	}
	if len(changed) == 0 {
		return SeverityPass, ""
	}
	for _, f := range changed {
		if f == "CHANGELOG.md" {
			return SeverityPass, ""
		}
	}
	for _, f := range changed {
		if codePathPattern.MatchString(f) {
			return SeverityBlock, "code files changed but CHANGELOG.md untouched"
		}
	}
	return SeverityPass, ""
}

var lastUpdatedRe = regexp.MustCompile(`\*\*Last updated:\*\*\s+(\d{4}-\d{2}-\d{2})`)

func extractLastUpdated(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if m := lastUpdatedRe.FindStringSubmatch(scanner.Text()); len(m) == 2 {
			return m[1], nil
		}
	}
	return "", nil
}

func checkDocTimestamp(ctx Context, file string) (Severity, string) {
	changed, ok := prChangedFiles(ctx)
	if !ok {
		return SeverityUnclear, "cannot compute diff against " + ctx.BaseRef
	}
	touched := false
	for _, f := range changed {
		if f == file {
			touched = true
			break
		}
	}
	if !touched {
		return SeverityPass, ""
	}
	fullPath := filepath.Join(ctx.RepoRoot, file)
	if _, err := os.Stat(fullPath); os.IsNotExist(err) {
		return SeverityBlock, file + " modified in PR but missing from tree"
	}
	stamp, err := extractLastUpdated(fullPath)
	if err != nil || stamp == "" {
		return SeverityBlock, file + " modified but no '**Last updated:** YYYY-MM-DD' line"
	}
	t, err := time.Parse("2006-01-02", stamp)
	if err != nil {
		return SeverityUnclear, "could not parse date '" + stamp + "'"
	}
	ageDays := int(time.Since(t).Hours() / 24)
	if ageDays < 0 {
		return SeverityBlock, fmt.Sprintf("%s timestamp %s is in the future", file, stamp)
	}
	if ageDays > maxDocAgeDays {
		return SeverityBlock, fmt.Sprintf("%s timestamp %s is %d days old (max %d)", file, stamp, ageDays, maxDocAgeDays)
	}
	return SeverityPass, ""
}

func checkCommitHygiene(ctx Context) (Severity, string) {
	messages, ok := prCommitMessages(ctx)
	if !ok {
		return SeverityUnclear, "cannot compute commit range against " + ctx.BaseRef
	}
	if strings.TrimSpace(messages) == "" {
		return SeverityPass, ""
	}
	var offenders []string
	for _, marker := range forbiddenCIMarkers {
		if strings.Contains(messages, marker) {
			offenders = append(offenders, "'"+marker+"'")
		}
	}
	if len(offenders) > 0 {
		return SeverityBlock, "forbidden substrings found in PR commit messages: " + strings.Join(offenders, " ")
	}
	return SeverityPass, ""
}

func checkUnitTestCount(ctx Context) (Severity, string) {
	testsDir := filepath.Join(ctx.RepoRoot, "tests")
	if _, err := os.Stat(testsDir); os.IsNotExist(err) {
		return SeverityUnclear, "tests/ directory missing"
	}
	count := 0
	err := filepath.Walk(testsDir, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil || !strings.HasSuffix(path, ".bats") {
			return nil
		}
		f, err := os.Open(path)
		if err != nil {
			return nil
		}
		defer f.Close()
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			if strings.HasPrefix(scanner.Text(), "@test ") {
				count++
			}
		}
		return nil
	})
	if err != nil {
		return SeverityUnclear, "error walking tests/: " + err.Error()
	}
	if count == 0 {
		return SeverityUnclear, "could not count @test definitions under tests/"
	}
	if count < minUnitTestCount {
		return SeverityBlock, fmt.Sprintf("found %d @test definitions, expected >= %d", count, minUnitTestCount)
	}
	return SeverityPass, ""
}

func topLevelYAMLKeys(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	keyRe := regexp.MustCompile(`^([a-z_][a-z0-9_]*):\s`)
	var keys []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if m := keyRe.FindStringSubmatch(scanner.Text()); len(m) == 2 {
			keys = append(keys, m[1])
		}
	}
	return keys, scanner.Err()
}

func checkDefaultsKeysHaveGetters(ctx Context) (Severity, string) {
	defaultsFile := filepath.Join(ctx.RepoRoot, "scripts", "defaults.yml")
	parserFile := filepath.Join(ctx.RepoRoot, "scripts", "lib", "config-parser.sh")

	if _, err := os.Stat(defaultsFile); os.IsNotExist(err) {
		return SeverityUnclear, "defaults.yml missing"
	}
	if _, err := os.Stat(parserFile); os.IsNotExist(err) {
		return SeverityUnclear, "config-parser.sh missing"
	}

	keys, err := topLevelYAMLKeys(defaultsFile)
	if err != nil || len(keys) == 0 {
		return SeverityUnclear, "could not read top-level keys from defaults.yml"
	}

	parserBytes, err := os.ReadFile(parserFile)
	if err != nil {
		return SeverityUnclear, "could not read config-parser.sh"
	}
	parserContent := string(parserBytes)

	scriptsDir := filepath.Join(ctx.RepoRoot, "scripts")
	var allScripts strings.Builder
	_ = filepath.Walk(scriptsDir, func(p string, info os.FileInfo, walkErr error) error {
		if walkErr != nil || info.IsDir() {
			return nil
		}
		data, err := os.ReadFile(p)
		if err == nil {
			allScripts.Write(data)
		}
		return nil
	})

	exempt := map[string]bool{"notifications": true, "commit_types": true}
	var missing []string
	for _, key := range keys {
		if exempt[key] {
			combined := parserContent + allScripts.String()
			if !strings.Contains(combined, "."+key+".") && !strings.Contains(combined, key) {
				missing = append(missing, key)
			}
			continue
		}
		pat := `config_get(_array)?\s+"` + regexp.QuoteMeta(key) + `\.`
		matched, _ := regexp.MatchString(pat, parserContent)
		if !matched {
			missing = append(missing, key)
		}
	}
	if len(missing) > 0 {
		return SeverityBlock, "defaults.yml keys without a getter in config-parser.sh: " + strings.Join(missing, " ")
	}
	return SeverityPass, ""
}

func checkExampleImageURLs(ctx Context) (Severity, string) {
	dir := filepath.Join(ctx.RepoRoot, "examples", "github-actions")
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return SeverityUnclear, "examples/github-actions missing"
	}
	imageLineRe := regexp.MustCompile(`(docker://|image:\s*)(\S+)`)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return SeverityUnclear, "could not read examples/github-actions"
	}
	var bad []string
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yml") {
			continue
		}
		content, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			continue
		}
		matches := imageLineRe.FindAllStringSubmatch(string(content), -1)
		if len(matches) == 0 {
			continue
		}
		hasConsumer, hasOther := false, false
		for _, m := range matches {
			img := m[2]
			if strings.Contains(img, consumerImage) {
				hasConsumer = true
			} else if strings.Contains(img, "/") {
				hasOther = true
			}
		}
		if !hasConsumer || hasOther {
			bad = append(bad, e.Name())
		}
	}
	if len(bad) > 0 {
		return SeverityBlock, "unexpected image reference in: " + strings.Join(bad, " ")
	}
	return SeverityPass, ""
}

func checkBitbucketExampleImage(ctx Context) (Severity, string) {
	file := filepath.Join(ctx.RepoRoot, "examples", "bitbucket", "bitbucket-pipelines.yml")
	if _, err := os.Stat(file); os.IsNotExist(err) {
		return SeverityUnclear, file + " missing"
	}
	content, err := os.ReadFile(file)
	if err != nil {
		return SeverityUnclear, "could not read " + file
	}
	if !strings.Contains(string(content), consumerImage) {
		return SeverityBlock, file + " does not reference " + consumerImage
	}
	imageLineRe := regexp.MustCompile(`(?m)^\s*image:\s*(\S+)`)
	for _, m := range imageLineRe.FindAllStringSubmatch(string(content), -1) {
		img := m[1]
		if !strings.Contains(img, consumerImage) && strings.Contains(img, "/") {
			return SeverityBlock, file + " has non-matching image references: " + img
		}
	}
	return SeverityPass, ""
}

func workdirClean(ctx Context) (Severity, string) {
	staged, err := gitRun(ctx, "diff", "--cached", "--name-only")
	if err != nil {
		return SeverityUnclear, "could not run git diff --cached: " + err.Error()
	}
	unstaged, err := gitRun(ctx, "diff", "--name-only")
	if err != nil {
		return SeverityUnclear, "could not run git diff: " + err.Error()
	}
	if strings.TrimSpace(string(staged)) != "" || strings.TrimSpace(string(unstaged)) != "" {
		return SeverityBlock, "working directory has uncommitted changes"
	}
	return SeverityPass, ""
}

func missingVersionFiles(ctx Context) (Severity, string) {
	if !ctx.Cfg.VersionFile.Enabled || len(ctx.Cfg.VersionFile.Groups) == 0 {
		return SeverityPass, ""
	}
	var missing []string
	for _, group := range ctx.Cfg.VersionFile.Groups {
		for _, entry := range group.Files {
			if entry == "" {
				continue
			}
			abs := filepath.Join(ctx.RepoRoot, entry)
			if _, err := os.Stat(abs); os.IsNotExist(err) {
				missing = append(missing, entry)
			}
		}
	}
	if len(missing) > 0 {
		return SeverityBlock, "configured version files missing: " + strings.Join(missing, ", ")
	}
	return SeverityPass, ""
}
