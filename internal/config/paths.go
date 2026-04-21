package config

import (
	"fmt"
	"os"
	"path/filepath"
)

// DefaultsDir is the Docker runtime path where bundled YAML defaults live.
// Override with PANORA_DEFAULTS_DIR for tests or non-container runs.
const DefaultsDir = "/etc/panora/defaults"

// DefaultsDirEnv is the env var override for DefaultsDir. Takes precedence
// over the baked-in path when set and non-empty.
const DefaultsDirEnv = "PANORA_DEFAULTS_DIR"

// CommitTypesFile and DefaultsFile are the bundled YAML filenames under DefaultsDir.
const (
	CommitTypesFile = "commit-types.yml"
	DefaultsFile    = "defaults.yml"
)

// ResolveBundledFile locates a bundled YAML file (commit-types.yml or
// defaults.yml). Search order:
//  1. $PANORA_DEFAULTS_DIR/<name>  (env override for tests and local dev)
//  2. DefaultsDir/<name>            (Docker runtime — /etc/panora/defaults/)
//  3. <exeDir>/../config/defaults/<name>   (local binary next to repo)
//  4. <exeDir>/config/defaults/<name>      (packaged binary layout)
func ResolveBundledFile(name string) (string, error) {
	var candidates []string

	if dir := os.Getenv(DefaultsDirEnv); dir != "" {
		candidates = append(candidates, filepath.Join(dir, name))
	}
	candidates = append(candidates, filepath.Join(DefaultsDir, name))

	if exePath, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exePath)
		candidates = append(candidates,
			filepath.Join(exeDir, "..", "config", "defaults", name),
			filepath.Join(exeDir, "config", "defaults", name),
		)
	}

	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("config: could not locate %s (searched: %v)", name, candidates)
}
