package pipeline

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Defaults for file paths written by stages. Exposed so tests can redirect.
const (
	MergedConfigPath = "/tmp/.versioning-merged.yml"
	ScenarioEnvPath  = "/tmp/scenario.env"
	BumpTypePath     = "/tmp/bump_type.txt"
	NextVersionPath  = "/tmp/next_version.txt"
	LatestTagPath    = "/tmp/latest_tag.txt"
)

// Pipeline wires the orchestrator dependencies.
type Pipeline struct {
	// Runner executes individual stages. Default: SelfExecRunner.
	Runner StageRunner
	// Env is the environment accessor. Default: OSEnv{}.
	Env Env
	// Stdout is where the orchestrator writes its own banners (not the
	// stages — those go through Runner). Default: os.Stdout.
	Stdout io.Writer
	// Stderr is where the orchestrator writes error banners. Default: os.Stderr.
	Stderr io.Writer
	// Now returns the current time for tag annotations. Default: time.Now.
	Now func() time.Time
}

// New returns a Pipeline with sensible defaults.
func New() *Pipeline {
	return &Pipeline{
		Runner: &SelfExecRunner{},
		Env:    OSEnv{},
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Now:    time.Now,
	}
}

func (p *Pipeline) stdout() io.Writer {
	if p.Stdout != nil {
		return p.Stdout
	}
	return os.Stdout
}

func (p *Pipeline) stderr() io.Writer {
	if p.Stderr != nil {
		return p.Stderr
	}
	return os.Stderr
}

func (p *Pipeline) env() Env {
	if p.Env != nil {
		return p.Env
	}
	return OSEnv{}
}

func (p *Pipeline) now() time.Time {
	if p.Now != nil {
		return p.Now()
	}
	return time.Now()
}

// Dispatch replaces pipe.sh: runs pre-flight (configure-git + platform
// detection + env mapping + config-parse), then picks PR vs Branch based on
// VERSIONING_PR_ID / VERSIONING_BRANCH.
func (p *Pipeline) Dispatch(ctx context.Context) error {
	if err := p.preflight(ctx); err != nil {
		return err
	}

	env := p.env()
	prID := env.Get("VERSIONING_PR_ID")
	branch := env.Get("VERSIONING_BRANCH")

	switch {
	case prID != "":
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "  VERSIONING PIPE - PR PIPELINE")
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout())
		if err := p.RunPR(ctx); err != nil {
			return err
		}
	case branch != "":
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "  VERSIONING PIPE - BRANCH PIPELINE")
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout())
		if err := p.RunBranch(ctx); err != nil {
			return err
		}
	default:
		_, _ = fmt.Fprintln(p.stderr(), "ERROR: Cannot determine pipeline type")
		_, _ = fmt.Fprintln(p.stderr())
		_, _ = fmt.Fprintln(p.stderr(), "No CI platform detected and no VERSIONING_* variables set.")
		_, _ = fmt.Fprintln(p.stderr(), "Set VERSIONING_PR_ID (for PR pipeline) or VERSIONING_BRANCH (for branch pipeline).")
		_, _ = fmt.Fprintln(p.stderr())
		_, _ = fmt.Fprintln(p.stderr(), "Supported platforms (auto-detected):")
		_, _ = fmt.Fprintln(p.stderr(), "  - Bitbucket Pipelines")
		_, _ = fmt.Fprintln(p.stderr(), "  - GitHub Actions")
		_, _ = fmt.Fprintln(p.stderr())
		_, _ = fmt.Fprintln(p.stderr(), "For other CI systems, set these environment variables manually:")
		_, _ = fmt.Fprintln(p.stderr(), "  VERSIONING_BRANCH        - Current branch name")
		_, _ = fmt.Fprintln(p.stderr(), "  VERSIONING_PR_ID         - Pull request ID (PR pipeline only)")
		_, _ = fmt.Fprintln(p.stderr(), "  VERSIONING_TARGET_BRANCH - PR target branch (PR pipeline only)")
		_, _ = fmt.Fprintln(p.stderr(), "  VERSIONING_COMMIT        - Current commit SHA")
		return errors.New("pipeline: no context (neither VERSIONING_PR_ID nor VERSIONING_BRANCH set)")
	}

	_, _ = fmt.Fprintln(p.stdout())
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	_, _ = fmt.Fprintln(p.stdout(), "  VERSIONING PIPE COMPLETED")
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	return nil
}

