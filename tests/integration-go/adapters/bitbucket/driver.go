package bitbucket

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	semver "github.com/Masterminds/semver/v3"

	"github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/core"
)

const (
	defaultPollInterval = 10 * time.Second
)

// Driver implements core.PlatformDriver for Bitbucket using REST API v2.0.
//
// UUID ↔ int64 mapping (strategy A):
// Bitbucket pipeline runs are identified by UUIDs (string), but PlatformDriver
// uses *int64 run IDs. We maintain an internal counter + map to translate between
// the two. A monotonic int64 counter is assigned to each new UUID seen; the map
// is the authoritative lookup in both directions.
//
// why: Strategy A (explicit map) was chosen over B (FNV hash) because hash
// collisions, while improbable, would silently produce incorrect behavior in
// WaitForNewWorkflowRun. The map has zero collision risk at the cost of a small
// per-driver allocation. The mutex ensures goroutine safety for parallel scenarios.
type Driver struct {
	c            *Client
	pollInterval time.Duration // configurable for testing; defaults to defaultPollInterval

	// uuid<->int64 mapping for pipeline run IDs
	mu      sync.Mutex
	uuidMap map[string]int64 // uuid → local int64 ID
	idMap   map[int64]string // local int64 ID → uuid
	counter int64            // monotonic counter, incremented via atomic
}

// NewDriver creates a Bitbucket driver.
func NewDriver(c *Client) *Driver {
	return &Driver{
		c:            c,
		pollInterval: defaultPollInterval,
		uuidMap:      make(map[string]int64),
		idMap:        make(map[int64]string),
	}
}

// newDriverWithPollInterval creates a driver with a custom poll interval.
// Only used in tests — allows fast polling without mocking time.Now().
func newDriverWithPollInterval(c *Client, interval time.Duration) *Driver {
	d := NewDriver(c)
	d.pollInterval = interval
	return d
}

// uuidToID maps a Bitbucket pipeline UUID to a local int64 ID.
// If the UUID has been seen before, returns the same ID. Otherwise assigns a new one.
func (d *Driver) uuidToID(uuid string) int64 {
	d.mu.Lock()
	defer d.mu.Unlock()
	if id, ok := d.uuidMap[uuid]; ok {
		return id
	}
	id := atomic.AddInt64(&d.counter, 1)
	d.uuidMap[uuid] = id
	d.idMap[id] = uuid
	return id
}

// idToUUID resolves a local int64 ID back to a Bitbucket pipeline UUID.
func (d *Driver) idToUUID(id int64) (string, bool) {
	d.mu.Lock()
	defer d.mu.Unlock()
	uuid, ok := d.idMap[id]
	return uuid, ok
}

// --- Branch ---

func (d *Driver) GetBranchSHA(branch string) (string, error) {
	var resp struct {
		Target struct {
			Hash string `json:"hash"`
		} `json:"target"`
	}
	if err := d.c.get("refs/branches/"+branch, &resp); err != nil {
		return "", fmt.Errorf("GetBranchSHA %s: %w", branch, err)
	}
	return resp.Target.Hash, nil
}

func (d *Driver) CreateBranch(name, fromRef string) error {
	sha, err := d.GetBranchSHA(fromRef)
	if err != nil {
		return err
	}
	body := map[string]interface{}{
		"name":   name,
		"target": map[string]string{"hash": sha},
	}
	if err := d.c.post("refs/branches", body, nil); err != nil {
		return fmt.Errorf("CreateBranch %s: %w", name, err)
	}
	return nil
}

func (d *Driver) DeleteBranch(name string) error {
	if err := d.c.delete("refs/branches/" + name); err != nil {
		return fmt.Errorf("DeleteBranch %s: %w", name, err)
	}
	return nil
}

// --- Commits ---

