package core

import (
	"context"
	"fmt"
	"runtime"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

// RunOptions configures the runner.
type RunOptions struct {
	Platform    string
	Filter      string
	Parallelism int
	Timeout     time.Duration
	FailFast    bool
	RunID       string
	ImageTag    string
}

// Runner orchestrates scenario execution.
type Runner struct {
	driver PlatformDriver
	pool   *SandboxPool
	opts   RunOptions
}

// NewRunner creates a runner with the given driver and options.
func NewRunner(driver PlatformDriver, pool *SandboxPool, opts RunOptions) *Runner {
	return &Runner{driver: driver, pool: pool, opts: opts}
}

// Run executes all matching scenarios and returns results.
func (r *Runner) Run(ctx context.Context, scenarios []Scenario) []ScenarioResult {
	filtered := r.filterScenarios(scenarios)

	merge := make([]Scenario, 0)
	noMerge := make([]Scenario, 0)
	for _, s := range filtered {
		if s.IsMergeScenario() {
			merge = append(merge, s)
		} else {
			noMerge = append(noMerge, s)
		}
	}

	results := make([]ScenarioResult, 0, len(filtered))
	var mu sync.Mutex

	collect := func(res ScenarioResult) bool {
		mu.Lock()
		results = append(results, res)
		mu.Unlock()
		if r.opts.FailFast && !res.Passed {
			return false
		}
		return true
	}

	// Run no-merge scenarios in parallel.
	// Concurrency: opts.Parallelism (default runtime.NumCPU).
	// No sandbox needed — scenarios target main and never merge.
	if len(noMerge) > 0 {
		p := r.opts.Parallelism
		if p <= 0 {
			p = runtime.NumCPU()
		}
		r.runParallel(ctx, noMerge, p, false, collect)
	}

	// Run merge scenarios in parallel.
	// SandboxPool is the sole concurrency control — no additional semaphore.
	// Each goroutine blocks only if its sandbox is already in use (rare in practice:
	// each scenario maps to its own sandbox-N).
	if len(merge) > 0 {
		r.runParallel(ctx, merge, len(merge), true, collect)
	}

	return results
}

func (r *Runner) filterScenarios(scenarios []Scenario) []Scenario {
	if r.opts.Filter == "" {
		return scenarios
	}
	out := make([]Scenario, 0)
	for _, s := range scenarios {
		if strings.Contains(s.Name, r.opts.Filter) {
			out = append(out, s)
		}
	}
	return out
}

// runParallel dispatches scenarios into a goroutine pool of size concurrency.
// If useSandbox is true, each goroutine acquires the SandboxPool before running.
func (r *Runner) runParallel(ctx context.Context, scenarios []Scenario, concurrency int, useSandbox bool, collect func(ScenarioResult) bool) {
	sem := make(chan struct{}, concurrency)
	var wg sync.WaitGroup
	stop := false
	for _, s := range scenarios {
		if stop {
			break
		}
		wg.Add(1)
		go func(sc Scenario) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if useSandbox {
				sandbox := sc.EffectiveBase()
				r.pool.Acquire(sandbox)
				defer r.pool.Release(sandbox)
			}
			res := r.runScenario(ctx, sc)
			if !collect(res) {
				stop = true
			}
		}(s)
	}
	wg.Wait()
}

func (r *Runner) runScenario(ctx context.Context, s Scenario) ScenarioResult {
	start := time.Now()
	tag, err := r.execScenario(ctx, s)
	return ScenarioResult{
		Scenario:   s.Name,
		Platform:   r.opts.Platform,
		Passed:     err == nil,
		Error:      err,
		Duration:   time.Since(start),
		CreatedTag: tag,
	}
}

