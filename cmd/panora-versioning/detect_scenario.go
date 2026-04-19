package main

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/detection"
	ulog "github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

const (
	scenarioEnvPath  = "/tmp/scenario.env"
	mergedConfigPath = "/tmp/.versioning-merged.yml"
)

func newDetectScenarioCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "detect-scenario",
		Short: "Detect the pipeline scenario",
		RunE:  runDetectScenario,
	}
}

func runDetectScenario(_ *cobra.Command, _ []string) error {
	ulog.Section("DETECTING PIPELINE SCENARIO")

	sourceBranch := os.Getenv("VERSIONING_BRANCH")
	targetBranch := os.Getenv("VERSIONING_TARGET_BRANCH")
	commit := os.Getenv("VERSIONING_COMMIT")
	if commit == "" {
		commit = "HEAD"
	}

	ulog.Info("Source Branch: " + sourceBranch)
	if targetBranch != "" {
		ulog.Info("Target Branch: " + targetBranch)
	} else {
		ulog.Info("Target Branch: <branch context>")
	}
	ulog.Plain("")

	workDir, err := os.Getwd()
	if err != nil {
		ulog.Error("getting working directory", err)
		os.Exit(1)
	}

	cfgPath, err := detection.FindConfig(workDir)
	if err != nil {
		ulog.Error("finding config", err)
		os.Exit(1)
	}

	cfg, err := detection.LoadConfig(cfgPath)
	if err != nil {
		ulog.Error("loading config", err)
		os.Exit(1)
	}

	ulog.Info("Hotfix branch prefix: " + cfg.HotfixBranchPrefix())

	ctx := detection.DetectContext{
		SourceBranch: sourceBranch,
		TargetBranch: targetBranch,
		Commit:       commit,
		WorkDir:      workDir,
		Config:       cfg,
	}

	scenario, err := detection.Detect(ctx)
	if err != nil {
		ulog.Error("detecting scenario", err)
		os.Exit(1)
	}

	ulog.Info("Scenario: " + scenarioLabel(scenario.Kind))

	if err := detection.WriteEnvFile(scenarioEnvPath, scenario); err != nil {
		ulog.Error("writing scenario.env", err)
		os.Exit(1)
	}
	ulog.Info("Wrote " + scenarioEnvPath)

	ulog.Plain("")
	return nil
}

func scenarioLabel(k detection.Kind) string {
	switch k {
	case detection.KindDevelopmentRelease:
		return "Development Release (Changelog + Tag)"
	case detection.KindHotfix:
		return "Hotfix (Changelog + Tag)"
	case detection.KindPromotionToMain:
		return "Promotion (No action)"
	default:
		return "Unknown - No pipeline action"
	}
}
