package bitbucket

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"mime/multipart"
	"net/http"
	"time"
)

const (
	baseURL        = "https://api.bitbucket.org/2.0"
	requestTimeout = 30 * time.Second
	maxRetries     = 3
)

// Client handles authenticated HTTP requests against the Bitbucket REST API v2.0.
type Client struct {
	httpClient *http.Client
	workspace  string
	repo       string
	token      string
	ctx        context.Context
	// retryBase is the base duration for exponential backoff on 429/5xx.
	// Defaults to 1s; overridden in tests to keep them fast.
	retryBase time.Duration
}

// NewClient creates a Bitbucket client with the default http.Client.
func NewClient(token, workspace, repo string) *Client {
	return &Client{
		httpClient: &http.Client{Timeout: requestTimeout},
		workspace:  workspace,
		repo:       repo,
		token:      token,
		ctx:        context.Background(),
		retryBase:  1 * time.Second,
	}
}

// NewClientWithHTTP creates a Bitbucket client with a custom http.Client.
// Use this in tests to inject httptest.NewServer.
func NewClientWithHTTP(token, workspace, repo string, httpClient *http.Client) *Client {
	return &Client{
		httpClient: httpClient,
		workspace:  workspace,
		repo:       repo,
		token:      token,
		ctx:        context.Background(),
		retryBase:  1 * time.Second,
	}
}

// withRetryBase returns a copy of the client with a custom retry base duration.
// Only used in tests to avoid real backoff waits.
func (c *Client) withRetryBase(d time.Duration) *Client {
	cp := *c
	cp.retryBase = d
	return &cp
}

// repoURL returns the base URL for the configured repository.
func (c *Client) repoURL() string {
	return fmt.Sprintf("%s/repositories/%s/%s", baseURL, c.workspace, c.repo)
}

// get performs a GET request with exponential backoff on 429/5xx.
// Returns the decoded JSON body into out (pass nil to discard).
func (c *Client) get(path string, out interface{}) error {
	return c.doWithRetry(c.ctx, http.MethodGet, c.repoURL()+"/"+path, nil, "", out)
}

// getRaw performs a GET request and returns the raw response body.
// Returns nil, nil on 404.
func (c *Client) getRaw(path string) ([]byte, error) {
	url := c.repoURL() + "/" + path
	var raw []byte

	err := c.doRetry(c.ctx, func() (*http.Request, error) {
		return http.NewRequestWithContext(c.ctx, http.MethodGet, url, nil)
	}, func(resp *http.Response) error {
		if resp.StatusCode == http.StatusNotFound {
			return nil // caller treats nil as "not found"
		}
		if resp.StatusCode >= 400 {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("GET %s: status %d: %s", path, resp.StatusCode, string(body))
		}
		var err error
		raw, err = io.ReadAll(resp.Body)
		return err
	})
	if err != nil {
		return nil, err
	}
	return raw, nil
}

// post performs a POST request with a JSON body and decodes the response.
func (c *Client) post(path string, body interface{}, out interface{}) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal request body: %w", err)
	}
	return c.doWithRetry(c.ctx, http.MethodPost, c.repoURL()+"/"+path, bytes.NewReader(encoded), "application/json", out)
}

// postForm performs a POST request with multipart form-data (used by /src endpoint).
func (c *Client) postForm(path string, fields map[string]string, out interface{}) error {
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for k, v := range fields {
		if err := mw.WriteField(k, v); err != nil {
			return fmt.Errorf("write form field %s: %w", k, err)
		}
	}
	_ = mw.Close()

	contentType := mw.FormDataContentType()
	return c.doWithRetry(c.ctx, http.MethodPost, c.repoURL()+"/"+path, &buf, contentType, out)
}

// postNoRetry performs a single POST attempt with no retry on failure.
// Used for best-effort operations (e.g. PR decline) where failure is acceptable.
func (c *Client) postNoRetry(path string, body interface{}) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal request body: %w", err)
	}
	req, err := http.NewRequestWithContext(c.ctx, http.MethodPost, c.repoURL()+"/"+path, bytes.NewReader(encoded))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	_ = resp.Body.Close()
	return nil
}

// delete performs a DELETE request. 404 is silently ignored (best-effort cleanup).
func (c *Client) delete(path string) error {
	return c.doRetry(c.ctx, func() (*http.Request, error) {
		return http.NewRequestWithContext(c.ctx, http.MethodDelete, c.repoURL()+"/"+path, nil)
	}, func(resp *http.Response) error {
		if resp.StatusCode == http.StatusNotFound {
			return nil
		}
		if resp.StatusCode >= 400 {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("DELETE %s: status %d: %s", path, resp.StatusCode, string(body))
		}
		return nil
	})
}

// doWithRetry builds and executes an HTTP request, retrying on 429/5xx.
func (c *Client) doWithRetry(ctx context.Context, method, url string, body io.Reader, contentType string, out interface{}) error {
	// why: body must be re-readable across retries; buffer it once if it is a stream.
	var bodyBytes []byte
	if body != nil {
		var err error
		bodyBytes, err = io.ReadAll(body)
		if err != nil {
			return fmt.Errorf("read request body: %w", err)
		}
	}

	return c.doRetry(ctx, func() (*http.Request, error) {
		var r io.Reader
		if bodyBytes != nil {
			r = bytes.NewReader(bodyBytes)
		}
		req, err := http.NewRequestWithContext(ctx, method, url, r)
		if err != nil {
			return nil, err
		}
		if contentType != "" {
			req.Header.Set("Content-Type", contentType)
		}
		return req, nil
	}, func(resp *http.Response) error {
		if resp.StatusCode >= 400 {
			respBody, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("%s %s: status %d: %s", method, url, resp.StatusCode, string(respBody))
		}
		if out != nil && resp.ContentLength != 0 {
			return json.NewDecoder(resp.Body).Decode(out)
		}
		return nil
	})
}

// doRetry executes makeReq + handleResp with exponential backoff on 429/5xx.
// max retries: maxRetries. Jitter is per-request (seeded from crypto source indirectly
// via rand with a time-based seed to avoid import of crypto/rand for a test harness).
func (c *Client) doRetry(ctx context.Context, makeReq func() (*http.Request, error), handleResp func(*http.Response) error) error {
	// why: per-request seed avoids correlated jitter when multiple goroutines retry simultaneously.
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))

	var lastErr error
	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff with jitter: base=retryBase (1s default), doubles each retry.
			base := time.Duration(1<<uint(attempt-1)) * c.retryBase
			jitter := time.Duration(rng.Intn(int(c.retryBase/time.Millisecond)+1)) * time.Millisecond
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(base + jitter):
			}
		}

		req, err := makeReq()
		if err != nil {
			return fmt.Errorf("build request: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+c.token)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("http do: %w", err)
			continue
		}

		// Retry on 429 or 5xx — these are transient.
		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
			body, _ := io.ReadAll(resp.Body)
			_ = resp.Body.Close()
			lastErr = fmt.Errorf("transient status %d: %s", resp.StatusCode, string(body))
			continue
		}

		err = handleResp(resp)
		_ = resp.Body.Close()
		return err
	}
	return fmt.Errorf("after %d retries: %w", maxRetries, lastErr)
}