// preflight replicates pipe.sh lines 15-60 in the same order:
//  1. git safe.directory (handled as part of configure-git subcommand)
//  2. configure-git (identity, remote auth, fetch)
//  3. platform detection + env mapping
//  4. config-parse (merged config written to /tmp/.versioning-merged.yml)
func (p *Pipeline) preflight(ctx context.Context) error {
	if err := p.runStage(ctx, "configure-git", "configure_git"); err != nil {
		return err
	}

	platform := DetectPlatform(p.env())
	PrintPlatformBanner(p.stdout(), platform)

	if platform == PlatformGitHub && p.env().Get("GITHUB_EVENT_NAME") == "pull_request" {
		LoadGitHubPREventFile(p.env())
	}

	mapping := MapEnv(p.env(), platform)
	if err := mapping.Apply(); err != nil {
		return err
	}

	// config-parse writes /tmp/.versioning-merged.yml that downstream stages
	// (detect-scenario, calc-version, changelog, guardrails, ...) consume.
	if err := p.runStage(ctx, "config-parse", "config_parse"); err != nil {
		return err
	}
	return nil
}

// RunPR executes the PR pipeline, matching pr-pipeline.sh.
func (p *Pipeline) RunPR(ctx context.Context) error {
	// Early exit: target branch must equal tag_on OR be a hotfix_target.
	cfg, err := config.Parse(MergedConfigPath)
	if err != nil {
		return fmt.Errorf("pipeline.pr: load merged config: %w", err)
	}
	tagBranch := cfg.Branches.TagOn
	targetBranch := p.env().Get("VERSIONING_TARGET_BRANCH")

	if targetBranch != tagBranch && !isHotfixTarget(cfg, targetBranch) {
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "  PR PIPELINE SKIPPED")
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintf(p.stdout(), "Target branch: %s\n", targetBranch)
		_, _ = fmt.Fprintln(p.stdout())
		_, _ = fmt.Fprintln(p.stdout(), "PR pipelines only run for PRs targeting:")
		_, _ = fmt.Fprintf(p.stdout(), "  - %s (tag branch)\n", tagBranch)
		if len(cfg.Branches.HotfixTargets) > 0 {
			_, _ = fmt.Fprintf(p.stdout(), "  - configured hotfix_targets (%s)\n",
				strings.Join(cfg.Branches.HotfixTargets, ", "))
		}
		return nil
	}

	// Scenario detection
	if err := p.runStage(ctx, "detect-scenario", "detect_scenario"); err != nil {
		return err
	}

	// Route by scenario
	scenario, _ := readScenario(ScenarioEnvPath)
	switch scenario {
	case "development_release", "hotfix":
		_, _ = fmt.Fprintln(p.stdout())
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintf(p.stdout(), "  PR PIPELINE — %s\n", scenario)
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout())

		if err := p.runStage(ctx, "validate-commits", "validate_commits"); err != nil {
			return err
		}

		_, _ = fmt.Fprintln(p.stdout())
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "  PIPELINE COMPLETED SUCCESSFULLY")
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")

	case "promotion_to_preprod", "promotion_to_main":
		_, _ = fmt.Fprintln(p.stdout())
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "  PROMOTION — NO ACTION NEEDED")
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "This is a promotion PR from one environment to another.")
		_, _ = fmt.Fprintln(p.stdout(), "No changelog or version changes are made during promotions.")

	default:
		_, _ = fmt.Fprintln(p.stdout())
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "  UNKNOWN SCENARIO — NO ACTION")
		_, _ = fmt.Fprintln(p.stdout(), "==========================================")
		_, _ = fmt.Fprintln(p.stdout(), "This PR scenario is not recognized.")
		_, _ = fmt.Fprintln(p.stdout(), "No pipeline action needed.")
	}

	return nil
}