// CreateCommit creates a commit on the given branch using the Bitbucket /src endpoint.
// The /src endpoint accepts multipart form data: each file path is a form field with
// content as value. The commit SHA is read back from GET /refs/branches/{branch}
// because the /src endpoint responds with a 201 redirect, not a JSON body with SHA.
func (d *Driver) CreateCommit(branch, message string, files map[string]string) (string, error) {
	fields := map[string]string{
		"message": message,
		"branch":  branch,
	}
	for path, content := range files {
		fields[path] = content
	}

	if err := d.c.postForm("src", fields, nil); err != nil {
		return "", fmt.Errorf("CreateCommit on %s: %w", branch, err)
	}

	// Read SHA from branch tip (POST /src does not return JSON with the new commit SHA)
	sha, err := d.GetBranchSHA(branch)
	if err != nil {
		return "", fmt.Errorf("get commit SHA after CreateCommit: %w", err)
	}
	return sha, nil
}

func (d *Driver) GetFileContent(path, ref string) ([]byte, error) {
	raw, err := d.c.getRaw("src/" + ref + "/" + path)
	if err != nil {
		return nil, fmt.Errorf("GetFileContent %s@%s: %w", path, ref, err)
	}
	return raw, nil
}

// --- Pull Requests ---

func (d *Driver) CreatePR(head, base, title string) (core.PRHandle, error) {
	body := map[string]interface{}{
		"title":               title,
		"source":              map[string]interface{}{"branch": map[string]string{"name": head}},
		"destination":         map[string]interface{}{"branch": map[string]string{"name": base}},
		"close_source_branch": false,
	}
	var resp struct {
		ID int64 `json:"id"`
	}
	if err := d.c.post("pullrequests", body, &resp); err != nil {
		return core.PRHandle{}, fmt.Errorf("CreatePR: %w", err)
	}
	return core.PRHandle{ID: resp.ID, Platform: "bitbucket"}, nil
}

func (d *Driver) MergePR(pr core.PRHandle, method core.MergeMethod, subject string) error {
	strategyMap := map[core.MergeMethod]string{
		core.MergeMethodSquash: "squash",
		core.MergeMethodMerge:  "merge_commit",
	}
	strategy, ok := strategyMap[method]
	if !ok {
		strategy = "squash"
	}
	body := map[string]interface{}{
		"merge_strategy":      strategy,
		"close_source_branch": false,
	}
	if subject != "" {
		body["message"] = subject
	}
	if err := d.c.post(fmt.Sprintf("pullrequests/%d/merge", pr.ID), body, nil); err != nil {
		return fmt.Errorf("MergePR %d: %w", pr.ID, err)
	}
	return nil
}

func (d *Driver) ClosePR(pr core.PRHandle) error {
	// why: best-effort cleanup — no retries, no error propagation.
	// A failed decline is harmless; the PR remains open but the test branch will be deleted.
	_ = d.c.postNoRetry(fmt.Sprintf("pullrequests/%d/decline", pr.ID), map[string]interface{}{})
	return nil
}

// --- Checks / pipeline ---

// WaitForChecks polls PR build statuses until all are in a terminal state.
// Terminal states: SUCCESSFUL, FAILED, STOPPED.
// Returns CheckPass only if all statuses are SUCCESSFUL.
func (d *Driver) WaitForChecks(pr core.PRHandle, timeout time.Duration) (core.CheckResult, error) {
	type statusValue struct {
		State string `json:"state"`
	}
	type statusPage struct {
		Values []statusValue `json:"values"`
	}

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		var page statusPage
		if err := d.c.get(fmt.Sprintf("pullrequests/%d/statuses", pr.ID), &page); err != nil {
			time.Sleep(d.pollInterval)
			continue
		}

		if len(page.Values) == 0 {
			time.Sleep(d.pollInterval)
			continue
		}

		allTerminal := true
		allPass := true
		for _, s := range page.Values {
			switch s.State {
			case "SUCCESSFUL", "FAILED", "STOPPED":
				// terminal
			default:
				allTerminal = false
			}
			if s.State != "SUCCESSFUL" {
				allPass = false
			}
		}

		if !allTerminal {
			time.Sleep(d.pollInterval)
			continue
		}
		if allPass {
			return core.CheckPass, nil
		}
		return core.CheckFail, nil
	}
	return "", fmt.Errorf("PR %d checks did not complete within %s", pr.ID, timeout)
}

