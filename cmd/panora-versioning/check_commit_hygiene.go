package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/validation"
)

func newCheckCommitHygieneCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:           "check-commit-hygiene",
		Short:         "Lint commit messages for GitHub Actions workflow-skip substrings",
		SilenceUsage:  true,
		SilenceErrors: true,
	}

	var (
		message string
		file    string
	)
	cmd.Flags().StringVarP(&message, "message", "m", "", "commit message to lint inline")
	cmd.Flags().StringVarP(&file, "file", "f", "", "path to commit message file")

	// Custom -h so it matches the bash script's help format
	cmd.SetHelpFunc(func(c *cobra.Command, _ []string) {
		_, _ = fmt.Fprintln(c.OutOrStdout(), validation.UsageText)
	})

	// Unknown flags must exit 2 (usage error), matching the bash script.
	cmd.SetFlagErrorFunc(func(c *cobra.Command, err error) error {
		_, _ = fmt.Fprintf(c.ErrOrStderr(), "ERROR: %v\n", err)
		os.Exit(2)
		return nil
	})

	cmd.RunE = func(cmd *cobra.Command, _ []string) error {
		mode, arg, err := resolveHygieneMode(cmd, message, file)
		if err != nil {
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), err.Error())
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), validation.UsageText)
			os.Exit(2)
			return nil
		}

		var msg string
		switch mode {
		case "message":
			msg = arg
		case "file":
			data, readErr := os.ReadFile(arg)
			if readErr != nil {
				_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "ERROR: cannot read file: %s\n", arg)
				os.Exit(2)
				return nil
			}
			msg = string(data)
		}

		issues := validation.CheckMessage(msg, "commit message")
		if len(issues) == 0 {
			return nil
		}

		for _, issue := range issues {
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), issue.Error())
		}
		_, _ = fmt.Fprintln(cmd.ErrOrStderr(), validation.RemediationText)
		os.Exit(1)
		return nil
	}

	return cmd
}

func resolveHygieneMode(cmd *cobra.Command, message, file string) (mode, arg string, err error) {
	hasMsg := cmd.Flags().Changed("message")
	hasFile := cmd.Flags().Changed("file")

	switch {
	case !hasMsg && !hasFile:
		return "", "", fmt.Errorf("ERROR: one of -m or -f is required")
	case hasMsg && hasFile:
		return "", "", fmt.Errorf("ERROR: -m and -f are mutually exclusive")
	case hasMsg:
		return "message", message, nil
	default:
		return "file", file, nil
	}
}
