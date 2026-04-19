package versioning

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// mergedConfig is the minimal shape of /tmp/.versioning-merged.yml that
// calc-version needs. Full typed loading is GO-09.
type mergedConfig struct {
	CommitTypes []struct {
		Name string   `yaml:"name"`
		Bump BumpType `yaml:"bump"`
	} `yaml:"commit_types"`
	Version struct {
		Components struct {
			Epoch struct {
				Enabled bool `yaml:"enabled"`
				Initial int  `yaml:"initial"`
			} `yaml:"epoch"`
			Major struct {
				Enabled bool `yaml:"enabled"`
				Initial int  `yaml:"initial"`
			} `yaml:"major"`
			Patch struct {
				Enabled bool `yaml:"enabled"`
				Initial int  `yaml:"initial"`
			} `yaml:"patch"`
			HotfixCounter struct {
				Enabled bool `yaml:"enabled"`
				Initial int  `yaml:"initial"`
			} `yaml:"hotfix_counter"`
		} `yaml:"components"`
		TagPrefixV bool `yaml:"tag_prefix_v"`
	} `yaml:"version"`
}

// LoadMergedConfig parses path into BumpConfig + VersionConfig.
func LoadMergedConfig(path string) (BumpConfig, VersionConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return BumpConfig{}, VersionConfig{}, fmt.Errorf("versioning.LoadMergedConfig: %w", err)
	}

	var mc mergedConfig
	if err := yaml.Unmarshal(data, &mc); err != nil {
		return BumpConfig{}, VersionConfig{}, fmt.Errorf("versioning.LoadMergedConfig parse: %w", err)
	}

	bumpCfg := BumpConfig{}
	for _, ct := range mc.CommitTypes {
		bumpCfg.CommitTypes = append(bumpCfg.CommitTypes, CommitType{
			Name: ct.Name,
			Bump: ct.Bump,
		})
	}

	verCfg := VersionConfig{
		EpochEnabled:         mc.Version.Components.Epoch.Enabled,
		EpochInitial:         mc.Version.Components.Epoch.Initial,
		MajorEnabled:         mc.Version.Components.Major.Enabled,
		MajorInitial:         mc.Version.Components.Major.Initial,
		PatchEnabled:         mc.Version.Components.Patch.Enabled,
		PatchInitial:         mc.Version.Components.Patch.Initial,
		HotfixCounterEnabled: mc.Version.Components.HotfixCounter.Enabled,
		HotfixCounterInitial: mc.Version.Components.HotfixCounter.Initial,
		TagPrefixV:           mc.Version.TagPrefixV,
	}

	return bumpCfg, verCfg, nil
}
