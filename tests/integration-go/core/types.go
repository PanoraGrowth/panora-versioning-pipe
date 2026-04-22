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
	GetLatestTag(prefix string) (*string, error)
	WaitForNewTag(previousTag *string, prefix string, timeout time.Duration) (string, error)
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
	Scenario   string
	Platform   string
	Passed     bool
	Error      error
	Duration   time.Duration
	CreatedTag string
}
