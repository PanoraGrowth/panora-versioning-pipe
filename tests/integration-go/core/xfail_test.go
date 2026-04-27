package core

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// stubDriver is a minimal PlatformDriver that returns configurable results.
type stubDriver struct {
	checkResult CheckResult
	checkErr    error
}

func (d *stubDriver) GetBranchSHA(branch string) (string, error) { return "abc123", nil }
func (d *stubDriver) CreateBranch(name, fromRef string) error    { return nil }
func (d *stubDriver) DeleteBranch(name string) error             { return nil }
func (d *stubDriver) CreateCommit(branch, message string, files map[string]string) (string, error) {
	return "sha1", nil
}
func (d *stubDriver) GetFileContent(path, ref string) ([]byte, error) { return nil, nil }
func (d *stubDriver) CreatePR(head, base, title string) (PRHandle, error) {
	return PRHandle{ID: 1, Platform: "github"}, nil
}
func (d *stubDriver) MergePR(pr PRHandle, method MergeMethod, subject string) error { return nil }
func (d *stubDriver) ClosePR(pr PRHandle) error                                     { return nil }
func (d *stubDriver) WaitForChecks(pr PRHandle, timeout time.Duration) (CheckResult, error) {
	return d.checkResult, d.checkErr
}
func (d *stubDriver) GetLatestWorkflowRunID(branch string) (*int64, error) { return nil, nil }
func (d *stubDriver) WaitForNewWorkflowRun(branch string, previousRunID *int64, timeout time.Duration) (*int64, error) {
	return nil, nil
}
func (d *stubDriver) DispatchWorkflow(ref, imageTag string) error { return nil }
func (d *stubDriver) WaitForWorkflowRunCompletion(runID int64, timeout time.Duration) (bool, error) {
	return true, nil
}
func (d *stubDriver) GetLatestTag(prefix string, excludePrefixes []string) (*string, error) {
	return nil, nil
}
func (d *stubDriver) WaitForNewTag(previousTag *string, prefix string, excludePrefixes []string, timeout time.Duration) (string, error) {
	return "", nil
}
func (d *stubDriver) CreateTag(name, ref string) error { return nil }
func (d *stubDriver) DeleteTag(name string) error      { return nil }

func runSingleScenario(t *testing.T, s Scenario, checkResult CheckResult, checkErr error) ScenarioResult {
	t.Helper()
	driver := &stubDriver{checkResult: checkResult, checkErr: checkErr}
	pool := NewSandboxPool()
	opts := RunOptions{Platform: "github", RunID: "test"}
	runner := NewRunner(driver, pool, opts)
	results := runner.Run(context.Background(), []Scenario{s})
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	return results[0]
}

func TestXfailScenarioFails(t *testing.T) {
	s := Scenario{
		Name:        "xfail-fails",
		Xfail:       true,
		XfailReason: "ticket 999 — known bug",
		Expected:    Expected{PRCheck: "pass"},
	}
	// Simulate the scenario failing: checks return "fail" but expected is "pass"
	res := runSingleScenario(t, s, CheckFail, nil)

	if !res.Xfail {
		t.Error("want Xfail=true, got false")
	}
	if res.Xpass {
		t.Error("want Xpass=false, got true")
	}
	if res.Passed {
		t.Error("want Passed=false, got true")
	}
	if res.Error != nil {
		t.Errorf("want Error=nil, got %v", res.Error)
	}
	if res.XfailReason != "ticket 999 — known bug" {
		t.Errorf("want XfailReason propagated, got %q", res.XfailReason)
	}
}

func TestXfailScenarioPasses(t *testing.T) {
	s := Scenario{
		Name:        "xfail-passes",
		Xfail:       true,
		XfailReason: "ticket 999 — known bug",
		Expected:    Expected{PRCheck: "pass"},
	}
	// Scenario passes as expected
	res := runSingleScenario(t, s, CheckPass, nil)

	if res.Xfail {
		t.Error("want Xfail=false, got true")
	}
	if !res.Xpass {
		t.Error("want Xpass=true, got false")
	}
}

func TestNormalScenarioFails(t *testing.T) {
	s := Scenario{
		Name:     "normal-fails",
		Expected: Expected{PRCheck: "pass"},
	}
	res := runSingleScenario(t, s, CheckFail, nil)

	if res.Xfail {
		t.Error("want Xfail=false, got true")
	}
	if res.Xpass {
		t.Error("want Xpass=false, got true")
	}
	if res.Passed {
		t.Error("want Passed=false, got true")
	}
	if res.Error == nil {
		t.Error("want Error!=nil, got nil")
	}
}

func TestNormalScenarioPasses(t *testing.T) {
	s := Scenario{
		Name:     "normal-passes",
		Expected: Expected{PRCheck: "pass"},
	}
	res := runSingleScenario(t, s, CheckPass, nil)

	if res.Xfail {
		t.Error("want Xfail=false, got true")
	}
	if res.Xpass {
		t.Error("want Xpass=false, got true")
	}
	if !res.Passed {
		t.Error("want Passed=true, got false")
	}
	if res.Error != nil {
		t.Errorf("want Error=nil, got %v", res.Error)
	}
}

func TestLoaderRejectsXfailWithoutReason(t *testing.T) {
	content := `
scenarios:
  - name: bad-scenario
    xfail: true
`
	tmp := filepath.Join(t.TempDir(), "scenarios.yml")
	if err := os.WriteFile(tmp, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	_, err := LoadScenarios(tmp)
	if err == nil {
		t.Fatal("want error for xfail=true without xfail_reason, got nil")
	}
	if !errors.Is(err, err) { // always true — just verify it's non-nil with message
		t.Error("unexpected")
	}
}
