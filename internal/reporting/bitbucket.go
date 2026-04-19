package reporting

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

// defaultAPIBase is the Bitbucket API root. Overridable via
// BITBUCKET_API_BASE_URL for integration test stubs.
const defaultAPIBase = "https://api.bitbucket.org"

// PostBuildStatusWithCode sends a Bitbucket build status and returns the HTTP
// status code. Auth header is never written to logs.
func PostBuildStatusWithCode(ctx context.Context, auth BBAuth, repoOwner, repoSlug, commit string, status BBStatus) (int, error) {
	apiBase := os.Getenv("BITBUCKET_API_BASE_URL")
	if apiBase == "" {
		apiBase = defaultAPIBase
	}

	url := fmt.Sprintf(
		"%s/2.0/repositories/%s/%s/commit/%s/statuses/build",
		apiBase, repoOwner, repoSlug, commit,
	)

	body := fmt.Sprintf(
		`{"state":%q,"key":%q,"name":%q,"url":%q,"description":%q}`,
		status.State, status.Key, status.Name, status.URL, status.Description,
	)

	client := &http.Client{Timeout: httpTimeout()}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("bitbucket-build-status: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+auth.Token) // token never logged

	resp, err := client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("bitbucket-build-status: http post: %w", err)
	}
	defer func() { _, _ = io.Copy(io.Discard, resp.Body); _ = resp.Body.Close() }()

	return resp.StatusCode, nil
}
