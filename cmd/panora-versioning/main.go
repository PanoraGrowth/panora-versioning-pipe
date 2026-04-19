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
	cmd.AddCommand(newDetectScenarioCmd())
	cmd.AddCommand(stubCommands()...)

	return cmd
}

func stubCommands() []*cobra.Command {
	stubs := []struct {
		name  string
		short string
	}{
		{"calc-version", "Calculate the next semantic version (stub — Wave 1)"},
		{"validate-commits", "Validate commit message format (stub — Wave 1)"},
		{"check-commit-hygiene", "Check commit hygiene (stub — Wave 1)"},
		{"guardrails", "Run versioning guardrails (stub — Wave 1)"},
		{"run-guardrails", "Run the guardrail suite (stub — Wave 1)"},
		{"notify-teams", "Send the Teams notification (stub — Wave 1)"},
		{"bitbucket-build-status", "Push Bitbucket build status (stub — Wave 1)"},
		{"write-version-file", "Write version files (stub — Wave 2)"},
		{"generate-changelog-per-folder", "Generate per-folder changelogs (stub — Wave 2)"},
		{"generate-changelog-last-commit", "Generate the last-commit changelog (stub — Wave 2)"},
		{"update-changelog", "Update CHANGELOG.md (stub — Wave 2)"},
		{"check-release-readiness", "Check release readiness (stub — Wave 2)"},
		{"config-parse", "Parse and merge .versioning.yml (stub — Wave N)"},
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
