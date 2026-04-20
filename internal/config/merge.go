package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// LoadRaw parses a YAML file into a raw map without applying defaults.
// Returns an empty map if path does not exist (missing .versioning.yml is OK).
func LoadRaw(path string) (map[string]interface{}, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]interface{}{}, nil
		}
		return nil, fmt.Errorf("config: read %s: %w", path, err)
	}
	var m map[string]interface{}
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("config: parse %s: %w", path, err)
	}
	if m == nil {
		m = map[string]interface{}{}
	}
	return m, nil
}

// deepMergeMap merges src into dst.
// Maps are merged recursively (dst wins on conflict only when src has nothing).
// Arrays and scalars from src always override dst (last-wins semantics, matching yq *).
func deepMergeMap(dst, src map[string]interface{}) map[string]interface{} {
	result := make(map[string]interface{}, len(dst))
	for k, v := range dst {
		result[k] = v
	}
	for k, sv := range src {
		if dv, ok := result[k]; ok {
			// Both sides have this key.
			dstMap, dstIsMap := dv.(map[string]interface{})
			srcMap, srcIsMap := sv.(map[string]interface{})
			if dstIsMap && srcIsMap {
				// Both are maps → recurse.
				result[k] = deepMergeMap(dstMap, srcMap)
				continue
			}
		}
		// Scalar, array, or only one side has the key → src wins.
		result[k] = sv
	}
	return result
}

// mergeRaw deep-merges a sequence of raw maps, left to right (later wins).
func mergeRaw(sources ...map[string]interface{}) map[string]interface{} {
	result := map[string]interface{}{}
	for _, src := range sources {
		if src == nil {
			continue
		}
		result = deepMergeMap(result, src)
	}
	return result
}

// LoadAndMerge loads commit-types.yml, defaults.yml, and optionally
// .versioning.yml, merges them (commit-types → defaults → user), applies
// commit_type_overrides, and returns a fully-typed *Config.
//
// Merge order matches bash config-parser.sh:
//   select(fileIndex==0) * select(fileIndex==1) * select(fileIndex==2)
//   => commit-types.yml * defaults.yml * .versioning.yml
//
// For maps: later files override earlier (yq * semantics).
// For arrays: later file replaces earlier entirely (yq * semantics).
func LoadAndMerge(commitTypesPath, defaultsPath, userConfigPath string) (*Config, error) {
	commitTypesRaw, err := LoadRaw(commitTypesPath)
	if err != nil {
		return nil, fmt.Errorf("config: merging commit-types: %w", err)
	}
	if len(commitTypesRaw) == 0 {
		return nil, fmt.Errorf("config: commit-types.yml not found at %s", commitTypesPath)
	}

	defaultsRaw, err := LoadRaw(defaultsPath)
	if err != nil {
		return nil, fmt.Errorf("config: merging defaults: %w", err)
	}
	if len(defaultsRaw) == 0 {
		return nil, fmt.Errorf("config: defaults.yml not found at %s", defaultsPath)
	}

	userRaw, err := LoadRaw(userConfigPath)
	if err != nil {
		return nil, fmt.Errorf("config: merging user config: %w", err)
	}

	merged := mergeRaw(commitTypesRaw, defaultsRaw, userRaw)

	// Round-trip through YAML to get a clean typed *Config.
	data, err := yaml.Marshal(merged)
	if err != nil {
		return nil, fmt.Errorf("config: marshal merged: %w", err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("config: unmarshal merged: %w", err)
	}

	if err := ApplyOverrides(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// ApplyOverrides patches cfg.CommitTypes using cfg.CommitTypeOverrides.
// For each override entry:
//   - If a commit type with matching name exists → update its fields.
//   - If no match → append as a new commit type.
//
// This mirrors apply_commit_type_overrides() in config-parser.sh.
func ApplyOverrides(cfg *Config) error {
	if len(cfg.CommitTypeOverrides) == 0 {
		return nil
	}

	// Build index by name for O(1) lookup.
	idx := make(map[string]int, len(cfg.CommitTypes))
	for i, ct := range cfg.CommitTypes {
		idx[ct.Name] = i
	}

	for name, override := range cfg.CommitTypeOverrides {
		if i, exists := idx[name]; exists {
			// Patch existing type — only update non-empty override fields.
			if override.Bump != "" {
				cfg.CommitTypes[i].Bump = override.Bump
			}
			if override.Emoji != "" {
				cfg.CommitTypes[i].Emoji = override.Emoji
			}
			if override.ChangelogGroup != "" {
				cfg.CommitTypes[i].ChangelogGroup = override.ChangelogGroup
			}
		} else {
			// Append new type.
			cfg.CommitTypes = append(cfg.CommitTypes, CommitType{
				Name:           name,
				Bump:           override.Bump,
				Emoji:          override.Emoji,
				ChangelogGroup: override.ChangelogGroup,
			})
			idx[name] = len(cfg.CommitTypes) - 1
		}
	}

	return nil
}

// WriteMergedConfig serializes cfg to YAML and writes it to path.
// The output is consumed by other Go subcommands and bash scripts via
// getters in config-parser.sh (for dual-run compatibility during migration).
func WriteMergedConfig(cfg *Config, path string) error {
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("config: serialize merged: %w", err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("config: write merged %s: %w", path, err)
	}
	return nil
}
