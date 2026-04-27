package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/adapters/bitbucket"
	ghAdapter "github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/adapters/github"
	"github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/core"
)

func main() {
	platform := flag.String("platform", "github", "platform: github | bitbucket")
	filter := flag.String("filter", "", "filter scenarios by name substring")
	parallel := flag.Int("parallel", 0, "goroutine concurrency (default: runtime.NumCPU)")
	timeout := flag.Duration("timeout", 5*time.Minute, "timeout per scenario")
	failFast := flag.Bool("fail-fast", false, "stop on first failure")
	runID := flag.String("run-id", "", "override run ID (default: random 8 hex chars)")
	repo := flag.String("repo", "", "override test repo (e.g. org/repo-fork)")
	imageTag := flag.String("image-tag", "", "pipe preview image tag for workflow dispatch")
	scenariosFlag := flag.String("scenarios", "", "path to scenarios YAML (overrides SCENARIOS_FILE env var)")
	flag.Parse()

	// Load .env.local if present — must happen before validateEnv so credentials
	// set there are visible to the validation step. Never fails if file is absent.
	loadEnvFile(filepath.Join("tests", "integration-go", ".env.local"))

	// Validate required env vars before doing anything else.
	// Lists ALL missing vars at once so the user can fix them in one shot.
	validateEnv(*platform, *repo)

	// Resolve scenarios file path relative to this binary's source dir.
	// When invoked via `go run ./tests/integration-go/cmd/...` from repo root,
	// the scenarios YAML lives at tests/integration-go/scenarios/test-scenarios.yml.
	scenariosPath := scenariosFilePath(*scenariosFlag)

	scenarios, err := core.LoadScenarios(scenariosPath)
	if err != nil {
		fatalf("load scenarios: %v", err)
	}

	if *runID == "" {
		*runID = envOrRandom("TEST_RUN_ID")
	}

	p := *parallel
	if p <= 0 {
		p = runtime.NumCPU()
	}

	opts := core.RunOptions{
		Platform:    *platform,
		Filter:      *filter,
		Parallelism: p,
		Timeout:     *timeout,
		FailFast:    *failFast,
		RunID:       *runID,
		ImageTag:    *imageTag,
	}

	driver, err := buildDriver(*platform, *repo)
	if err != nil {
		fatalf("build driver: %v", err)
	}

	pool := core.NewSandboxPool()
	runner := core.NewRunner(driver, pool, opts)

	fmt.Printf("Platform: %s | Scenarios: %s | RunID: %s\n",
		*platform, scenariosPath, *runID)

	results := runner.Run(context.Background(), scenarios)

	// Print results table
	fmt.Println()
	passed := 0
	failed := 0
	skipped := 0
	xfailCount := 0
	xpassCount := 0
	for _, r := range results {
		var status string
		switch {
		case r.Skipped:
			status = "SKIP"
			skipped++
		case r.Xpass:
			status = "XPASS"
			xpassCount++
		case r.Xfail:
			status = "XFAIL"
			xfailCount++
		case r.Passed:
			status = "PASS"
			passed++
		default:
			status = "FAIL"
			failed++
		}
		tag := r.CreatedTag
		if tag == "" {
			tag = "-"
		}
		detail := ""
		switch {
		case r.SkipReason != "":
			detail = "  " + r.SkipReason
		case r.Xpass:
			detail = "  SCENARIO MARKED XFAIL BUT PASSED — remove xfail and update ticket"
		case r.Xfail:
			detail = "  " + r.XfailReason
		case r.Error != nil:
			detail = "  " + r.Error.Error()
		}
		fmt.Printf("%-6s %-45s %-10s %6.1fs   tag=%-15s%s\n",
			status, r.Scenario, r.Platform, r.Duration.Seconds(), tag, detail)
	}

	fmt.Printf("\n---\nScenarios: %d total, %d passed, %d failed, %d skipped, %d xfail, %d xpass\n",
		len(results), passed, failed, skipped, xfailCount, xpassCount)

	if failed > 0 || xpassCount > 0 {
		os.Exit(1)
	}
}