func (r *Runner) execScenario(ctx context.Context, s Scenario) (createdTag string, retErr error) {
	base := s.EffectiveBase()
	branch := fmt.Sprintf("%s-%s-%s", s.EffectiveBranchPrefix(), s.Name, r.opts.RunID)
	prTitle := s.EffectivePRTitle()
	timeout := r.opts.Timeout
	if timeout <= 0 {
		timeout = 5 * time.Minute
	}

	var (
		prHandle   *PRHandle
		seededTags []string
		tagBefore  *string
	)

	defer func() {
		// Cleanup in reverse setup order — best effort, errors logged not returned
		if prHandle != nil {
			if err := r.driver.ClosePR(*prHandle); err != nil {
				fmt.Printf("  [cleanup] close PR: %v\n", err)
			}
		}
		if err := r.driver.DeleteBranch(branch); err != nil {
			fmt.Printf("  [cleanup] delete branch %s: %v\n", branch, err)
		}
		for _, tag := range seededTags {
			if err := r.driver.DeleteTag(tag); err != nil {
				fmt.Printf("  [cleanup] delete seed tag %s: %v\n", tag, err)
			}
		}
		if createdTag != "" {
			if err := r.driver.DeleteTag(createdTag); err != nil {
				fmt.Printf("  [cleanup] delete created tag %s: %v\n", createdTag, err)
			}
		} else if s.Expected.TagCreated {
			// Pipe may have created a tag before the test failed
			latest, _ := r.driver.GetLatestTag(s.TagPrefix())
			if latest != nil && (tagBefore == nil || *latest != *tagBefore) {
				_ = r.driver.DeleteTag(*latest)
			}
		}
	}()

	// 1. Seed tags
	for _, tagName := range s.SeedTags {
		if err := r.driver.CreateTag(tagName, base); err != nil {
			return "", fmt.Errorf("seed tag %s: %w", tagName, err)
		}
		seededTags = append(seededTags, tagName)
	}

	// 2. Snapshot latest tag (for diff detection later)
	latest, err := r.driver.GetLatestTag(s.TagPrefix())
	if err != nil {
		return "", fmt.Errorf("get latest tag before test: %w", err)
	}
	tagBefore = latest

	// 3. Create test branch
	if err := r.driver.CreateBranch(branch, base); err != nil {
		return "", fmt.Errorf("create branch: %w", err)
	}

	// 4. Apply commits (with config_override injected into first commit)
	configOverride := s.ConfigOverride
	for idx, commit := range s.Commits {
		files := make(map[string]string)
		for k, v := range commit.Files {
			files[k] = v + "\n# run:" + r.opts.RunID
		}
		if len(files) == 0 {
			files["test-artifact.txt"] = "test\n# run:" + r.opts.RunID
		}

		if idx == 0 && len(configOverride) > 0 {
			raw, err := r.driver.GetFileContent(".versioning.yml", base)
			if err != nil {
				return "", fmt.Errorf("get .versioning.yml: %w", err)
			}
			var baseCfg map[string]interface{}
			if raw != nil {
				if err := yaml.Unmarshal(raw, &baseCfg); err != nil {
					return "", fmt.Errorf("parse .versioning.yml: %w", err)
				}
			}
			merged := deepMerge(baseCfg, configOverride)
			out, err := yaml.Marshal(merged)
			if err != nil {
				return "", fmt.Errorf("marshal merged config: %w", err)
			}
			files[".versioning.yml"] = string(out)
		}

		if _, err := r.driver.CreateCommit(branch, commit.Message, files); err != nil {
			return "", fmt.Errorf("create commit %d: %w", idx, err)
		}
	}

	// 5. Create PR
	pr, err := r.driver.CreatePR(branch, base, prTitle)
	if err != nil {
		return "", fmt.Errorf("create PR: %w", err)
	}
	prHandle = &pr

	// 6. Wait for checks
	checkResult, err := r.driver.WaitForChecks(pr, timeout)
	if err != nil {
		return "", fmt.Errorf("wait for checks: %w", err)
	}
	if err := AssertPRCheck(checkResult, s.Expected.PRCheck); err != nil {
		return "", err
	}

	// 7. If no merge needed, we're done
	if !s.IsMergeScenario() {
		return "", nil
	}

	// 8. Snapshot before merge
	prevRunID, err := r.driver.GetLatestWorkflowRunID(base)
	if err != nil {
		return "", fmt.Errorf("get workflow run id before merge: %w", err)
	}

	// 9. Merge PR
	method := s.EffectiveMergeMethod()
	if err := r.driver.MergePR(pr, method, s.MergeSubject); err != nil {
		return "", fmt.Errorf("merge PR: %w", err)
	}
	prHandle = nil // merged, no need to close

	// 10. Wait for post-merge workflow
	newRunID, err := r.driver.WaitForNewWorkflowRun(base, prevRunID, 45*time.Second)
	if err != nil || newRunID == nil {
		// fallback: dispatch manually
		if dispErr := r.driver.DispatchWorkflow(base, r.opts.ImageTag); dispErr != nil {
			return "", fmt.Errorf("dispatch workflow fallback: %w", dispErr)
		}
		newRunID, err = r.driver.WaitForNewWorkflowRun(base, prevRunID, 30*time.Second)
		if err != nil || newRunID == nil {
			return "", fmt.Errorf("workflow run never appeared")
		}
	}

	ok, err := r.driver.WaitForWorkflowRunCompletion(*newRunID, timeout)
	if err != nil {
		return "", fmt.Errorf("wait for workflow completion: %w", err)
	}
	if !ok {
		return "", fmt.Errorf("post-merge workflow failed (run %d)", *newRunID)
	}

	// 11. Assert tag
	tag, err := AssertTagCreated(r.driver, s, tagBefore, timeout)
	if err != nil {
		return "", err
	}
	createdTag = tag

	if tag != "" && s.Expected.TagPattern != "" {
		if err := AssertTagPattern(tag, s.Expected.TagPattern); err != nil {
			return tag, err
		}
	}

	// 12. Assert changelog
	changelogPath := s.Expected.ChangelogLocation
	if changelogPath == "" {
		changelogPath = "CHANGELOG.md"
	}

	if s.Expected.ChangelogContains != "" {
		if err := AssertChangelogContains(r.driver, changelogPath, base, s.Expected.ChangelogContains); err != nil {
			return tag, err
		}
	}
	for _, loc := range s.Expected.ChangelogLocations {
		if err := AssertChangelogContains(r.driver, loc, base, s.Expected.ChangelogContains); err != nil {
			return tag, err
		}
	}
	if len(s.Expected.ChangelogNotLocations) > 0 {
		if err := AssertChangelogNotIn(r.driver, s.Expected.ChangelogNotLocations, base, s.Expected.ChangelogContains); err != nil {
			return tag, err
		}
	}
	if s.Expected.ChangelogSectionMarker != "" {
		if err := AssertChangelogSectionMarker(r.driver, changelogPath, base, s.Expected.ChangelogSectionMarker); err != nil {
			return tag, err
		}
	}

	// 13. Assert version file
	if s.Expected.VersionFilePath != "" {
		if err := AssertVersionFile(r.driver, s.Expected.VersionFilePath, base, tag, s.Expected.VersionFileUpdated); err != nil {
			return tag, err
		}
	}

	return tag, nil
}

// deepMerge recursively merges override into base. Override wins on conflicts.
func deepMerge(base, override map[string]interface{}) map[string]interface{} {
	result := make(map[string]interface{})
	for k, v := range base {
		result[k] = v
	}
	for k, v := range override {
		if bv, ok := result[k]; ok {
			if bMap, ok := bv.(map[string]interface{}); ok {
				if oMap, ok := v.(map[string]interface{}); ok {
					result[k] = deepMerge(bMap, oMap)
					continue
				}
			}
		}
		result[k] = v
	}
	return result
}
