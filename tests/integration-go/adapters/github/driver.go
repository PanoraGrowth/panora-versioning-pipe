package github

import (
	"fmt"
	"sort"
	"strings"
	"time"

	semver "github.com/Masterminds/semver/v3"
	gh "github.com/google/go-github/v71/github"

	"github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/core"
)

const (
	pollInterval = 10 * time.Second
	maxWait      = 3 * time.Minute
)

// Driver implements core.PlatformDriver for GitHub.
type Driver struct {
	c *Client
}

// NewDriver creates a GitHub driver.
func NewDriver(c *Client) *Driver {
	return &Driver{c: c}
}

// --- Branch ---

func (d *Driver) GetBranchSHA(branch string) (string, error) {
	ref, _, err := d.c.gh.Git.GetRef(d.c.ctx, d.c.owner, d.c.repo, "refs/heads/"+branch)
	if err != nil {
		return "", fmt.Errorf("GetBranchSHA %s: %w", branch, err)
	}
	return ref.GetObject().GetSHA(), nil
}

func (d *Driver) CreateBranch(name, fromRef string) error {
	sha, err := d.GetBranchSHA(fromRef)
	if err != nil {
		return err
	}
	refStr := "refs/heads/" + name
	_, _, err = d.c.gh.Git.CreateRef(d.c.ctx, d.c.owner, d.c.repo, &gh.Reference{
		Ref:    &refStr,
		Object: &gh.GitObject{SHA: &sha},
	})
	if err != nil {
		return fmt.Errorf("CreateBranch %s: %w", name, err)
	}
	return nil
}

func (d *Driver) DeleteBranch(name string) error {
	_, err := d.c.gh.Git.DeleteRef(d.c.ctx, d.c.owner, d.c.repo, "refs/heads/"+name)
	if err != nil && !isNotFound(err) {
		return fmt.Errorf("DeleteBranch %s: %w", name, err)
	}
	return nil
}

// --- Commits ---

func (d *Driver) CreateCommit(branch, message string, files map[string]string) (string, error) {
	// Get current tip
	ref, _, err := d.c.gh.Git.GetRef(d.c.ctx, d.c.owner, d.c.repo, "refs/heads/"+branch)
	if err != nil {
		return "", fmt.Errorf("get branch ref: %w", err)
	}
	parentSHA := ref.GetObject().GetSHA()

	parentCommit, _, err := d.c.gh.Git.GetCommit(d.c.ctx, d.c.owner, d.c.repo, parentSHA)
	if err != nil {
		return "", fmt.Errorf("get parent commit: %w", err)
	}
	baseTree := parentCommit.GetTree().GetSHA()

	// Create blobs
	treeEntries := make([]*gh.TreeEntry, 0, len(files))
	for path, content := range files {
		blob, _, err := d.c.gh.Git.CreateBlob(d.c.ctx, d.c.owner, d.c.repo, &gh.Blob{
			Content:  gh.Ptr(content),
			Encoding: gh.Ptr("utf-8"),
		})
		if err != nil {
			return "", fmt.Errorf("create blob for %s: %w", path, err)
		}
		p := path
		mode := "100644"
		typ := "blob"
		treeEntries = append(treeEntries, &gh.TreeEntry{
			Path: &p,
			Mode: &mode,
			Type: &typ,
			SHA:  blob.SHA,
		})
	}

	// Create tree
	tree, _, err := d.c.gh.Git.CreateTree(d.c.ctx, d.c.owner, d.c.repo, baseTree, treeEntries)
	if err != nil {
		return "", fmt.Errorf("create tree: %w", err)
	}

	// Create commit
	commit, _, err := d.c.gh.Git.CreateCommit(d.c.ctx, d.c.owner, d.c.repo, &gh.Commit{
		Message: &message,
		Tree:    &gh.Tree{SHA: tree.SHA},
		Parents: []*gh.Commit{{SHA: &parentSHA}},
	}, nil)
	if err != nil {
		return "", fmt.Errorf("create commit: %w", err)
	}

	// Update branch ref
	commitSHA := commit.GetSHA()
	_, _, err = d.c.gh.Git.UpdateRef(d.c.ctx, d.c.owner, d.c.repo, &gh.Reference{
		Ref:    gh.Ptr("refs/heads/" + branch),
		Object: &gh.GitObject{SHA: &commitSHA},
	}, false)
	if err != nil {
		return "", fmt.Errorf("update branch ref: %w", err)
	}
	return commitSHA, nil
}

