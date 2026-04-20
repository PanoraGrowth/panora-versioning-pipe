// Command panora-versioning is the Go entry point for the Panora versioning
// pipe. As of GO-11 it is the container ENTRYPOINT: running the binary with
// no subcommand auto-detects the CI platform and dispatches to either the PR
// or the branch pipeline, replacing pipe.sh.
package main

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/pipeline"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version"
)

func main() {
	root := newRootCmd()
	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:           "panora-versioning",
		Short:         "Automated versioning, changelog, and release tooling",
		Long:          "panora-versioning drives the CI versioning pipeline for Panora repos.",
		SilenceUsage:  true,
		SilenceErrors: true,
		Version:       version.Full(),
		// Default command (no subcommand) replaces pipe.sh: platform detection,
		// env mapping, and dispatch to PR or branch pipeline.
		RunE: func(cmd *cobra.Command, _ []string) error {
			p := pipeline.New()
			p.Stdout = cmd.OutOrStdout()
			p.Stderr = cmd.ErrOrStderr()
			return p.Dispatch(cmd.Context())
		},
	}
	cmd.SetVersionTemplate(version.Template())

	cmd.AddCommand(newConfigureGitCmd())
	cmd.AddCommand(newConfigParseCmd())
	cmd.AddCommand(newGuardrailsCmd())
	cmd.AddCommand(newRunGuardrailsCmd())
	cmd.AddCommand(newCalcVersionCmd())
	cmd.AddCommand(newDetectScenarioCmd())
	cmd.AddCommand(newValidateCommitsCmd())
	cmd.AddCommand(newCheckCommitHygieneCmd())
	cmd.AddCommand(newNotifyTeamsCmd())
	cmd.AddCommand(newBitbucketBuildStatusCmd())
	cmd.AddCommand(newWriteVersionFileCmd())
	cmd.AddCommand(newCheckReleaseReadinessCmd())
	cmd.AddCommand(newGenerateChangelogPerFolderCmd())
	cmd.AddCommand(newGenerateChangelogLastCommitCmd())
	cmd.AddCommand(newUpdateChangelogCmd())
	cmd.AddCommand(newPRPipelineCmd())
	cmd.AddCommand(newBranchPipelineCmd())

	return cmd
}
