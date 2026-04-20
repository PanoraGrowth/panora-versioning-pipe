package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/release"
)

func newCheckReleaseReadinessCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "check-release-readiness",
		Short: "Run the release readiness gate",
		Long: `Aggregates state from git, config, and the working tree to decide whether
a release is safe. Advisory in PRs; blocking before tagging.

Exit 0 if zero blocking issues, exit 1 otherwise.`,
		SilenceUsage: true,
		RunE:         runCheckReleaseReadiness,
	}
}

func runCheckReleaseReadiness(cmd *cobra.Command, _ []string) error {
	cfgPath := os.Getenv("PANORA_MERGED_CONFIG")
	if cfgPath == "" {
		cfgPath = config.MergedConfigPath
	}

	cfg, err := config.Load(cfgPath)
	if err != nil {
		return fmt.Errorf("check-release-readiness: load config: %w", err)
	}

	repoRoot, err := repoRootDir()
	if err != nil {
		return fmt.Errorf("check-release-readiness: git rev-parse: %w", err)
	}

	baseRef := os.Getenv("BASE_REF")
	if baseRef == "" {
		baseRef = "origin/main"
	}

	ctx := release.Context{
		Cfg:      cfg,
		RepoRoot: repoRoot,
		BaseRef:  baseRef,
		Stdout:   cmd.OutOrStdout(),
		Stderr:   cmd.ErrOrStderr(),
	}

	fmt.Fprintln(cmd.OutOrStdout(), "==========================================")
	fmt.Fprintln(cmd.OutOrStdout(), "  Release Readiness Gate")
	fmt.Fprintln(cmd.OutOrStdout(), "==========================================")
	fmt.Fprintf(cmd.OutOrStdout(), "  base_ref:  %s\n", baseRef)
	fmt.Fprintf(cmd.OutOrStdout(), "  repo_root: %s\n", repoRoot)
	fmt.Fprintln(cmd.OutOrStdout())

	report, err := release.Check(ctx)
	if err != nil {
		return fmt.Errorf("check-release-readiness: %w", err)
	}

	release.Print(report, cmd.OutOrStdout())

	if release.HasBlockingResult(report) {
		os.Exit(1)
	}
	return nil
}