func (d *Driver) GetFileContent(path, ref string) ([]byte, error) {
	fileContent, _, _, err := d.c.gh.Repositories.GetContents(d.c.ctx, d.c.owner, d.c.repo, path,
		&gh.RepositoryContentGetOptions{Ref: ref})
	if err != nil {
		if isNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("GetFileContent %s@%s: %w", path, ref, err)
	}
	if fileContent == nil {
		return nil, nil
	}
	raw, err := fileContent.GetContent()
	if err != nil {
		return nil, fmt.Errorf("decode file content %s@%s: %w", path, ref, err)
	}
	return []byte(raw), nil
}

// --- Pull Requests ---

func (d *Driver) CreatePR(head, base, title string) (core.PRHandle, error) {
	body := "Automated integration test"
	pr, _, err := d.c.gh.PullRequests.Create(d.c.ctx, d.c.owner, d.c.repo, &gh.NewPullRequest{
		Title: &title,
		Head:  &head,
		Base:  &base,
		Body:  &body,
	})
	if err != nil {
		return core.PRHandle{}, fmt.Errorf("CreatePR: %w", err)
	}
	return core.PRHandle{ID: int64(pr.GetNumber()), Platform: "github"}, nil
}

func (d *Driver) MergePR(pr core.PRHandle, method core.MergeMethod, subject string) error {
	opts := &gh.PullRequestOptions{
		MergeMethod: string(method),
	}
	if subject != "" {
		opts.CommitTitle = subject
	}
	_, _, err := d.c.gh.PullRequests.Merge(d.c.ctx, d.c.owner, d.c.repo, int(pr.ID), "", opts)
	if err != nil {
		return fmt.Errorf("MergePR %d: %w", pr.ID, err)
	}
	return nil
}

func (d *Driver) ClosePR(pr core.PRHandle) error {
	state := "closed"
	_, _, err := d.c.gh.PullRequests.Edit(d.c.ctx, d.c.owner, d.c.repo, int(pr.ID), &gh.PullRequest{
		State: &state,
	})
	if err != nil && !isNotFound(err) {
		return fmt.Errorf("ClosePR %d: %w", pr.ID, err)
	}
	return nil
}

// --- Checks ---

func (d *Driver) WaitForChecks(pr core.PRHandle, timeout time.Duration) (core.CheckResult, error) {
	// Get the PR to find the HEAD SHA
	prData, _, err := d.c.gh.PullRequests.Get(d.c.ctx, d.c.owner, d.c.repo, int(pr.ID))
	if err != nil {
		return "", fmt.Errorf("get PR %d: %w", pr.ID, err)
	}
	ref := prData.GetHead().GetSHA()

	terminalStates := map[string]bool{
		"success": true, "failure": true, "cancelled": true,
		"skipped": true, "stale": true, "timed_out": true,
		"action_required": true, "neutral": true,
	}

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		runs, _, err := d.c.gh.Checks.ListCheckRunsForRef(d.c.ctx, d.c.owner, d.c.repo, ref,
			&gh.ListCheckRunsOptions{})
		if err != nil || runs == nil || len(runs.CheckRuns) == 0 {
			time.Sleep(pollInterval)
			continue
		}

		allDone := true
		allPass := true
		for _, run := range runs.CheckRuns {
			conclusion := strings.ToLower(run.GetConclusion())
			status := strings.ToLower(run.GetStatus())
			if !terminalStates[conclusion] && status != "completed" {
				allDone = false
				break
			}
			if conclusion != "success" && conclusion != "skipped" && conclusion != "neutral" {
				allPass = false
			}
		}
		if !allDone {
			time.Sleep(pollInterval)
			continue
		}
		if allPass {
			return core.CheckPass, nil
		}
		return core.CheckFail, nil
	}
	return "", fmt.Errorf("PR checks did not complete within %s", timeout)
}

// --- Workflow ---

func (d *Driver) GetLatestWorkflowRunID(branch string) (*int64, error) {
	runs, _, err := d.c.gh.Actions.ListWorkflowRunsByFileName(
		d.c.ctx, d.c.owner, d.c.repo, "versioning.yml",
		&gh.ListWorkflowRunsOptions{Branch: branch, ListOptions: gh.ListOptions{PerPage: 1}},
	)
	if err != nil {
		return nil, fmt.Errorf("list workflow runs: %w", err)
	}
	if runs == nil || len(runs.WorkflowRuns) == 0 {
		return nil, nil
	}
	id := runs.WorkflowRuns[0].GetID()
	return &id, nil
}

