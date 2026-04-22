package bitbucket

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// testRetryBase is a very short retry base for tests — avoids real backoff waits.
const testRetryBase = 1 * time.Millisecond

// withBaseURL patches the client's http.Client transport to route all requests
// through the given server URL. This is necessary because the httptest server
// uses a custom TLS certificate — we use srv.Client() which already has the
// transport configured for that certificate.
//
// However, we still need requests to go to the right host. We do this by
// pointing baseURL — so we override the client's repoURL via the test server.
// The cleanest approach is to have the test handler match any path, and the
// server URL is injected via a custom Transport in the test client.

func TestGet_success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Errorf("expected Bearer token, got %q", r.Header.Get("Authorization"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"key":"value"}`))
	}))
	defer srv.Close()

	// Use a client that repoints requests to the test server.
	c := newClientForTest(t, srv)
	var out struct {
		Key string `json:"key"`
	}
	err := c.get("refs/branches/main", &out)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.Key != "value" {
		t.Errorf("expected 'value', got %q", out.Key)
	}
}

func TestGet_404returnsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"type":"error","error":{"message":"not found"}}`, http.StatusNotFound)
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	var out struct{}
	err := c.get("refs/branches/missing", &out)
	if err == nil {
		t.Fatal("expected error for 404, got nil")
	}
}

func TestGetRaw_404returnsNil(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	raw, err := c.getRaw("src/main/nonexistent.txt")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if raw != nil {
		t.Errorf("expected nil for 404, got %q", raw)
	}
}

func TestGetRaw_200returnsBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("file content"))
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	raw, err := c.getRaw("src/main/file.txt")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(raw) != "file content" {
		t.Errorf("expected 'file content', got %q", string(raw))
	}
}

func TestPost_success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("expected POST, got %s", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"id":42}`))
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	var out struct {
		ID int `json:"id"`
	}
	err := c.post("pullrequests", map[string]string{"title": "test"}, &out)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if out.ID != 42 {
		t.Errorf("expected ID=42, got %d", out.ID)
	}
}

func TestDelete_success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete {
			t.Errorf("expected DELETE, got %s", r.Method)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	if err := c.delete("refs/branches/test"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDelete_404ignored(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	// Should not return error on 404 — best-effort cleanup semantics.
	if err := c.delete("refs/branches/nonexistent"); err != nil {
		t.Fatalf("expected no error on 404 delete, got: %v", err)
	}
}

func TestRetry_on429(t *testing.T) {
	attempts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	var out struct {
		OK bool `json:"ok"`
	}
	err := c.get("some/endpoint", &out)
	if err != nil {
		t.Fatalf("unexpected error after retries: %v", err)
	}
	if !out.OK {
		t.Error("expected ok=true")
	}
	if attempts != 3 {
		t.Errorf("expected 3 attempts, got %d", attempts)
	}
}

func TestRetry_on500exhausted(t *testing.T) {
	attempts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("internal error"))
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	var out struct{}
	err := c.get("some/endpoint", &out)
	if err == nil {
		t.Fatal("expected error after exhausting retries")
	}
	// maxRetries=3: initial attempt + 3 retries = 4 total
	if attempts != maxRetries+1 {
		t.Errorf("expected %d attempts, got %d", maxRetries+1, attempts)
	}
}

func TestPostForm_sendsMultipart(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseMultipartForm(1 << 20); err != nil {
			t.Errorf("failed to parse multipart form: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if r.FormValue("message") != "test commit" {
			t.Errorf("expected message='test commit', got %q", r.FormValue("message"))
		}
		if r.FormValue("branch") != "feature" {
			t.Errorf("expected branch='feature', got %q", r.FormValue("branch"))
		}
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	c := newClientForTest(t, srv)
	fields := map[string]string{
		"message":      "test commit",
		"branch":       "feature",
		"some/file.go": "package main",
	}
	if err := c.postForm("src", fields, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

// newClientForTest builds a test client that routes ALL requests to the given
// httptest.Server, regardless of the URL path. Uses a fast retry base so backoff
// tests don't wait real seconds.
func newClientForTest(t *testing.T, srv *httptest.Server) *Client {
	t.Helper()
	transport := &rewriteTransport{base: srv.URL, inner: http.DefaultTransport}
	hc := &http.Client{Transport: transport}
	c := NewClientWithHTTP("test-token", "ws", "repo", hc)
	return c.withRetryBase(testRetryBase)
}

// rewriteTransport rewrites all request URLs to target the test server.
// It replaces the scheme+host with the test server base URL, preserving path and query.
type rewriteTransport struct {
	base  string
	inner http.RoundTripper
}

func (t *rewriteTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Clone the request to avoid mutating the original.
	clone := req.Clone(req.Context())
	clone.URL.Scheme = "http"
	// Extract just host from base URL (strip scheme).
	host := t.base
	if len(host) > 7 && host[:7] == "http://" {
		host = host[7:]
	}
	clone.URL.Host = host
	// Remove any hardcoded baseURL prefix so the path is just the repo path.
	// The client builds URLs like: http://api.bitbucket.org/2.0/repositories/ws/repo/...
	// We want: http://<testserver>/repositories/ws/repo/...
	// Since the handler matches any path, we don't need to strip — just rehost.
	return t.inner.RoundTrip(clone)
}
