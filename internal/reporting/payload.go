// Package reporting implements HTTP adapters for CI notification endpoints.
// It covers Microsoft Teams webhooks and the Bitbucket build status API.
// Secrets (webhook URLs, API tokens) are never written to logs.
package reporting

import (
	"os"
	"strconv"
	"time"
)

// TeamsConfig holds notification settings read from .versioning-merged.yml.
type TeamsConfig struct {
	Enabled         bool   `yaml:"enabled"`
	OnSuccess       bool   `yaml:"on_success"`
	OnFailure       bool   `yaml:"on_failure"`
	PayloadTemplate string `yaml:"payload_template"`
}

// TeamsVars holds the substitution values for the Teams payload template.
// These map 1-to-1 with the $VAR_NAME tokens in the JSON template.
type TeamsVars struct {
	NotificationStyle    string
	NotificationIcon     string
	NotificationTitle    string
	NotificationSubtitle string
	BitbucketRepoSlug    string
	BitbucketBranch      string
	BitbucketPRID        string
	BitbucketCommitShort string
	BitbucketPRAuthor    string
	BitbucketWorkspace   string
	BitbucketBuildNumber string
}

// BBAuth holds Bitbucket API credentials.
type BBAuth struct {
	Token string // Bearer token — never logged
}

// BBStatus is the Bitbucket build status payload.
type BBStatus struct {
	State       string // "SUCCESSFUL" or "FAILED"
	Key         string
	Name        string
	URL         string
	Description string
}

// defaultHTTPTimeout is applied to all outbound HTTP calls unless overridden
// by PANORA_HTTP_TIMEOUT_SECONDS.
const defaultHTTPTimeout = 10 * time.Second

// httpTimeout returns the configured HTTP timeout.
func httpTimeout() time.Duration {
	if s := os.Getenv("PANORA_HTTP_TIMEOUT_SECONDS"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 {
			return time.Duration(n) * time.Second
		}
	}
	return defaultHTTPTimeout
}
