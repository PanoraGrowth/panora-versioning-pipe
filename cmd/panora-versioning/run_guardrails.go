package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/guardrails"
)

func newRunGuardrailsCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "run-guardrails",
		Short: "Run the guardrail suite",
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx, err := guardrails.LoadRunContext(cmd.OutOrStdout(), cmd.ErrOrStderr())
			if err != nil {
				return err
			}

			errs := guardrails.Run(ctx)
			if len(errs) > 0 {
				for _, e := range errs {
					_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "ERROR: Guardrail failed: %v\n", e)
				}
				os.Exit(1)
			}

			_, _ = fmt.Fprintln(cmd.OutOrStdout(), "✓ All guardrails passed")
			return nil
		},
	}
}
