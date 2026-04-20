package main

import (
	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/pipeline"
)

// newBranchPipelineCmd is the GO-11 replacement for
// scripts/orchestration/branch-pipeline.sh. See pr_pipeline.go for the
// rationale about preflight responsibilities.
func newBranchPipelineCmd() *cobra.Command {
	return &cobra.Command{
		Use:           "branch-pipeline",
		Short:         "Run the branch pipeline (tag creation)",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			p := pipeline.New()
			p.Stdout = cmd.OutOrStdout()
			p.Stderr = cmd.ErrOrStderr()
			if err := (&pipeline.SelfExecRunner{
				Stdout: p.Stdout,
				Stderr: p.Stderr,
			}).Run(cmd.Context(), "config-parse", "config_parse"); err != nil {
				return err
			}
			return p.RunBranch(cmd.Context())
		},
	}
}
