package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/reporting"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

func newBitbucketBuildStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:           "bitbucket-build-status",
		Short:         "Report build status to the Bitbucket API",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runBitbucketBuildStatus(cmd.Context())
		},
	}
}

func runBitbucketBuildStatus(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}

	log.Section("REPORTING BUILD STATUS TO PR")

	required := []string{
		"BITBUCKET_COMMIT",
		"BITBUCKET_REPO_OWNER",
		"BITBUCKET_REPO_SLUG",
		"BITBUCKET_BUILD_NUMBER",
		"BITBUCKET_API_TOKEN",
	}
	missing := missingEnvVars(required)
	if len(missing) > 0 {
		log.Plain(fmt.Sprintf("WARNING: Missing variables: %s", strings.Join(missing, " ")))
		log.Plain("Build status will not be reported")
		log.Section("=")
		return nil
	}

	exitCode := os.Getenv("BITBUCKET_EXIT_CODE")
	state, desc := "SUCCESSFUL", "Pipeline completed successfully"
	if exitCode != "" && exitCode != "0" {
		state, desc = "FAILED", "Pipeline failed"
	}

	commit := resolveCurrentCommit()

	repoOwner := os.Getenv("BITBUCKET_REPO_OWNER")
	repoSlug := os.Getenv("BITBUCKET_REPO_SLUG")
	buildNum := os.Getenv("BITBUCKET_BUILD_NUMBER")

	buildURL := fmt.Sprintf(
		"https://bitbucket.org/%s/%s/pipelines/results/%s",
		repoOwner, repoSlug, buildNum,
	)

	log.Plain(fmt.Sprintf("Status: %s", state))
	log.Plain(fmt.Sprintf("Description: %s", desc))
	log.Plain(fmt.Sprintf("Build URL: %s", buildURL))
	log.Plain(fmt.Sprintf("Commit: %s", commit))

	auth := reporting.BBAuth{Token: os.Getenv("BITBUCKET_API_TOKEN")} // never logged
	status := reporting.BBStatus{
		State:       state,
		Key:         "pr-pipeline",
		Name:        fmt.Sprintf("PR Pipeline #%s", buildNum),
		URL:         buildURL,
		Description: desc,
	}

	statusCode, err := reporting.PostBuildStatusWithCode(ctx, auth, repoOwner, repoSlug, commit, status)
	if err != nil {
		log.Plain(fmt.Sprintf("HTTP Response: error (%v)", err))
		log.Plain("ERROR: Failed to report build status")
		log.Section("=")
		return nil // bash exits 0 regardless
	}

	log.Plain(fmt.Sprintf("HTTP Response: %d", statusCode))
	if statusCode >= 200 && statusCode < 300 {
		log.Plain("Build status reported successfully")
	} else {
		log.Plain("ERROR: Failed to report build status")
	}
	log.Section("=")

	return nil
}

func missingEnvVars(vars []string) []string {
	var missing []string
	for _, v := range vars {
		if os.Getenv(v) == "" {
			missing = append(missing, v)
		}
	}
	return missing
}

func resolveCurrentCommit() string {
	// BITBUCKET_COMMIT env first (matches bash: "Current commit after pipeline-driven pushes").
	if c := os.Getenv("BITBUCKET_COMMIT"); c != "" {
		return c
	}
	// Fall back to git HEAD.
	out, err := exec.Command("git", "rev-parse", "HEAD").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}
