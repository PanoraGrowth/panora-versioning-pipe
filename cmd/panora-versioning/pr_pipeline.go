package main

import (
	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/pipeline"
)

// newPRPipelineCmd is the GO-11 replacement for scripts/orchestration/pr-pipeline.sh.
// It does NOT run preflight (configure-git + config-parse) — those are run
// explicitly by the default command or invoked by the caller. This mirrors the
// bash model where pr-pipeline.sh also assumed configure-git had already run.
func newPRPipelineCmd() *cobra.Command {
	return &cobra.Command{
		Use:           "pr-pipeline",
		Short:         "Run the PR pipeline",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			p := pipeline.New()
			p.Stdout = cmd.OutOrStdout()
			p.Stderr = cmd.ErrOrStderr()
			// When invoked directly as a subcommand (not via Dispatch), the caller
			// is responsible for having already run config-parse. Run it here to
			// be safe — config-parse is idempotent.
			if err := (&pipeline.SelfExecRunner{
				Stdout: p.Stdout,
				Stderr: p.Stderr,
			}).Run(cmd.Context(), "config-parse", "config_parse"); err != nil {
				return err
			}
			return p.RunPR(cmd.Context())
		},
	}
}
