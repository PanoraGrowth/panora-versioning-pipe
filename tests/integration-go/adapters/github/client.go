package github

import (
	"context"
	"fmt"
	"net/http"

	gh "github.com/google/go-github/v71/github"
	"golang.org/x/oauth2"
)

// Client wraps the google/go-github SDK client.
type Client struct {
	gh    *gh.Client
	owner string
	repo  string
	ctx   context.Context
}

// NewClient creates a GitHub API client authenticated with the given token.
// repo must be "owner/repo".
func NewClient(token, repo string) (*Client, error) {
	owner, repoName, err := splitRepo(repo)
	if err != nil {
		return nil, err
	}
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tc := oauth2.NewClient(context.Background(), ts)
	return &Client{
		gh:    gh.NewClient(tc),
		owner: owner,
		repo:  repoName,
		ctx:   context.Background(),
	}, nil
}

// NewClientWithHTTP creates a GitHub API client using a custom HTTP client (for testing).
func NewClientWithHTTP(httpClient *http.Client, owner, repo string) *Client {
	return &Client{
		gh:    gh.NewClient(httpClient),
		owner: owner,
		repo:  repo,
		ctx:   context.Background(),
	}
}

func splitRepo(repo string) (string, string, error) {
	for i, c := range repo {
		if c == '/' {
			return repo[:i], repo[i+1:], nil
		}
	}
	return "", "", fmt.Errorf("invalid repo format %q: expected owner/repo", repo)
}
