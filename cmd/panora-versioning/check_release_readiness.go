package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/release"
)

func newCheckReleaseReadinessCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "check-release-readiness",
		Short: "Check release readiness gate",
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx, err := release.LoadContext()
			if err != nil {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "ERROR: %v\n", err)
				os.Exit(1)
			}

			out := cmd.OutOrStdout()

			_, _ = fmt.Fprintln(out, "==========================================")
			_, _ = fmt.Fprintln(out, "  Release Readiness Gate")
			_, _ = fmt.Fprintln(out, "==========================================")
			_, _ = fmt.Fprintf(out, "  base_ref:  %s\n", ctx.BaseRef)
			_, _ = fmt.Fprintf(out, "  repo_root: %s\n", ctx.RepoRoot)
			_, _ = fmt.Fprintln(out)

			rp := release.Run(ctx)

			for _, r := range rp.Results {
				_, _ = fmt.Fprintln(out, r.String())
			}

			_, _ = fmt.Fprintln(out)
			_, _ = fmt.Fprintln(out, "------------------------------------------")
			_, _ = fmt.Fprintln(out, release.FormatSummary(rp))
			_, _ = fmt.Fprintln(out, "------------------------------------------")

			if v := os.Getenv("GITHUB_STEP_SUMMARY"); v != "" {
				f, err := os.OpenFile(v, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
				if err == nil {
					_, _ = fmt.Fprint(f, release.FormatGitHubStepSummary(rp))
					_ = f.Close()
				}
			}

			if rp.Blocked() {
				os.Exit(1)
			}
			return nil
		},
	}
}