// --- Workflow (Bitbucket Pipelines) ---

type pipelineState struct {
	Name   string `json:"name"`
	Result struct {
		Name string `json:"name"`
	} `json:"result"`
}

type pipeline struct {
	UUID   string        `json:"uuid"`
	State  pipelineState `json:"state"`
	Target struct {
		RefName string `json:"ref_name"`
	} `json:"target"`
}

type pipelinePage struct {
	Values []pipeline `json:"values"`
}

// GetLatestWorkflowRunID returns the int64 ID of the latest pipeline run on the branch.
// Nil if no runs exist. The int64 is a local mapping — see Driver doc comment for rationale.
func (d *Driver) GetLatestWorkflowRunID(branch string) (*int64, error) {
	var page pipelinePage
	path := fmt.Sprintf("pipelines/?sort=-created_on&pagelen=1&target.ref_name=%s", branch)
	if err := d.c.get(path, &page); err != nil {
		return nil, fmt.Errorf("GetLatestWorkflowRunID %s: %w", branch, err)
	}
	if len(page.Values) == 0 {
		return nil, nil
	}
	id := d.uuidToID(page.Values[0].UUID)
	return &id, nil
}

// WaitForNewWorkflowRun polls until a pipeline run newer than previousRunID appears on branch.
// Returns nil if timeout expires (caller falls back to DispatchWorkflow).
func (d *Driver) WaitForNewWorkflowRun(branch string, previousRunID *int64, timeout time.Duration) (*int64, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		current, err := d.GetLatestWorkflowRunID(branch)
		if err != nil {
			time.Sleep(d.pollInterval)
			continue
		}
		if current != nil && (previousRunID == nil || *current != *previousRunID) {
			return current, nil
		}
		time.Sleep(d.pollInterval)
	}
	return nil, nil
}

// DispatchWorkflow triggers a Bitbucket Pipeline manually on the given ref.
// Uses the "default" pipeline selector. Returns an actionable error if dispatch fails.
func (d *Driver) DispatchWorkflow(ref, imageTag string) error {
	body := map[string]interface{}{
		"target": map[string]interface{}{
			"type":     "pipeline_ref_target",
			"ref_type": "branch",
			"ref_name": ref,
			"selector": map[string]string{
				"type":    "custom",
				"pattern": "default",
			},
		},
	}
	if err := d.c.post("pipelines/", body, nil); err != nil {
		return fmt.Errorf("DispatchWorkflow on %s: %w — ensure a custom pipeline named 'default' exists in bitbucket-pipelines.yml", ref, err)
	}
	return nil
}

// WaitForWorkflowRunCompletion polls GET /pipelines/{uuid} until state.name == "COMPLETED".
// Returns true if result.name == "SUCCESSFUL".
func (d *Driver) WaitForWorkflowRunCompletion(runID int64, timeout time.Duration) (bool, error) {
	uuid, ok := d.idToUUID(runID)
	if !ok {
		return false, fmt.Errorf("WaitForWorkflowRunCompletion: unknown run ID %d (not tracked in this session)", runID)
	}

	// why: UUID from Bitbucket API contains curly braces e.g. "{uuid-here}".
	// The endpoint expects the UUID without braces when used as a path segment.
	cleanUUID := cleanBitbucketUUID(uuid)

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		var p pipeline
		if err := d.c.get("pipelines/"+cleanUUID, &p); err != nil {
			time.Sleep(d.pollInterval)
			continue
		}
		if p.State.Name == "COMPLETED" {
			return p.State.Result.Name == "SUCCESSFUL", nil
		}
		time.Sleep(d.pollInterval)
	}
	return false, fmt.Errorf("pipeline run %d did not complete within %s", runID, timeout)
}

