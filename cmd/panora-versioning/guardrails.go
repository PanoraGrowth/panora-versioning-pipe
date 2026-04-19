package main

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/guardrails"
)

func newGuardrailsCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "guardrails",
		Short: "Run versioning guardrails",
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx, err := guardrails.LoadRunContext(cmd.OutOrStdout(), cmd.ErrOrStderr())
			if err != nil {
				return err
			}

			warned, err := guardrails.AssertNoVersionRegression(ctx)
			if err != nil {
				os.Exit(1)
			}
			_ = warned
			return nil
		},
	}
}
