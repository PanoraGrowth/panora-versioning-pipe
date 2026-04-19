// Package config loads and exposes the merged .versioning.yml configuration.
// This is a minimal loader scoped to the fields that Wave 1 subcommands need.
// The full config-parser port (wave N) will extend this package.
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
	Name string `yaml:"name"`
	Bump string `yaml:"bump"`
}

// Config is the minimal representation of the merged versioning config.
type Config struct {
	Commits struct {
		Format string `yaml:"format"` // "conventional" or "ticket"
	} `yaml:"commits"`

	Tickets struct {
		Prefixes []string `yaml:"prefixes"`
		Required bool     `yaml:"required"`
	} `yaml:"tickets"`

	Validation struct {
		RequireCommitTypes  bool     `yaml:"require_commit_types"`
		IgnorePatterns      []string `yaml:"ignore_patterns"`
		HotfixTitleRequired string   `yaml:"hotfix_title_required"`
	} `yaml:"validation"`

	Changelog struct {
		Mode string `yaml:"mode"` // "last_commit" or "full"
	} `yaml:"changelog"`

	CommitTypes []CommitType `yaml:"commit_types"`

	Hotfix struct {
		Keyword interface{} `yaml:"keyword"` // string or []string
	} `yaml:"hotfix"`
}

// Load parses the YAML file at path into a Config.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("config.Load %s: %w", path, err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("config.Load unmarshal %s: %w", path, err)
	}
	applyDefaults(&cfg)
	return &cfg, nil
}

func applyDefaults(c *Config) {
	if c.Commits.Format == "" {
		c.Commits.Format = "ticket"
	}
	if c.Changelog.Mode == "" {
		c.Changelog.Mode = "last_commit"
	}
	// require_commit_types defaults to true when not set
	// yaml.v3 zero-value for bool is false, so we can't distinguish
	// "not set" from "false" without a pointer. We preserve the parsed value
	// as-is; callers that need the default must use LoadWithDefaults.

	if c.Validation.HotfixTitleRequired == "" {
		c.Validation.HotfixTitleRequired = "error"
	}
}

// IsConventional returns true when commits.format is "conventional".
func (c *Config) IsConventional() bool {
	return c.Commits.Format == "conventional"
}

// RequireCommitTypes returns the require_commit_types flag.
func (c *Config) RequireCommitTypes() bool {
	return c.Validation.RequireCommitTypes
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
	if c.Hotfix.Keyword == nil {
		return []string{"hotfix:*", "hotfix(*", "[Hh]otfix/*"}
	}
	switch v := c.Hotfix.Keyword.(type) {
	case string:
		return []string{v + ":*", v + "(*"}
	case []interface{}:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				out = append(out, s)
			}
		}
		return out
	}
	return nil
}

// TicketPrefixesPattern returns a pipe-joined regex alternation of ticket
// prefixes, e.g. "AM|TECH", or "" if none are configured.
func (c *Config) TicketPrefixesPattern() string {
	return strings.Join(c.Tickets.Prefixes, "|")
}