// loadEnvFile reads a KEY=VALUE file and sets each variable in the process environment.
// Skips blank lines and lines starting with #. Does not override variables already set
// in the environment (explicit env wins over file). Silent if the file doesn't exist.
func loadEnvFile(path string) {
	f, err := os.Open(path)
	if err != nil {
		return // file absent — not an error
	}
	defer func() { _ = f.Close() }()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.IndexByte(line, '=')
		if idx < 1 {
			continue // malformed line — skip silently
		}
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		if os.Getenv(key) == "" {
			_ = os.Setenv(key, val)
		}
	}
}

// validateEnv checks that all required env vars are set for the chosen platform.
// Lists every missing variable in one shot before exiting — never cuts at the first error.
func validateEnv(platform, repoFlag string) {
	type requirement struct {
		name string
		desc string
		// present returns true when the variable is satisfied (env set or flag override).
		present func() bool
	}

	var reqs []requirement

	switch platform {
	case "github":
		reqs = []requirement{
			{
				name:    "INTEGRATION_TEST_TOKEN",
				desc:    "GitHub personal access token with repo+workflow scopes",
				present: func() bool { return os.Getenv("INTEGRATION_TEST_TOKEN") != "" },
			},
			{
				name:    "INTEGRATION_TEST_REPO",
				desc:    "target test repository (e.g. your-org/your-repo)",
				present: func() bool { return repoFlag != "" || os.Getenv("INTEGRATION_TEST_REPO") != "" },
			},
		}
	case "bitbucket":
		reqs = []requirement{
			{
				name:    "BB_TOKEN",
				desc:    "Bitbucket repository access token",
				present: func() bool { return os.Getenv("BB_TOKEN") != "" },
			},
			{
				name:    "BB_WORKSPACE",
				desc:    "Bitbucket workspace slug",
				present: func() bool { return os.Getenv("BB_WORKSPACE") != "" },
			},
			{
				name:    "BB_REPO",
				desc:    "Bitbucket repository slug",
				present: func() bool { return os.Getenv("BB_REPO") != "" },
			},
		}
	}

	var missing []requirement
	for _, r := range reqs {
		if !r.present() {
			missing = append(missing, r)
		}
	}

	if len(missing) == 0 {
		return
	}

	fmt.Fprintln(os.Stderr, "ERROR: missing required environment variables:")
	for _, r := range missing {
		fmt.Fprintf(os.Stderr, "  %-30s — %s\n", r.name, r.desc)
	}
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "Set these in tests/integration-go/.env.local (gitignored) and run:")
	fmt.Fprintln(os.Stderr, "  source tests/integration-go/.env.local && go run ./tests/integration-go/cmd/...")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "See tests/integration-go/.env.example for the full variable list.")
	os.Exit(1)
}

func buildDriver(platform, repoOverride string) (core.PlatformDriver, error) {
	switch platform {
	case "github":
		token := os.Getenv("INTEGRATION_TEST_TOKEN")
		repo := repoOverride
		if repo == "" {
			repo = os.Getenv("INTEGRATION_TEST_REPO")
		}
		c, err := ghAdapter.NewClient(token, repo)
		if err != nil {
			return nil, fmt.Errorf("github client: %w", err)
		}
		return ghAdapter.NewDriver(c), nil

	case "bitbucket":
		token := os.Getenv("BB_TOKEN")
		workspace := os.Getenv("BB_WORKSPACE")
		bbRepo := os.Getenv("BB_REPO")
		c := bitbucket.NewClient(token, workspace, bbRepo)
		return bitbucket.NewDriver(c), nil

	default:
		return nil, fmt.Errorf("unknown platform %q (use github or bitbucket)", platform)
	}
}

func scenariosFilePath(flagVal string) string {
	if flagVal != "" {
		return flagVal
	}
	if p := os.Getenv("SCENARIOS_FILE"); p != "" {
		return p
	}
	return filepath.Join("tests", "integration-go", "scenarios", "test-scenarios.yml")
}

func envOrRandom(key string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return randomHex8()
}

func randomHex8() string {
	f, err := os.Open("/dev/urandom")
	if err != nil {
		return "deadbeef"
	}
	defer func() { _ = f.Close() }()
	b := make([]byte, 4)
	_, _ = f.Read(b)
	return fmt.Sprintf("%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
}

func fatalf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "error: "+format+"\n", args...)
	os.Exit(1)
}
