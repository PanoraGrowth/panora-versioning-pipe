package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"

	internalconfig "github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/reporting"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

func newNotifyTeamsCmd() *cobra.Command {
	return &cobra.Command{
		Use:           "notify-teams <success|failure>",
		Short:         "Send a Microsoft Teams notification",
		Args:          cobra.ExactArgs(1),
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runNotifyTeams(cmd.Context(), args[0])
		},
	}
}

// notifConfig mirrors the relevant subset of .versioning-merged.yml.
type notifConfig struct {
	Notifications struct {
		Teams reporting.TeamsConfig `yaml:"teams"`
	} `yaml:"notifications"`
}

func runNotifyTeams(ctx context.Context, triggerType string) error {
	if ctx == nil {
		ctx = context.Background()
	}

	if triggerType != "success" && triggerType != "failure" {
		return fmt.Errorf("notify-teams: invalid trigger type %q — must be 'success' or 'failure'", triggerType)
	}

	cfg, err := loadNotifConfig()
	if err != nil {
		return err
	}

	if !cfg.Notifications.Teams.Enabled {
		log.Plain("Teams notifications are disabled in configuration")
		return nil
	}

	switch triggerType {
	case "success":
		if !cfg.Notifications.Teams.OnSuccess {
			log.Plain("Teams notification on success is disabled")
			return nil
		}
	case "failure":
		if !cfg.Notifications.Teams.OnFailure {
			log.Plain("Teams notification on failure is disabled")
			return nil
		}
	}

	webhookURL := os.Getenv("TEAMS_WEBHOOK_URL")
	if webhookURL == "" {
		log.Plain("Warning: TEAMS_WEBHOOK_URL not configured, skipping notification")
		return nil
	}

	templatePath := cfg.Notifications.Teams.PayloadTemplate
	if templatePath == "" {
		templatePath = resolveTemplatePath()
	}
	if _, err := os.Stat(templatePath); err != nil {
		return fmt.Errorf("notify-teams: payload template not found: %s", templatePath)
	}

	vars := buildTeamsVars(triggerType)

	log.Plain(fmt.Sprintf("Sending Teams notification (%s)...", triggerType))

	statusCode, err := reporting.SendTeamsNotificationWithStatus(ctx, webhookURL, templatePath, vars)
	if err != nil {
		// network failure — bash warned and exited 0
		log.Warn(fmt.Sprintf("Teams notification failed: %v", err))
		return nil
	}

	if statusCode == 200 || statusCode == 202 {
		log.Plain("Teams notification sent successfully")
	} else {
		log.Warn(fmt.Sprintf("Teams notification HTTP status: %d", statusCode))
	}

	return nil
}

func loadNotifConfig() (notifConfig, error) {
	cfgPath := "/tmp/.versioning-merged.yml"
	if v := os.Getenv("PANORA_MERGED_CONFIG"); v != "" {
		cfgPath = v
	}

	if _, err := os.Stat(cfgPath); os.IsNotExist(err) {
		// No merged config yet — return struct with Go zero values.
		// Notifications.Teams.Enabled defaults to false → notifications skipped.
		return notifConfig{}, nil
	}

	// Use Parse (no defaults) — the merged config already has all values set.
	// Load() applies Defaults() which can overwrite explicit enabled:false.
	canonical, err := internalconfig.Parse(cfgPath)
	if err != nil {
		return notifConfig{}, fmt.Errorf("notify-teams: %w", err)
	}

	var cfg notifConfig
	cfg.Notifications.Teams.Enabled = canonical.Notifications.Teams.Enabled
	cfg.Notifications.Teams.OnSuccess = canonical.Notifications.Teams.OnSuccess
	cfg.Notifications.Teams.OnFailure = canonical.Notifications.Teams.OnFailure
	// PayloadTemplate not in config schema — stays empty (resolved via resolveTemplatePath).
	return cfg, nil
}

func resolveTemplatePath() string {
	candidates := []string{
		"/pipe/reporting/templates/webhook_pipeline_payload.json",
		"/tmp/webhook_payload.json",
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return candidates[0]
}

func buildTeamsVars(triggerType string) reporting.TeamsVars {
	commit := os.Getenv("VERSIONING_COMMIT")
	if len(commit) == 0 {
		commit = "unknown"
	}
	commitShort := commit
	if len(commitShort) > 7 {
		commitShort = commitShort[:7]
	}

	author := gitCommitAuthor()

	vars := reporting.TeamsVars{
		BitbucketRepoSlug:    os.Getenv("BITBUCKET_REPO_SLUG"),
		BitbucketBranch:      envOrDefault("BITBUCKET_BRANCH", os.Getenv("VERSIONING_BRANCH")),
		BitbucketPRID:        envOrDefault("BITBUCKET_PR_ID", os.Getenv("VERSIONING_PR_ID")),
		BitbucketCommitShort: commitShort,
		BitbucketPRAuthor:    author,
		BitbucketWorkspace:   os.Getenv("BITBUCKET_WORKSPACE"),
		BitbucketBuildNumber: os.Getenv("BITBUCKET_BUILD_NUMBER"),
	}

	if triggerType == "success" {
		vars.NotificationStyle = "accent"
		vars.NotificationIcon = "https://cdn-icons-png.flaticon.com/512/845/845646.png"
		vars.NotificationTitle = "✅ Pipeline Successful"
		vars.NotificationSubtitle = "PR validation completed"
	} else {
		vars.NotificationStyle = "attention"
		vars.NotificationIcon = "https://cdn-icons-png.flaticon.com/512/1828/1828665.png"
		vars.NotificationTitle = "❌ Pipeline Failed"
		vars.NotificationSubtitle = "Commit validation failed"
	}

	return vars
}

func gitCommitAuthor() string {
	out, err := exec.Command("git", "log", "-1", "--format=%an").Output()
	if err != nil {
		return "N/A"
	}
	return strings.TrimSpace(string(out))
}
