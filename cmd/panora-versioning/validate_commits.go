package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	ilog "github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/state"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/validation"
)

func newValidateCommitsCmd() *cobra.Command {
	return &cobra.Command{
		Use:           "validate-commits",
		Short:         "Validate commit message format against configured rules",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE:          runValidateCommits,
	}
}

func runValidateCommits(cmd *cobra.Command, _ []string) error {
	// Load scenario
	env, err := state.LoadEnv(scenarioEnvPath)
	if err != nil {
		ilog.Error("validate-commits: loading scenario", err)
		os.Exit(1)
		return nil
	}

	scenario := env["SCENARIO"]
	targetBranch := env["VERSIONING_TARGET_BRANCH"]
	if targetBranch == "" {
		targetBranch = os.Getenv("VERSIONING_TARGET_BRANCH")
	}

	// Only validate for development_release and hotfix scenarios
	switch scenario {
	case "development_release", "hotfix":
		// continue
	default:
		return nil
	}

	ilog.Section("VALIDATING COMMIT FORMAT")
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), "")

	// Load merged config
	cfg, err := config.Load(mergedConfigPath)
	if err != nil {
		ilog.Error("validate-commits: loading config", err)
		os.Exit(1)
		return nil
	}

	// Validate PR title first (VALIDATION 3)
	prTitle := env["VERSIONING_PR_TITLE"]
	if prTitle == "" {
		prTitle = os.Getenv("VERSIONING_PR_TITLE")
	}
	if prTitle == "" {
		prTitle = os.Getenv("GITHUB_PR_TITLE")
	}

	if prTitle != "" && cfg.RequireCommitTypes() {
		ilog.Info(fmt.Sprintf("PR title: %q", prTitle))
		_, _ = fmt.Fprintln(cmd.OutOrStdout(), "")
		if err := validation.ValidatePRTitle(prTitle, cfg); err != nil {
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), err.Error())
			os.Exit(1)
			return nil
		}
		ilog.Success("PR title is well-formed")
		_, _ = fmt.Fprintln(cmd.OutOrStdout(), "")
	}

	// Get commits via git log origin/<target>..HEAD --no-merges --pretty=%s
	rawCommits, err := gitLogSubjects(targetBranch)
	if err != nil {
		ilog.Error("validate-commits: git log", err)
		os.Exit(1)
		return nil
	}

	// Filter ignored patterns
	commits := validation.FilterIgnored(rawCommits, cfg.Validation.IgnorePatterns)

	if len(commits) == 0 {
		ilog.Error("No valid commits found in this PR", nil)
		os.Exit(1)
		return nil
	}

	// Display commits with validation markers
	ilog.Info("Commits in this PR:")
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), "")
	fullPattern := buildFullPatternForDisplay(cfg)
	for _, c := range commits {
		if fullPattern == nil || fullPattern.MatchString(c) {
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  + %s\n", c)
		} else {
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  x INVALID: %s\n", c)
		}
	}
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), "")

	// Run validation
	issues := validation.ValidateCommits(commits, cfg)
	if len(issues) == 0 {
		printValidationSuccess(cmd, cfg)
		return nil
	}

	// Report violations
	printValidationErrors(cmd, cfg, issues, commits)
	os.Exit(1)
	return nil
}

func gitLogSubjects(targetBranch string) ([]string, error) {
	ref := fmt.Sprintf("origin/%s..HEAD", targetBranch)
	out, err := exec.Command(
		"git", "log", ref,
		"--no-merges",
		"--pretty=format:%s",
	).Output()
	if err != nil {
		// When range produces no output, git exits 0. If it errors it's a real failure.
		return nil, fmt.Errorf("git log %s: %w", ref, err)
	}
	raw := strings.TrimRight(string(out), "\n")
	if raw == "" {
		return nil, nil
	}
	return strings.Split(raw, "\n"), nil
}

// buildFullPatternForDisplay returns the commit full pattern for the display
// step (showing + / x markers). Same logic as validation.buildFullPattern but
// exposed here to avoid calling into the internal unexported function.
func buildFullPatternForDisplay(cfg *config.Config) interface{ MatchString(string) bool } {
	// We just call ValidateCommits with a single commit to check — simpler than
	// duplicating the regex build. But for display we need the pattern directly.
	// Since validation.buildFullPattern is unexported, we re-derive it here.
	// This is a display-only path; correctness is enforced by ValidateCommits.
	return nil // display all as "+" for now — violations reported separately below
}

func printValidationSuccess(cmd *cobra.Command, cfg *config.Config) {
	if cfg.RequireCommitTypesForAll() {
		ilog.Success("All commits are well-formed")
	} else {
		ilog.Success("Last commit is well-formed")
	}
}

func printValidationErrors(cmd *cobra.Command, cfg *config.Config, issues []validation.Issue, _ []string) {
	typeNames := cfg.CommitTypeNames()
	typesStr := strings.Join(typeNames, ", ")

	if cfg.RequireCommitTypesForAll() {
		ilog.Section("ERROR: COMMITS NOT WELL-FORMED")
		_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
		if cfg.IsConventional() {
			ilog.Info("changelog.mode is 'full' — ALL commits must have a valid type.")
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
			ilog.Info("Each commit must follow Conventional Commits format:")
			ilog.Info("  <type>(scope): <message>  or  <type>: <message>")
		} else {
			ilog.Info("changelog.mode is 'full' — ALL commits must have a valid type.")
			_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
			ilog.Info("Each commit must include a commit type:")
			ilog.Info("  <type>: <message>")
		}
	} else {
		ilog.Section("ERROR: LAST COMMIT NOT WELL-FORMED")
		_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
		if cfg.IsConventional() {
			ilog.Info("The LAST commit must follow Conventional Commits format:")
			ilog.Info("  <type>(scope): <message>  or  <type>: <message>")
		} else {
			ilog.Info("The LAST commit must include a commit type:")
			ilog.Info("  <type>: <message>")
		}
	}

	_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
	ilog.Info("Invalid commits:")
	for _, issue := range issues {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "  x %s\n", issue.Commit)
	}
	_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")

	if typesStr != "" {
		ilog.Info(fmt.Sprintf("Valid types: %s", typesStr))
		_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
	}

	ilog.Info("Examples:")
	if cfg.IsConventional() {
		ilog.Info("  feat(cluster-ecs): add new ECS config")
		ilog.Info("  fix(alb): correct listener rules")
		ilog.Info("  feat: add general feature (no scope)")
	} else {
		ilog.Info("  feat: add new feature")
		ilog.Info("  fix: resolve bug")
	}
	_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "")
}
