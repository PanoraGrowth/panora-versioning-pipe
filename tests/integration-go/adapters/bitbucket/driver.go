package bitbucket

import (
	"errors"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/core"
)

// ErrNotImplemented is returned by all Bitbucket driver methods until T3.
var ErrNotImplemented = errors.New("bitbucket adapter not implemented (T3)")

// Driver implements core.PlatformDriver for Bitbucket.
// Stub in T2 — all methods return ErrNotImplemented.
type Driver struct {
	c *Client
}

// NewDriver creates a Bitbucket driver stub.
func NewDriver(c *Client) *Driver {
	return &Driver{c: c}
}

func (d *Driver) GetBranchSHA(branch string) (string, error) {
	return "", ErrNotImplemented
}

func (d *Driver) CreateBranch(name, fromRef string) error {
	return ErrNotImplemented
}

func (d *Driver) DeleteBranch(name string) error {
	return ErrNotImplemented
}

func (d *Driver) CreateCommit(branch, message string, files map[string]string) (string, error) {
	return "", ErrNotImplemented
}

func (d *Driver) GetFileContent(path, ref string) ([]byte, error) {
	return nil, ErrNotImplemented
}

func (d *Driver) CreatePR(head, base, title string) (core.PRHandle, error) {
	return core.PRHandle{}, ErrNotImplemented
}

func (d *Driver) MergePR(pr core.PRHandle, method core.MergeMethod, subject string) error {
	return ErrNotImplemented
}

func (d *Driver) ClosePR(pr core.PRHandle) error {
	return ErrNotImplemented
}

func (d *Driver) WaitForChecks(pr core.PRHandle, timeout time.Duration) (core.CheckResult, error) {
	return "", ErrNotImplemented
}

func (d *Driver) GetLatestWorkflowRunID(branch string) (*int64, error) {
	return nil, ErrNotImplemented
}

func (d *Driver) WaitForNewWorkflowRun(branch string, previousRunID *int64, timeout time.Duration) (*int64, error) {
	return nil, ErrNotImplemented
}

func (d *Driver) DispatchWorkflow(ref, imageTag string) error {
	return ErrNotImplemented
}

func (d *Driver) WaitForWorkflowRunCompletion(runID int64, timeout time.Duration) (bool, error) {
	return false, ErrNotImplemented
}

func (d *Driver) GetLatestTag(prefix string) (*string, error) {
	return nil, ErrNotImplemented
}

func (d *Driver) WaitForNewTag(previousTag *string, prefix string, timeout time.Duration) (string, error) {
	return "", ErrNotImplemented
}

func (d *Driver) CreateTag(name, ref string) error {
	return ErrNotImplemented
}

func (d *Driver) DeleteTag(name string) error {
	return ErrNotImplemented
}
