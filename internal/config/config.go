// Package config loads and exposes the merged .versioning.yml configuration.
package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

const MergedConfigPath = "/tmp/.versioning-merged.yml"

// CommitType represents one entry from the commit_types array.
type CommitType struct {
	Name           string `yaml:"name"`
	Bump           string `yaml:"bump"`
	Emoji          string `yaml:"emoji,omitempty"`
	ChangelogGroup string `yaml:"changelog_group,omitempty"`
}

// CommitTypeOverride holds partial overrides for a commit type.
type CommitTypeOverride struct {
	Bump           string `yaml:"bump,omitempty"`
	Emoji          string `yaml:"emoji,omitempty"`
	ChangelogGroup string `yaml:"changelog_group,omitempty"`
}

// ComponentConfig describes a version component (epoch, major, patch, etc.).
type ComponentConfig struct {
	Enabled bool `yaml:"enabled"`
	Initial int  `yaml:"initial"`
}

// TimestampComponent extends ComponentConfig with format and timezone.
type TimestampComponent struct {
	Enabled  bool   `yaml:"enabled"`
	Format   string `yaml:"format"`
	Timezone string `yaml:"timezone"`
}

// VersionComponents holds all version component configs.
type VersionComponents struct {
	Epoch         ComponentConfig    `yaml:"epoch"`
	Major         ComponentConfig    `yaml:"major"`
	Patch         ComponentConfig    `yaml:"patch"`
	HotfixCounter ComponentConfig    `yaml:"hotfix_counter"`
	Timestamp     TimestampComponent `yaml:"timestamp"`
}

// VersionSeparators holds separator strings.
type VersionSeparators struct {
	Version   string `yaml:"version"`
	Timestamp string `yaml:"timestamp"`
	TagAppend string `yaml:"tag_append"`
}

// VersionConfig holds the full version section.
type VersionConfig struct {
	Components VersionComponents `yaml:"components"`
	TagPrefixV bool              `yaml:"tag_prefix_v"`
	Separators VersionSeparators `yaml:"separators"`
}

// PerFolderConfig holds the changelog.per_folder section.
type PerFolderConfig struct {
	Enabled            bool     `yaml:"enabled"`
	Folders            []string `yaml:"folders"`
	FolderPattern      string   `yaml:"folder_pattern"`
	ScopeMatching      string   `yaml:"scope_matching"`
	ScopeMatchingDepth int      `yaml:"scope_matching_depth"`
	Fallback           string   `yaml:"fallback"`
}

// ChangelogConfig holds the changelog section.
type ChangelogConfig struct {
	File              string          `yaml:"file"`
	Title             string          `yaml:"title"`
	Mode              string          `yaml:"mode"`
	UseEmojis         bool            `yaml:"use_emojis"`
	IncludeCommitLink bool            `yaml:"include_commit_link"`
	IncludeTicketLink bool            `yaml:"include_ticket_link"`
	IncludeAuthor     bool            `yaml:"include_author"`
	CommitURL         string          `yaml:"commit_url"`
	TicketLinkLabel   string          `yaml:"ticket_link_label"`
	PerFolder         PerFolderConfig `yaml:"per_folder"`
}

// ValidationConfig holds the validation section.
type ValidationConfig struct {
	RequireTicketPrefix bool `yaml:"require_ticket_prefix"`
	// RequireCommitTypes uses *bool so we can distinguish "not set" (nil → default true)
	// from explicitly set to false. yaml.v3 zero-value for bool is false, which would
	// shadow the default-true behavior.
	RequireCommitTypes     *bool    `yaml:"require_commit_types"`
	HotfixTitleRequired    string   `yaml:"hotfix_title_required"`
	AllowVersionRegression bool     `yaml:"allow_version_regression"`
	IgnorePatterns         []string `yaml:"ignore_patterns"`
}

// TicketsConfig holds the tickets section.
type TicketsConfig struct {
	Prefixes []string `yaml:"prefixes"`
	Required bool     `yaml:"required"`
	URL      string   `yaml:"url"`
}

// CommitsConfig holds the commits section.
type CommitsConfig struct {
	Format string `yaml:"format"`
}

// BranchesConfig holds the branches section.
type BranchesConfig struct {
	TagOn         string   `yaml:"tag_on"`
	HotfixTargets []string `yaml:"hotfix_targets"`
}

