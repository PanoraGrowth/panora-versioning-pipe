package core

import "time"

// PlatformDriver abstracts platform-specific operations for the test runner.
// Adapters implement this; the core never imports adapter packages.
type PlatformDriver interface {
	// Branch
	GetBranchSHA(branch string) (string, error)
	CreateBranch(name, fromRef string) error
	DeleteBranch(name string) error

	// Commits
	CreateCommit(branch, message string, files map[string]string) (string, error)
	GetFileContent(path, ref string) ([]byte, error)

	// Pull Requests
	CreatePR(head, base, title string) (PRHandle, error)
	MergePR(pr PRHandle, method MergeMethod, subject string) error
	ClosePR(pr PRHandle) error

	// Checks / pipeline
	WaitForChecks(pr PRHandle, timeout time.Duration) (CheckResult, error)

	// Workflow (GitHub Actions / Bitbucket Pipelines)
	GetLatestWorkflowRunID(branch string) (*int64, error)
	WaitForNewWorkflowRun(branch string, previousRunID *int64, timeout time.Duration) (*int64, error)
	DispatchWorkflow(ref, imageTag string) error
	WaitForWorkflowRunCompletion(runID int64, timeout time.Duration) (bool, error)

	// Tags
	//
	// excludePrefixes lists tag prefixes that are sub-namespaces of prefix and must be
	// excluded from results to avoid cross-contamination between parallel scenarios.
	// Example: GetLatestTag("v1.", ["v1.27."]) returns only v1.NNN tags, not v1.27.NNN.
	// Computed once per Run() by computeExcludesByPrefix — callers don't build this manually.
	GetLatestTag(prefix string, excludePrefixes []string) (*string, error)
	WaitForNewTag(previousTag *string, prefix string, excludePrefixes []string, timeout time.Duration) (string, error)
	CreateTag(name, ref string) error
	DeleteTag(name string) error
}

// PRHandle is an opaque PR identifier.
type PRHandle struct {
	ID       int64
	Platform string // "github" | "bitbucket"
}

// MergeMethod represents the merge strategy.
type MergeMethod string

const (
	MergeMethodSquash MergeMethod = "squash"
	MergeMethodMerge  MergeMethod = "merge"
)

// CheckResult is the outcome of PR checks.
type CheckResult string

const (
	CheckPass CheckResult = "pass"
	CheckFail CheckResult = "fail"
)

// ScenarioResult holds the outcome of a single scenario execution.
type ScenarioResult struct {
	Scenario    string
	Platform    string
	Passed      bool
	Error       error
	Duration    time.Duration
	CreatedTag  string
	Skipped     bool
	SkipReason  string
	Xfail       bool   // scenario marked xfail and failed as expected
	Xpass       bool   // scenario marked xfail but passed unexpectedly
	XfailReason string // reason string from the scenario YAML (for output)
}