// --- Tags ---

func (d *Driver) GetLatestTag(prefix string, excludePrefixes []string) (*string, error) {
	path := "refs/tags?sort=-target.date&pagelen=25"
	if prefix != "" {
		// why: Bitbucket supports q= filter for field matching. name~ means "starts with"
		// in Bitbucket query syntax (it's actually substring, but prefix works in practice
		// because tag names are versioned and the prefix is always "vN.").
		path = fmt.Sprintf(`refs/tags?sort=-target.date&pagelen=25&q=name~"%s"`, prefix)
	}

	var resp struct {
		Values []struct {
			Name string `json:"name"`
		} `json:"values"`
	}
	if err := d.c.get(path, &resp); err != nil {
		return nil, fmt.Errorf("GetLatestTag (prefix=%s): %w", prefix, err)
	}
	if len(resp.Values) == 0 {
		return nil, nil
	}

	// Sort by semver descending — same logic as GitHub driver.
	// Exclude tags belonging to more-specific sub-namespaces (cross-contamination guard).
	names := make([]string, 0, len(resp.Values))
	for _, v := range resp.Values {
		if hasExcludedPrefix(v.Name, excludePrefixes) {
			continue
		}
		names = append(names, v.Name)
	}
	if len(names) == 0 {
		return nil, nil
	}
	sort.Slice(names, func(i, j int) bool {
		vi, ei := semver.NewVersion(names[i])
		vj, ej := semver.NewVersion(names[j])
		if ei != nil || ej != nil {
			return names[i] > names[j]
		}
		return vi.GreaterThan(vj)
	})
	return &names[0], nil
}

func (d *Driver) WaitForNewTag(previousTag *string, prefix string, excludePrefixes []string, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		current, err := d.GetLatestTag(prefix, excludePrefixes)
		if err != nil {
			time.Sleep(d.pollInterval)
			continue
		}
		if current != nil && (previousTag == nil || *current != *previousTag) {
			return *current, nil
		}
		time.Sleep(d.pollInterval)
	}
	prev := "<none>"
	if previousTag != nil {
		prev = *previousTag
	}
	return "", fmt.Errorf("no new tag (prefix=%s) appeared within %s; last: %s", prefix, timeout, prev)
}

// hasExcludedPrefix reports whether name starts with any of the excludePrefixes.
// Mirrors the same helper in the GitHub driver — both drivers need identical filtering semantics.
func hasExcludedPrefix(name string, excludePrefixes []string) bool {
	for _, ex := range excludePrefixes {
		if strings.HasPrefix(name, ex) {
			return true
		}
	}
	return false
}

// CreateTag creates a lightweight tag pointing to the tip of the given ref.
// The ref is resolved to a SHA first via GetBranchSHA.
func (d *Driver) CreateTag(name, ref string) error {
	sha, err := d.GetBranchSHA(ref)
	if err != nil {
		return err
	}
	body := map[string]interface{}{
		"name":   name,
		"target": map[string]string{"hash": sha},
	}
	if err := d.c.post("refs/tags", body, nil); err != nil {
		return fmt.Errorf("CreateTag %s: %w", name, err)
	}
	return nil
}

func (d *Driver) DeleteTag(name string) error {
	if err := d.c.delete("refs/tags/" + name); err != nil {
		return fmt.Errorf("DeleteTag %s: %w", name, err)
	}
	return nil
}

// cleanBitbucketUUID strips curly braces from Bitbucket UUIDs.
// Bitbucket returns UUIDs wrapped in braces: "{xxxxxxxx-...}".
// The /pipelines/{uuid} path segment must not include the braces.
func cleanBitbucketUUID(uuid string) string {
	if len(uuid) > 0 && uuid[0] == '{' {
		uuid = uuid[1:]
	}
	if len(uuid) > 0 && uuid[len(uuid)-1] == '}' {
		uuid = uuid[:len(uuid)-1]
	}
	return uuid
}
