package main

import (
	"context"
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/gitops"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

const (
	defaultGitUserName  = "CI Pipeline"
	defaultGitUserEmail = "ci@panora-versioning-pipe.noreply"
)

func newConfigureGitCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "configure-git",
		Short: "Configure git identity and fetch refs for the pipeline",
		Long: "Mirrors scripts/setup/configure-git.sh: sets safe.directory, configures " +
			"user.name/user.email, rewrites origin with embedded credentials when a " +
			"CI token is available, and fetches tags + the target branch.",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runConfigureGit(cmd.Context())
		},
	}
	return cmd
}

func runConfigureGit(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}

	log.Plain("Configuring git...")

	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("configure-git: resolve cwd: %w", err)
	}

	repo, err := gitops.Open(cwd)
	if err != nil {
		return err
	}

	if err := repo.ConfigureSafeDirectory(cwd); err != nil {
		return err
	}

	userName := envOrDefault("GIT_USER_NAME", defaultGitUserName)
	userEmail := envOrDefault("GIT_USER_EMAIL", defaultGitUserEmail)
	if err := repo.ConfigureIdentity(userName, userEmail); err != nil {
		return err
	}

	switch {
	case os.Getenv("CI_GITHUB_TOKEN") != "":
		log.Plain("Configuring GitHub App token for push access...")
		if err := repo.SetupRemoteAuth(gitops.AuthOptions{
			GitHubToken: os.Getenv("CI_GITHUB_TOKEN"),
		}); err != nil {
			return err
		}
		log.Plain("GitHub App token configured for push access")
	case os.Getenv("CI_BOT_USERNAME") != "" && os.Getenv("CI_BOT_APP_PASSWORD") != "":
		log.Plain("Configuring Bitbucket service account for push access...")
		if err := repo.SetupRemoteAuth(gitops.AuthOptions{
			BitbucketUser:        os.Getenv("CI_BOT_USERNAME"),
			BitbucketAppPassword: os.Getenv("CI_BOT_APP_PASSWORD"),
		}); err != nil {
			return err
		}
		log.Plain("Bitbucket service account configured for push access")
	}

	log.Plain("Fetching git refs...")
	if err := repo.Fetch(ctx); err != nil {
		// Local-only repos without a reachable origin must not block the
		// pipeline — the bash script tolerated the same case with `|| true`.
		log.Warn(fmt.Sprintf("fetch skipped: %v", err))
	}

	if target := os.Getenv("VERSIONING_TARGET_BRANCH"); target != "" {
		log.Plain(fmt.Sprintf("Fetching destination branch: %s", target))
		if err := repo.FetchBranch(ctx, target); err != nil {
			log.Warn(fmt.Sprintf("fetch target branch skipped: %v", err))
		}
	}

	log.Plain("Git configured successfully")
	return nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