// VersionFileEntry is a single file entry inside a version_file group.
type VersionFileEntry struct {
	Path    string `yaml:"path"`
	Pattern string `yaml:"pattern,omitempty"`
}

// VersionFileGroup describes a group of files to update on version bump.
type VersionFileGroup struct {
	Name         string   `yaml:"name"`
	TriggerPaths []string `yaml:"trigger_paths,omitempty"`
	Files        []string `yaml:"files"`
	UpdateAll    bool     `yaml:"update_all,omitempty"`
}

// VersionFileConfig holds the version_file section.
type VersionFileConfig struct {
	Enabled                bool               `yaml:"enabled"`
	Type                   string             `yaml:"type,omitempty"`
	Pattern                string             `yaml:"pattern,omitempty"`
	Replacement            string             `yaml:"replacement,omitempty"`
	Groups                 []VersionFileGroup `yaml:"groups"`
	UnmatchedFilesBehavior string             `yaml:"unmatched_files_behavior,omitempty"`
}

// HotfixKeywordList handles the yaml field that can be a string or []string.
type HotfixKeywordList struct {
	Values []string
}

func (h *HotfixKeywordList) UnmarshalYAML(value *yaml.Node) error {
	switch value.Kind {
	case yaml.ScalarNode:
		h.Values = []string{value.Value}
	case yaml.SequenceNode:
		var ss []string
		if err := value.Decode(&ss); err != nil {
			return err
		}
		h.Values = ss
	default:
		return fmt.Errorf("hotfix.keyword: unexpected YAML node kind %v", value.Kind)
	}
	return nil
}

// HotfixConfig holds the hotfix section.
type HotfixConfig struct {
	Keyword HotfixKeywordList `yaml:"keyword"`
}

// TeamsNotificationConfig holds the notifications.teams section.
type TeamsNotificationConfig struct {
	Enabled   bool   `yaml:"enabled"`
	OnSuccess bool   `yaml:"on_success"`
	OnFailure bool   `yaml:"on_failure"`
	Webhook   string `yaml:"webhook,omitempty"`
}

// NotificationsConfig holds the notifications section.
type NotificationsConfig struct {
	Teams TeamsNotificationConfig `yaml:"teams"`
}

// Config is the fully-typed representation of the merged versioning config.
type Config struct {
	Commits             CommitsConfig                 `yaml:"commits"`
	Tickets             TicketsConfig                 `yaml:"tickets"`
	Validation          ValidationConfig              `yaml:"validation"`
	Version             VersionConfig                 `yaml:"version"`
	Changelog           ChangelogConfig               `yaml:"changelog"`
	CommitTypes         []CommitType                  `yaml:"commit_types"`
	CommitTypeOverrides map[string]CommitTypeOverride `yaml:"commit_type_overrides"`
	Hotfix              HotfixConfig                  `yaml:"hotfix"`
	Branches            BranchesConfig                `yaml:"branches"`
	VersionFile         VersionFileConfig             `yaml:"version_file"`
	Notifications       NotificationsConfig           `yaml:"notifications"`
}

// Load parses the YAML file at path into a Config and applies defaults.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("config.Load %s: %w", path, err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("config.Load unmarshal %s: %w", path, err)
	}
	cfg.Defaults()
	return &cfg, nil
}

