package bitbucket

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/tests/integration-go/core"
)

// testPollInterval is a fast poll interval used in all tests that involve polling loops.
// The driver's default is 10s which would make tests unbearably slow.
const testPollInterval = 5 * time.Millisecond

// --- helpers ---

// handler returns a HandlerFunc that serves JSON at any path.
func jsonHandler(t *testing.T, statusCode int, body interface{}) http.HandlerFunc {
	t.Helper()
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(statusCode)
		if body != nil {
			if err := json.NewEncoder(w).Encode(body); err != nil {
				t.Errorf("encode response: %v", err)
			}
		}
	}
}

func newDriverForTest(t *testing.T, srv *httptest.Server) *Driver {
	t.Helper()
	c := newClientForTest(t, srv)
	return newDriverWithPollInterval(c, testPollInterval)
}

// --- GetBranchSHA ---

func TestGetBranchSHA_success(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"target": map[string]string{"hash": "abc123"},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	sha, err := d.GetBranchSHA("main")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sha != "abc123" {
		t.Errorf("expected sha=abc123, got %q", sha)
	}
}

func TestGetBranchSHA_error(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"type":"error"}`))
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	_, err := d.GetBranchSHA("main")
	if err == nil {
		t.Fatal("expected error for 401")
	}
}

// --- CreateBranch ---

func TestCreateBranch_success(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodGet {
			// GET branch SHA
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"target": map[string]string{"hash": "sha-from-main"},
			})
			return
		}
		// POST create branch
		var body map[string]interface{}
		_ = json.NewDecoder(r.Body).Decode(&body)
		if body["name"] != "feature" {
			t.Errorf("expected branch name 'feature', got %v", body["name"])
		}
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(map[string]string{"name": "feature"})
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	if err := d.CreateBranch("feature", "main"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

// --- DeleteBranch ---

func TestDeleteBranch_success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	if err := d.DeleteBranch("feature"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDeleteBranch_404isOK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	// DeleteBranch should not error on 404 (best-effort cleanup)
	if err := d.DeleteBranch("missing"); err != nil {
		t.Fatalf("expected no error on 404, got: %v", err)
	}
}

// --- CreateCommit ---

func TestCreateCommit_success(t *testing.T) {
	// POST /src returns 201; then GET /refs/branches/{branch} returns SHA
	callNum := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callNum++
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodPost {
			w.WriteHeader(http.StatusCreated)
			return
		}
		// GET branch → SHA
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"target": map[string]string{"hash": "new-commit-sha"},
		})
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	sha, err := d.CreateCommit("feature", "feat: add file", map[string]string{"file.txt": "content"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sha != "new-commit-sha" {
		t.Errorf("expected sha='new-commit-sha', got %q", sha)
	}
}

// --- GetFileContent ---

func TestGetFileContent_success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("file body"))
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	raw, err := d.GetFileContent(".versioning.yml", "main")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(raw) != "file body" {
		t.Errorf("expected 'file body', got %q", string(raw))
	}
}

func TestGetFileContent_404returnsNil(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	raw, err := d.GetFileContent("nonexistent.txt", "main")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if raw != nil {
		t.Errorf("expected nil for 404, got %q", raw)
	}
}

// --- CreatePR ---

func TestCreatePR_success(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 201, map[string]interface{}{
		"id": 99,
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr, err := d.CreatePR("feature", "main", "test: my PR")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pr.ID != 99 {
		t.Errorf("expected PR ID=99, got %d", pr.ID)
	}
	if pr.Platform != "bitbucket" {
		t.Errorf("expected platform=bitbucket, got %q", pr.Platform)
	}
}

// --- MergePR ---

func TestMergePR_squash(t *testing.T) {
	var capturedBody map[string]interface{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&capturedBody)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr := core.PRHandle{ID: 5, Platform: "bitbucket"}
	if err := d.MergePR(pr, core.MergeMethodSquash, "feat: squash subject"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if capturedBody["merge_strategy"] != "squash" {
		t.Errorf("expected merge_strategy=squash, got %v", capturedBody["merge_strategy"])
	}
	if capturedBody["message"] != "feat: squash subject" {
		t.Errorf("expected message='feat: squash subject', got %v", capturedBody["message"])
	}
}

func TestMergePR_merge(t *testing.T) {
	var capturedBody map[string]interface{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&capturedBody)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr := core.PRHandle{ID: 6, Platform: "bitbucket"}
	if err := d.MergePR(pr, core.MergeMethodMerge, ""); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if capturedBody["merge_strategy"] != "merge_commit" {
		t.Errorf("expected merge_strategy=merge_commit, got %v", capturedBody["merge_strategy"])
	}
	// no message field when subject is empty
	if _, ok := capturedBody["message"]; ok {
		t.Error("expected no 'message' field when subject is empty")
	}
}

// --- ClosePR ---

func TestClosePR_bestEffort(t *testing.T) {
	// Even on 500, ClosePR should return nil (best-effort)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr := core.PRHandle{ID: 10, Platform: "bitbucket"}
	// Must not return error
	if err := d.ClosePR(pr); err != nil {
		t.Fatalf("ClosePR should be best-effort, got error: %v", err)
	}
}

// --- WaitForChecks ---

func TestWaitForChecks_pass(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]string{
			{"state": "SUCCESSFUL"},
			{"state": "SUCCESSFUL"},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr := core.PRHandle{ID: 1, Platform: "bitbucket"}
	result, err := d.WaitForChecks(pr, 500*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != core.CheckPass {
		t.Errorf("expected CheckPass, got %q", result)
	}
}

func TestWaitForChecks_fail(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]string{
			{"state": "SUCCESSFUL"},
			{"state": "FAILED"},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr := core.PRHandle{ID: 2, Platform: "bitbucket"}
	result, err := d.WaitForChecks(pr, 500*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != core.CheckFail {
		t.Errorf("expected CheckFail, got %q", result)
	}
}

func TestWaitForChecks_timeout(t *testing.T) {
	// All checks are INPROGRESS — should time out.
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]string{
			{"state": "INPROGRESS"},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	pr := core.PRHandle{ID: 3, Platform: "bitbucket"}
	_, err := d.WaitForChecks(pr, 50*time.Millisecond)
	if err == nil {
		t.Fatal("expected timeout error, got nil")
	}
}

// --- GetLatestWorkflowRunID ---

func TestGetLatestWorkflowRunID_noRuns(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []interface{}{},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	id, err := d.GetLatestWorkflowRunID("main")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != nil {
		t.Errorf("expected nil, got %v", id)
	}
}

func TestGetLatestWorkflowRunID_hasRun(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]interface{}{
			{
				"uuid":  "{abc-123}",
				"state": map[string]string{"name": "COMPLETED"},
			},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	id, err := d.GetLatestWorkflowRunID("main")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id == nil {
		t.Fatal("expected non-nil ID")
	}
	if *id <= 0 {
		t.Errorf("expected positive int64 ID, got %d", *id)
	}
}

// --- WaitForNewWorkflowRun ---

func TestWaitForNewWorkflowRun_detectsNew(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")
		var uuid string
		if callCount == 1 {
			uuid = "{old-uuid}"
		} else {
			uuid = "{new-uuid}"
		}
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"values": []map[string]interface{}{
				{"uuid": uuid, "state": map[string]string{"name": "COMPLETED"}},
			},
		})
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)

	// Register the old UUID first
	oldID := d.uuidToID("{old-uuid}")

	newID, err := d.WaitForNewWorkflowRun("main", &oldID, 500*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if newID == nil {
		t.Fatal("expected new run ID, got nil")
	}
	if *newID == oldID {
		t.Error("expected a different run ID from the old one")
	}
}

func TestWaitForNewWorkflowRun_timeout(t *testing.T) {
	// Always returns the same UUID — should time out.
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]interface{}{
			{"uuid": "{same-uuid}", "state": map[string]string{"name": "RUNNING"}},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	oldID := d.uuidToID("{same-uuid}")

	result, err := d.WaitForNewWorkflowRun("main", &oldID, 50*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Returns nil on timeout (caller decides whether to dispatch)
	if result != nil {
		t.Errorf("expected nil on timeout, got %d", *result)
	}
}

// --- DispatchWorkflow ---

func TestDispatchWorkflow_success(t *testing.T) {
	var capturedBody map[string]interface{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&capturedBody)
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	if err := d.DispatchWorkflow("main", ""); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	target, _ := capturedBody["target"].(map[string]interface{})
	if target == nil {
		t.Fatal("expected target in body")
	}
	if target["ref_name"] != "main" {
		t.Errorf("expected ref_name=main, got %v", target["ref_name"])
	}
}

// --- WaitForWorkflowRunCompletion ---

func TestWaitForWorkflowRunCompletion_success(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"uuid": "{run-uuid}",
		"state": map[string]interface{}{
			"name":   "COMPLETED",
			"result": map[string]string{"name": "SUCCESSFUL"},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	id := d.uuidToID("{run-uuid}")

	ok, err := d.WaitForWorkflowRunCompletion(id, 500*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Error("expected successful completion")
	}
}

func TestWaitForWorkflowRunCompletion_failed(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"uuid": "{run-uuid}",
		"state": map[string]interface{}{
			"name":   "COMPLETED",
			"result": map[string]string{"name": "FAILED"},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	id := d.uuidToID("{run-uuid}")

	ok, err := d.WaitForWorkflowRunCompletion(id, 500*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Error("expected failed completion to return false")
	}
}

func TestWaitForWorkflowRunCompletion_unknownID(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	// ID 9999 was never registered in the uuid map
	_, err := d.WaitForWorkflowRunCompletion(9999, 100*time.Millisecond)
	if err == nil {
		t.Fatal("expected error for unknown run ID")
	}
}

// --- GetLatestTag ---

func TestGetLatestTag_noTags(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []interface{}{},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	tag, err := d.GetLatestTag("v1.")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if tag != nil {
		t.Errorf("expected nil, got %q", *tag)
	}
}

func TestGetLatestTag_returnsSemverLatest(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]string{
			{"name": "v1.2.0"},
			{"name": "v1.10.0"},
			{"name": "v1.3.0"},
		},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	tag, err := d.GetLatestTag("v1.")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if tag == nil {
		t.Fatal("expected a tag, got nil")
	}
	if *tag != "v1.10.0" {
		t.Errorf("expected v1.10.0 (highest semver), got %q", *tag)
	}
}

// --- WaitForNewTag ---

func TestWaitForNewTag_detectsNew(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")
		var name string
		if callCount == 1 {
			name = "v1.0.0"
		} else {
			name = "v1.1.0"
		}
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"values": []map[string]string{{"name": name}},
		})
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	prev := "v1.0.0"
	tag, err := d.WaitForNewTag(&prev, "v1.", 500*time.Millisecond)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if tag != "v1.1.0" {
		t.Errorf("expected v1.1.0, got %q", tag)
	}
}

func TestWaitForNewTag_timeout(t *testing.T) {
	srv := httptest.NewServer(jsonHandler(t, 200, map[string]interface{}{
		"values": []map[string]string{{"name": "v1.0.0"}},
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	prev := "v1.0.0"
	_, err := d.WaitForNewTag(&prev, "v1.", 50*time.Millisecond)
	if err == nil {
		t.Fatal("expected timeout error, got nil")
	}
}

// --- CreateTag ---

func TestCreateTag_success(t *testing.T) {
	var capturedBody map[string]interface{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodGet {
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"target": map[string]string{"hash": "sha-main"},
			})
			return
		}
		_ = json.NewDecoder(r.Body).Decode(&capturedBody)
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	if err := d.CreateTag("v1.2.3", "main"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if capturedBody["name"] != "v1.2.3" {
		t.Errorf("expected name=v1.2.3, got %v", capturedBody["name"])
	}
	target, _ := capturedBody["target"].(map[string]interface{})
	if target["hash"] != "sha-main" {
		t.Errorf("expected target.hash=sha-main, got %v", target["hash"])
	}
}

// --- DeleteTag ---

func TestDeleteTag_success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "v1.2.3") {
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	if err := d.DeleteTag("v1.2.3"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDeleteTag_404isOK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	d := newDriverForTest(t, srv)
	if err := d.DeleteTag("nonexistent"); err != nil {
		t.Fatalf("expected no error on 404, got: %v", err)
	}
}

// --- cleanBitbucketUUID ---

func TestCleanBitbucketUUID(t *testing.T) {
	cases := []struct {
		input    string
		expected string
	}{
		{"{abc-123}", "abc-123"},
		{"abc-123", "abc-123"},
		{"{}", ""},
		{"", ""},
	}
	for _, tc := range cases {
		got := cleanBitbucketUUID(tc.input)
		if got != tc.expected {
			t.Errorf("cleanBitbucketUUID(%q) = %q, want %q", tc.input, got, tc.expected)
		}
	}
}

// --- uuidToID determinism ---

func TestUUIDMapping_deterministic(t *testing.T) {
	d := &Driver{
		uuidMap: make(map[string]int64),
		idMap:   make(map[int64]string),
	}

	id1 := d.uuidToID("{uuid-a}")
	id2 := d.uuidToID("{uuid-b}")
	id3 := d.uuidToID("{uuid-a}") // same as first

	if id1 == id2 {
		t.Error("different UUIDs should get different IDs")
	}
	if id1 != id3 {
		t.Error("same UUID should return the same ID on second call")
	}

	// Reverse lookup
	uuid, ok := d.idToUUID(id1)
	if !ok || uuid != "{uuid-a}" {
		t.Errorf("idToUUID(%d) = %q, %v; want {uuid-a}, true", id1, uuid, ok)
	}
}
