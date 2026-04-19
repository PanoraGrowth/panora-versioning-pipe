package reporting

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

// SendTeamsNotificationWithStatus renders the payload template with vars,
// POSTs it to webhookURL, and returns the HTTP status code.
// The webhook URL is never written to logs.
func SendTeamsNotificationWithStatus(ctx context.Context, webhookURL, templatePath string, vars TeamsVars) (int, error) {
	raw, err := os.ReadFile(templatePath)
	if err != nil {
		return 0, fmt.Errorf("teams: read payload template: %w", err)
	}

	payload := renderTemplate(string(raw), vars)

	if err := os.WriteFile("/tmp/teams_payload.json", []byte(payload), 0o644); err != nil {
		_ = err // best-effort debug artifact — don't fail the command
	}

	return postJSONStatus(ctx, webhookURL, payload)
}

// renderTemplate substitutes shell-style $VAR_NAME tokens in the template
// string. Compatible with the envsubst format the bash script used.
func renderTemplate(src string, vars TeamsVars) string {
	replacements := map[string]string{
		"$NOTIFICATION_STYLE":     vars.NotificationStyle,
		"$NOTIFICATION_ICON":      vars.NotificationIcon,
		"$NOTIFICATION_TITLE":     vars.NotificationTitle,
		"$NOTIFICATION_SUBTITLE":  vars.NotificationSubtitle,
		"$BITBUCKET_REPO_SLUG":    vars.BitbucketRepoSlug,
		"$BITBUCKET_BRANCH":       vars.BitbucketBranch,
		"$BITBUCKET_PR_ID":        vars.BitbucketPRID,
		"$BITBUCKET_COMMIT_SHORT": vars.BitbucketCommitShort,
		"$BITBUCKET_PR_AUTHOR":    vars.BitbucketPRAuthor,
		"$BITBUCKET_WORKSPACE":    vars.BitbucketWorkspace,
		"$BITBUCKET_BUILD_NUMBER": vars.BitbucketBuildNumber,
	}

	result := src
	for k, v := range replacements {
		result = strings.ReplaceAll(result, k, v)
	}
	return result
}

func postJSONStatus(ctx context.Context, url, body string) (int, error) {
	client := &http.Client{Timeout: httpTimeout()}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("teams: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("teams: http post: %w", err)
	}
	defer func() { _, _ = io.Copy(io.Discard, resp.Body); _ = resp.Body.Close() }()

	return resp.StatusCode, nil
}
