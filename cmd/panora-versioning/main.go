// Command panora-versioning is the Go entry point for the Panora versioning
// pipe. During the Bash -> Go migration it coexists with the legacy shell
// pipeline: `pipe.sh` stays as the Docker ENTRYPOINT and dispatches into
// subcommands implemented either here (Go) or under scripts/ (Bash).
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version"
)

const stubExitCode = 42

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
	cmd.AddCommand(stubCommands()...)

	return cmd
}

func stubCommands() []*cobra.Command {
	stubs := []struct {
		name  string
		short string
	}{
		{"pr-pipeline", "Run the PR pipeline (stub — Wave N)"},
		{"branch-pipeline", "Run the branch pipeline (stub — Wave N)"},
	}

	out := make([]*cobra.Command, 0, len(stubs))
	for _, s := range stubs {
		name := s.name
		out = append(out, &cobra.Command{
			Use:   name,
			Short: s.short,
			RunE: func(cmd *cobra.Command, _ []string) error {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "%s: not implemented yet\n", name)
				os.Exit(stubExitCode)
				return nil
			},
		})
	}
	return out
}
