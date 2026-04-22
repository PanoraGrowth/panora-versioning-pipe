package bitbucket

import "net/http"

// Client holds credentials for the Bitbucket REST API v2.0.
// Implemented in T3 — stub only in T2.
type Client struct {
	httpClient *http.Client
	workspace  string
	repo       string
	token      string
}

// NewClient creates a Bitbucket client stub.
func NewClient(token, workspace, repo string) *Client {
	return &Client{
		httpClient: &http.Client{},
		workspace:  workspace,
		repo:       repo,
		token:      token,
	}
}