// RunBranch executes the branch pipeline, matching branch-pipeline.sh.
func (p *Pipeline) RunBranch(ctx context.Context) error {
	cfg, err := config.Parse(MergedConfigPath)
	if err != nil {
		return fmt.Errorf("pipeline.branch: load merged config: %w", err)
	}
	tagBranch := cfg.Branches.TagOn
	branch := p.env().Get("VERSIONING_BRANCH")

	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	_, _ = fmt.Fprintln(p.stdout(), "  BRANCH PIPELINE - TAG CREATION")
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	_, _ = fmt.Fprintf(p.stdout(), "Branch: %s\n", branch)
	_, _ = fmt.Fprintln(p.stdout())

	if branch != tagBranch {
		_, _ = fmt.Fprintf(p.stdout(), "Tag creation only runs on %s branch\n", tagBranch)
		_, _ = fmt.Fprintf(p.stdout(), "Current branch: %s\n", branch)
		_, _ = fmt.Fprintln(p.stdout(), "Skipping tag creation")
		return nil
	}

	// Scenario detection — drives hotfix routing in calc-version.
	if err := p.runStage(ctx, "detect-scenario", "detect_scenario"); err != nil {
		return err
	}

	// Calculate version — writes /tmp/next_version.txt + /tmp/bump_type.txt.
	if err := p.runStage(ctx, "calc-version", "calc_version"); err != nil {
		return err
	}

	bumpType, _ := readFileTrim(BumpTypePath)
	if bumpType == "" {
		_, _ = fmt.Fprintln(p.stdout(), "No new commits since last tag - skipping tag creation")
		return nil
	}
	nextTag, _ := readFileTrim(NextVersionPath)
	latestTag, _ := readFileTrim(LatestTagPath)

	_, _ = fmt.Fprintf(p.stdout(), "New tag: %s\n", nextTag)
	_, _ = fmt.Fprintf(p.stdout(), "Bump type: %s\n", bumpType)
	_, _ = fmt.Fprintln(p.stdout())

	// Runtime guardrails — fail the pipeline before any side effect.
	if err := p.runStage(ctx, "run-guardrails", "run_guardrails"); err != nil {
		return err
	}
	_, _ = fmt.Fprintln(p.stdout())

	// CHANGELOG_BASE_REF is consumed by the changelog generators — matches
	// the export in branch-pipeline.sh:81.
	if err := os.Setenv("CHANGELOG_BASE_REF", latestTag); err != nil {
		return fmt.Errorf("pipeline.branch: set CHANGELOG_BASE_REF: %w", err)
	}
	_, _ = fmt.Fprintln(p.stdout())

	if err := p.runStage(ctx, "write-version-file", "write_version_file"); err != nil {
		return err
	}
	_, _ = fmt.Fprintln(p.stdout())

	if err := p.runStage(ctx, "generate-changelog-per-folder", "generate_changelog_per_folder"); err != nil {
		return err
	}
	_, _ = fmt.Fprintln(p.stdout())

	if err := p.runStage(ctx, "generate-changelog-last-commit", "generate_changelog_last_commit"); err != nil {
		return err
	}
	_, _ = fmt.Fprintln(p.stdout())

	if err := p.runStage(ctx, "update-changelog", "update_changelog"); err != nil {
		return err
	}
	_, _ = fmt.Fprintln(p.stdout())

	// Tag creation + atomic push — replicates branch-pipeline.sh:108-124.
	if err := p.createAndPushTag(ctx, nextTag, bumpType, branch); err != nil {
		return err
	}

	// Cleanup flag file (matches branch-pipeline.sh:127).
	_ = os.Remove("/tmp/changelog_committed.flag")

	_, _ = fmt.Fprintln(p.stdout())
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	_, _ = fmt.Fprintln(p.stdout(), "  VERSION TAG CREATED SUCCESSFULLY")
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	if latestTag != "" {
		_, _ = fmt.Fprintf(p.stdout(), "Previous Tag:      %s\n", latestTag)
	} else {
		_, _ = fmt.Fprintln(p.stdout(), "Previous Tag:      none")
	}
	_, _ = fmt.Fprintf(p.stdout(), "New Version:       %s\n", stripTagPrefix(nextTag))
	_, _ = fmt.Fprintf(p.stdout(), "Bump Type:         %s\n", bumpType)
	_, _ = fmt.Fprintf(p.stdout(), "New Tag:           %s\n", nextTag)
	_, _ = fmt.Fprintf(p.stdout(), "Branch:            %s\n", branch)
	return nil
}

