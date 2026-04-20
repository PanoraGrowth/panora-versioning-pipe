package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// readStateTrimmed reads a single-line state file and returns the trimmed value.
// Returns an error when the file does not exist.
func readStateTrimmed(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("readStateTrimmed %s: %w", path, err)
	}
	return strings.TrimSpace(string(b)), nil
}

// buildGitRange returns the git log range given an optional base ref.
// Matches bash: if [ -z "$CHANGELOG_BASE_REF" ] then "HEAD" else "base..HEAD".
func buildGitRange(baseRef string) string {
	if baseRef == "" {
		return "HEAD"
	}
	return baseRef + "..HEAD"
}

// gitLog runs git log with the pipe-delimited pretty format used by the
// changelog generators: %H|%an|%s (hash, author, subject).
func gitLog(gitRange string) (string, error) {
	cmd := exec.Command("git", "log", gitRange,
		"--no-merges",
		"--pretty=format:%H|%an|%s",
	)
	out, err := cmd.Output()
	if err != nil {
		// git log returns exit 128 for invalid ranges — treat as empty
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 128 {
			return "", nil
		}
		return "", fmt.Errorf("gitLog %q: %w", gitRange, err)
	}
	return string(out), nil
}

// loadConfigSafe loads the merged config, returning a nil error on success.
// Used where config is optional (update-changelog).
func loadConfigSafe() (*config.Config, error) {
	return config.Load(config.MergedConfigPath)
}
