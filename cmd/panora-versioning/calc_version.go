package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/gitops"
	ulog "github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/state"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/versioning"
)

func newCalcVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "calc-version",
		Short: "Calculate the next semantic version",
		RunE:  runCalcVersion,
	}
}

func runCalcVersion(_ *cobra.Command, _ []string) error {
	ulog.Section("CALCULATING VERSION")

	// ── Load merged config ──────────────────────────────────────────────────
	bumpCfg, verCfg, err := versioning.LoadMergedConfig(mergedConfigPath)
	if err != nil {
		ulog.Error("loading config", err)
		os.Exit(1)
	}

	// ── Load scenario env ───────────────────────────────────────────────────
	scenario := "development_release"
	if envVars, envErr := state.LoadEnv(scenarioEnvPath); envErr == nil {
		if s, ok := envVars["SCENARIO"]; ok && s != "" {
			scenario = s
		}
	}

	// ── Open git repo ───────────────────────────────────────────────────────
	repo, err := gitops.Open(".")
	if err != nil {
		ulog.Error("opening git repo", err)
		os.Exit(2)
	}

	// ── Find latest tag in namespace ────────────────────────────────────────
	nsFilter := versioning.LatestTagFilter(verCfg)
	latestTag, err := repo.LatestTag(nsFilter)
	if err != nil {
		ulog.Error("finding latest tag", err)
		os.Exit(2)
	}

	if err := state.WriteLine(latestTagPath, latestTag); err != nil {
		ulog.Error("writing latest_tag.txt", err)
		os.Exit(1)
	}

	if latestTag == "" {
		ulog.Info("No version tags found, starting from initial values")
	} else {
		ulog.Info(fmt.Sprintf("Latest tag: %s", latestTag))
	}

	// ── Determine commit range ──────────────────────────────────────────────
	targetBranch := os.Getenv("VERSIONING_TARGET_BRANCH")
	var commitRange string
	if targetBranch != "" {
		commitRange = fmt.Sprintf("origin/%s..HEAD", targetBranch)
		ulog.Info(fmt.Sprintf("Context: PR (target: %s)", targetBranch))
	} else if latestTag != "" {
		commitRange = fmt.Sprintf("%s..HEAD", latestTag)
		ulog.Info(fmt.Sprintf("Context: Branch (since tag: %s)", latestTag))
	} else {
		commitRange = "HEAD"
		ulog.Info("Context: Branch (no previous tags, using all commits)")
	}

	// ── Get commits ─────────────────────────────────────────────────────────
	rawCommits, err := commitsInRange(repo, commitRange)
	if err != nil {
		ulog.Error("reading commits", err)
		os.Exit(2)
	}

	commits := toVersioningCommits(rawCommits)

	if len(commits) == 0 {
		ulog.Info("No new commits found - skipping version calculation")
		if wErr := state.WriteLine(nextVersionPath, ""); wErr != nil {
			ulog.Error("writing next_version.txt", wErr)
			os.Exit(1)
		}
		if wErr := state.WriteLine(bumpTypePath, ""); wErr != nil {
			ulog.Error("writing bump_type.txt", wErr)
			os.Exit(1)
		}
		return nil
	}

	// ── Hotfix scenario ─────────────────────────────────────────────────────
	var bump versioning.BumpType
	if scenario == "hotfix" {
		if verCfg.HotfixCounterEnabled {
			bump = versioning.BumpHotfix
			ulog.Info("Detected: HOTFIX bump (hotfix scenario)")
		} else {
			ulog.Info("Hotfix scenario but hotfix_counter.enabled=false — skipping tag creation")
			if wErr := state.WriteLine(nextVersionPath, ""); wErr != nil {
				ulog.Error("writing next_version.txt", wErr)
				os.Exit(1)
			}
			if wErr := state.WriteLine(bumpTypePath, ""); wErr != nil {
				ulog.Error("writing bump_type.txt", wErr)
				os.Exit(1)
			}
			return nil
		}
	} else {
		bump = versioning.DetermineBump(commits, bumpCfg)
		ulog.Info(fmt.Sprintf("Detected bump: %s", bump))
	}

	// ── bump=none → no version file ─────────────────────────────────────────
	if bump == versioning.BumpNone {
		ulog.Info("No version bump (commit type has bump: none)")
		if wErr := state.WriteLine(nextVersionPath, ""); wErr != nil {
			ulog.Error("writing next_version.txt", wErr)
			os.Exit(1)
		}
		if wErr := state.WriteLine(bumpTypePath, ""); wErr != nil {
			ulog.Error("writing bump_type.txt", wErr)
			os.Exit(1)
		}
		return nil
	}

	// ── Compute next version ────────────────────────────────────────────────
	nextVer, err := versioning.NextVersion(latestTag, bump, verCfg)
	if err != nil {
		ulog.Error("computing next version", err)
		os.Exit(1)
	}

	ulog.Info(fmt.Sprintf("Next version will be: %s", nextVer))

	// ── Write outputs ───────────────────────────────────────────────────────
	if wErr := state.WriteLine(nextVersionPath, nextVer); wErr != nil {
		ulog.Error("writing next_version.txt", wErr)
		os.Exit(1)
	}
	ulog.Info(fmt.Sprintf("Wrote %s", nextVersionPath))

	if wErr := state.WriteLine(bumpTypePath, string(bump)); wErr != nil {
		ulog.Error("writing bump_type.txt", wErr)
		os.Exit(1)
	}
	ulog.Info(fmt.Sprintf("Wrote %s", bumpTypePath))

	ulog.Success("Version calculation complete")
	return nil
}

func toVersioningCommits(raw []gitops.Commit) []versioning.Commit {
	out := make([]versioning.Commit, 0, len(raw))
	for _, c := range raw {
		out = append(out, versioning.Commit{Subject: c.Subject, Body: c.Body})
	}
	return out
}

// commitsInRange parses a git range string ("from..to" or bare "ref") and
// delegates to the appropriate gitops method.
func commitsInRange(repo *gitops.Repo, rangeStr string) ([]gitops.Commit, error) {
	if idx := strings.Index(rangeStr, ".."); idx >= 0 {
		from := rangeStr[:idx]
		to := rangeStr[idx+2:]
		return repo.CommitsBetween(from, to)
	}
	return repo.CommitsOn(rangeStr)
}