// createAndPushTag creates the annotated tag on HEAD (the CHANGELOG commit)
// and pushes both branch and tag atomically. Replicates the bash
// `git tag -a ... -m ...` + git_push_branch_and_tag flow.
func (p *Pipeline) createAndPushTag(ctx context.Context, tag, bumpType, branch string) error {
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	_, _ = fmt.Fprintln(p.stdout(), "  CREATING VERSION TAG")
	_, _ = fmt.Fprintln(p.stdout(), "==========================================")
	_, _ = fmt.Fprintf(p.stdout(), "Tag: %s\n", tag)
	_, _ = fmt.Fprintln(p.stdout())

	head, err := runGit(ctx, "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("pipeline.create_tag: rev-parse HEAD: %w", err)
	}
	head = strings.TrimSpace(head)

	version := stripTagPrefix(tag)
	timestamp := p.now().UTC().Format("2006-01-02 15:04:05 MST")

	args := []string{
		"tag", "-a", tag,
		"-m", fmt.Sprintf("Release version %s (%s)", version, bumpType),
		"-m", "",
		"-m", "Automated by CI pipeline",
		"-m", fmt.Sprintf("Branch: %s", branch),
		"-m", fmt.Sprintf("Commit: %s", head),
		"-m", fmt.Sprintf("Timestamp: %s", timestamp),
	}
	if _, err := runGit(ctx, args...); err != nil {
		return fmt.Errorf("pipeline.create_tag: git tag: %w", err)
	}
	_, _ = fmt.Fprintln(p.stdout(), "✓ Tag created successfully")
	_, _ = fmt.Fprintln(p.stdout())

	_, _ = fmt.Fprintln(p.stdout(), "Pushing CHANGELOG commit and tag atomically...")
	pushArgs := []string{
		"push", "origin",
		fmt.Sprintf("HEAD:refs/heads/%s", branch),
		fmt.Sprintf("refs/tags/%s", tag),
	}
	if _, err := runGit(ctx, pushArgs...); err != nil {
		return fmt.Errorf("pipeline.push_tag: git push: %w", err)
	}
	_, _ = fmt.Fprintf(p.stdout(), "✓ Pushed branch (%s) and tag (%s) atomically\n", branch, tag)
	return nil
}

// runStage delegates to the configured runner and adds a consistent failure
// banner so operators can immediately see which stage blew up.
func (p *Pipeline) runStage(ctx context.Context, subcommand, stage string) error {
	runner := p.Runner
	if runner == nil {
		runner = &SelfExecRunner{}
	}
	if err := runner.Run(ctx, subcommand, stage); err != nil {
		_, _ = fmt.Fprintf(p.stderr(), "\nERROR: pipeline stage %q failed\n", stage)
		return err
	}
	return nil
}

// readScenario reads SCENARIO from a simple KEY=VALUE env file.
func readScenario(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "SCENARIO=") {
			return strings.TrimSpace(strings.TrimPrefix(line, "SCENARIO=")), nil
		}
	}
	return "", nil
}

func readFileTrim(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func stripTagPrefix(tag string) string {
	return strings.TrimPrefix(tag, "v")
}

func isHotfixTarget(cfg *config.Config, branch string) bool {
	if branch == "" {
		return false
	}
	for _, t := range cfg.Branches.HotfixTargets {
		if t == branch {
			return true
		}
	}
	return false
}

func runGit(ctx context.Context, args ...string) (string, error) {
	out, err := exec.CommandContext(ctx, "git", args...).Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}