// Defaults fills zero-values with the documented defaults from defaults.yml.
func (c *Config) Defaults() {
	if c.Commits.Format == "" {
		c.Commits.Format = "ticket"
	}

	// Validation defaults
	if c.Validation.HotfixTitleRequired == "" {
		c.Validation.HotfixTitleRequired = "error"
	}
	// require_commit_types defaults to true when not explicitly set in YAML.
	if c.Validation.RequireCommitTypes == nil {
		t := true
		c.Validation.RequireCommitTypes = &t
	}
	if len(c.Validation.IgnorePatterns) == 0 {
		c.Validation.IgnorePatterns = []string{
			`^Merge`,
			`^Revert`,
			`^fixup!`,
			`^squash!`,
			`^chore\(release\)`,
			`^chore\(hotfix\)`,
		}
	}

	// Changelog defaults
	if c.Changelog.File == "" {
		c.Changelog.File = "CHANGELOG.md"
	}
	if c.Changelog.Title == "" {
		c.Changelog.Title = "Changelog"
	}
	if c.Changelog.Mode == "" {
		c.Changelog.Mode = "last_commit"
	}
	if c.Changelog.TicketLinkLabel == "" {
		c.Changelog.TicketLinkLabel = "View ticket"
	}
	// include_* default to true
	if !c.Changelog.IncludeCommitLink {
		c.Changelog.IncludeCommitLink = true
	}
	if !c.Changelog.IncludeTicketLink {
		c.Changelog.IncludeTicketLink = true
	}
	if !c.Changelog.IncludeAuthor {
		c.Changelog.IncludeAuthor = true
	}
	// per_folder defaults
	if c.Changelog.PerFolder.ScopeMatchingDepth == 0 {
		c.Changelog.PerFolder.ScopeMatchingDepth = 2
	}

	// Version component defaults (from defaults.yml)
	if !c.versionExplicitlySet() {
		c.Version.Components.Major.Enabled = true
		c.Version.Components.Patch.Enabled = true
		c.Version.Components.HotfixCounter.Enabled = true
	}
	if c.Version.Components.Timestamp.Format == "" {
		c.Version.Components.Timestamp.Format = "%Y%m%d%H%M%S"
	}
	if c.Version.Components.Timestamp.Timezone == "" {
		c.Version.Components.Timestamp.Timezone = "UTC"
	}
	if c.Version.Separators.Version == "" {
		c.Version.Separators.Version = "."
	}
	if c.Version.Separators.Timestamp == "" {
		c.Version.Separators.Timestamp = "."
	}

	// Branches defaults
	if c.Branches.TagOn == "" {
		c.Branches.TagOn = "development"
	}
	if len(c.Branches.HotfixTargets) == 0 {
		c.Branches.HotfixTargets = []string{"main", "pre-production"}
	}

	// Hotfix keyword defaults
	if len(c.Hotfix.Keyword.Values) == 0 {
		c.Hotfix.Keyword.Values = []string{"hotfix:*", "hotfix(*", "[Hh]otfix/*"}
	}

	// Notifications defaults
	if !c.Notifications.Teams.Enabled {
		c.Notifications.Teams.Enabled = true
		c.Notifications.Teams.OnFailure = true
	}
}

// versionExplicitlySet returns true when any version component was explicitly
// configured in YAML (i.e. the version block is non-zero).
func (c *Config) versionExplicitlySet() bool {
	v := c.Version
	return v.TagPrefixV ||
		v.Components.Epoch.Enabled || v.Components.Epoch.Initial != 0 ||
		v.Components.Major.Enabled || v.Components.Major.Initial != 0 ||
		v.Components.Patch.Enabled || v.Components.Patch.Initial != 0 ||
		v.Components.HotfixCounter.Enabled || v.Components.HotfixCounter.Initial != 0 ||
		v.Components.Timestamp.Enabled
}

// IsConventional returns true when commits.format is "conventional".
func (c *Config) IsConventional() bool {
	return c.Commits.Format == "conventional"
}

// RequireCommitTypes returns the require_commit_types flag (default: true).
func (c *Config) RequireCommitTypes() bool {
	if c.Validation.RequireCommitTypes == nil {
		return true
	}
	return *c.Validation.RequireCommitTypes
}

// RequireCommitTypesForAll returns true when require_commit_types is on and
// changelog.mode is "full" (all commits must be typed, not just the last).
func (c *Config) RequireCommitTypesForAll() bool {
	return c.RequireCommitTypes() && c.Changelog.Mode == "full"
}

// CommitTypeNames returns the list of valid commit type names from commit_types.
func (c *Config) CommitTypeNames() []string {
	names := make([]string, 0, len(c.CommitTypes))
	for _, ct := range c.CommitTypes {
		names = append(names, ct.Name)
	}
	return names
}

// HotfixKeywords returns the hotfix keyword patterns as a slice of strings.
func (c *Config) HotfixKeywords() []string {
	return c.Hotfix.Keyword.Values
}

// TicketPrefixesPattern returns a pipe-joined regex alternation of ticket
// prefixes, e.g. "AM|TECH", or "" if none are configured.
func (c *Config) TicketPrefixesPattern() string {
	return strings.Join(c.Tickets.Prefixes, "|")
}
