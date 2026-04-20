// Package guardrails enforces pre-emission version invariants.
package guardrails

import (
	"fmt"
	"os"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Config holds the subset of the merged versioning config needed by guardrails.
type Config struct {
	Version    VersionConfig    `yaml:"version"`
	Validation ValidationConfig `yaml:"validation"`
}

// VersionConfig mirrors the version.components block.
type VersionConfig struct {
	Components ComponentsConfig `yaml:"components"`
}

// ComponentsConfig describes which version components are enabled.
type ComponentsConfig struct {
	Epoch         ComponentConfig `yaml:"epoch"`
	Major         ComponentConfig `yaml:"major"`
	Patch         ComponentConfig `yaml:"patch"`
	HotfixCounter ComponentConfig `yaml:"hotfix_counter"`
}

// ComponentConfig is a single version component entry.
type ComponentConfig struct {
	Enabled bool `yaml:"enabled"`
}

// ValidationConfig holds validation-section overrides.
type ValidationConfig struct {
	AllowVersionRegression bool `yaml:"allow_version_regression"`
}

// LoadConfig reads the merged config from path via the canonical config.Load
// loader and maps the fields guardrails needs.
func LoadConfig(path string) (Config, error) {
	cfg, err := config.Load(path)
	if err != nil {
		return Config{}, fmt.Errorf("guardrails: %w", err)
	}
	return Config{
		Version: VersionConfig{
			Components: ComponentsConfig{
				Epoch:         ComponentConfig{Enabled: cfg.Version.Components.Epoch.Enabled},
				Major:         ComponentConfig{Enabled: cfg.Version.Components.Major.Enabled},
				Patch:         ComponentConfig{Enabled: cfg.Version.Components.Patch.Enabled},
				HotfixCounter: ComponentConfig{Enabled: cfg.Version.Components.HotfixCounter.Enabled},
			},
		},
		Validation: ValidationConfig{
			AllowVersionRegression: cfg.Validation.AllowVersionRegression,
		},
	}, nil
}

// MergedConfigPath returns the path to the merged config file, preferring the
// PANORA_MERGED_CONFIG env var (used by integration tests) and falling back to
// the canonical /tmp location used in production.
func MergedConfigPath() string {
	if v := os.Getenv("PANORA_MERGED_CONFIG"); v != "" {
		return v
	}
	return "/tmp/.versioning-merged.yml"
}

// StateFilePath returns the effective path for a given state file, preferring
// the env-var override (used by integration tests) and falling back to the
// canonical /tmp location.
func StateFilePath(envVar, defaultPath string) string {
	if v := os.Getenv(envVar); v != "" {
		return v
	}
	return defaultPath
}