func (d *Driver) WaitForNewWorkflowRun(branch string, previousRunID *int64, timeout time.Duration) (*int64, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		runs, _, err := d.c.gh.Actions.ListWorkflowRunsByFileName(
			d.c.ctx, d.c.owner, d.c.repo, "versioning.yml",
			&gh.ListWorkflowRunsOptions{Branch: branch, ListOptions: gh.ListOptions{PerPage: 1}},
		)
		if err != nil || runs == nil || len(runs.WorkflowRuns) == 0 {
			time.Sleep(pollInterval)
			continue
		}
		run := runs.WorkflowRuns[0]
		id := run.GetID()
		if previousRunID == nil || id != *previousRunID {
			return &id, nil
		}
		time.Sleep(pollInterval)
	}
	return nil, nil
}

func (d *Driver) DispatchWorkflow(ref, imageTag string) error {
	inputs := map[string]interface{}{}
	if imageTag != "" {
		inputs["image_tag"] = imageTag
	}
	_, err := d.c.gh.Actions.CreateWorkflowDispatchEventByFileName(
		d.c.ctx, d.c.owner, d.c.repo, "versioning.yml",
		gh.CreateWorkflowDispatchEventRequest{Ref: ref, Inputs: inputs},
	)
	if err != nil {
		return fmt.Errorf("dispatch workflow: %w", err)
	}
	return nil
}

func (d *Driver) WaitForWorkflowRunCompletion(runID int64, timeout time.Duration) (bool, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		run, _, err := d.c.gh.Actions.GetWorkflowRunByID(d.c.ctx, d.c.owner, d.c.repo, runID)
		if err != nil {
			time.Sleep(pollInterval)
			continue
		}
		if run.GetStatus() == "completed" {
			return run.GetConclusion() == "success", nil
		}
		time.Sleep(pollInterval)
	}
	return false, fmt.Errorf("workflow run %d did not complete within %s", runID, timeout)
}

// --- Tags ---

func (d *Driver) GetLatestTag(prefix string, excludePrefixes []string) (*string, error) {
	refs, _, err := d.c.gh.Git.ListMatchingRefs(d.c.ctx, d.c.owner, d.c.repo, &gh.ReferenceListOptions{
		Ref: "refs/tags/" + prefix,
	})
	if err != nil {
		if isNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("list tags (prefix=%s): %w", prefix, err)
	}
	if len(refs) == 0 {
		return nil, nil
	}

	// ListMatchingRefs does not guarantee chronological order.
	// Sort by semver descending so the first element is always the highest version.
	names := make([]string, 0, len(refs))
	for _, r := range refs {
		name := strings.TrimPrefix(r.GetRef(), "refs/tags/")
		// Exclude tags that belong to a more-specific sub-namespace (e.g. v1.27.* when
		// querying v1.*). This prevents cross-contamination between parallel scenarios.
		if hasExcludedPrefix(name, excludePrefixes) {
			continue
		}
		names = append(names, name)
	}
	if len(names) == 0 {
		return nil, nil
	}
	sort.Slice(names, func(i, j int) bool {
		vi, ei := semver.NewVersion(names[i])
		vj, ej := semver.NewVersion(names[j])
		if ei != nil || ej != nil {
			// Unparseable tags fall back to lexicographic order
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
			time.Sleep(pollInterval)
			continue
		}
		if current != nil && (previousTag == nil || *current != *previousTag) {
			return *current, nil
		}
		time.Sleep(pollInterval)
	}
	prev := "<none>"
	if previousTag != nil {
		prev = *previousTag
	}
	return "", fmt.Errorf("no new tag (prefix=%s) appeared within %s; last: %s", prefix, timeout, prev)
}

// hasExcludedPrefix reports whether name starts with any of the excludePrefixes.
func hasExcludedPrefix(name string, excludePrefixes []string) bool {
	for _, ex := range excludePrefixes {
		if strings.HasPrefix(name, ex) {
			return true
		}
	}
	return false
}

func (d *Driver) CreateTag(name, ref string) error {
	sha, err := d.GetBranchSHA(ref)
	if err != nil {
		return err
	}
	refStr := "refs/tags/" + name
	_, _, err = d.c.gh.Git.CreateRef(d.c.ctx, d.c.owner, d.c.repo, &gh.Reference{
		Ref:    &refStr,
		Object: &gh.GitObject{SHA: &sha},
	})
	if err != nil {
		return fmt.Errorf("CreateTag %s: %w", name, err)
	}
	return nil
}

func (d *Driver) DeleteTag(name string) error {
	_, err := d.c.gh.Git.DeleteRef(d.c.ctx, d.c.owner, d.c.repo, "refs/tags/"+name)
	if err != nil && !isNotFound(err) {
		return fmt.Errorf("DeleteTag %s: %w", name, err)
	}
	return nil
}

// isNotFound returns true for 404 GitHub API errors.
func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	if e, ok := err.(*gh.ErrorResponse); ok {
		return e.Response != nil && e.Response.StatusCode == 404
	}
	return strings.Contains(err.Error(), "404")
}
