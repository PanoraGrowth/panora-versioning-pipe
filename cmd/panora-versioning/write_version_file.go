package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/versionfile"
)

func repoRootDir() (string, error) {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return os.Getwd()
	}
	return strings.TrimSpace(string(out)), nil
}

func newWriteVersionFileCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "write-version-file",
		Short: "Write version strings into configured target files",
		RunE:  runWriteVersionFile,
	}
}

func runWriteVersionFile(cmd *cobra.Command, _ []string) error {
	cfg, err := config.Load(config.MergedConfigPath)
	if err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "write-version-file: %v\n", err)
		os.Exit(1)
	}
	if !cfg.VersionFile.Enabled {
		fmt.Fprintln(cmd.OutOrStdout(), "[INFO]  write-version-file: version file feature is disabled, skipping")
		return nil
	}
	vb, err := os.ReadFile("/tmp/next_version.txt")
	if err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "write-version-file: version file not found. Run calculate-version first.\n")
		os.Exit(1)
	}
	fullVersion := strings.TrimSpace(string(vb))
	plainVersion := fullVersion
	if cfg.Version.TagPrefixV && strings.HasPrefix(fullVersion, "v") {
		plainVersion = strings.TrimPrefix(fullVersion, "v")
	}
	if len(cfg.VersionFile.Groups) == 0 {
		fmt.Fprintln(cmd.OutOrStdout(), "[WARN]  write-version-file: no groups configured in version_file. Nothing to update.")
		return nil
	}
	repoRoot, err := repoRootDir()
	if err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "write-version-file: cannot determine repo root: %v\n", err)
		os.Exit(2)
	}
	targetBranch := os.Getenv("VERSIONING_TARGET_BRANCH")
	changedFiles, err := versionfile.GetChangedFiles(repoRoot, targetBranch)
	if err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "write-version-file: git error: %v\n", err)
		os.Exit(2)
	}
	fmt.Fprintf(cmd.OutOrStdout(), "[INFO]  write-version-file: version to write: %s\n", fullVersion)
	targets, skipped, err := versionfile.Discover(cfg.VersionFile, repoRoot, changedFiles)
	if err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "%v\n", err)
		os.Exit(1)
	}
	for _, groupName := range skipped {
		fmt.Fprintf(cmd.OutOrStdout(), "[INFO]  write-version-file: group %q: trigger_paths did not match changed files, skipping\n", groupName)
	}
	var modifiedFiles []string
	for _, target := range targets {
		ver := plainVersion
		if target.Kind == "pattern" {
			ver = fullVersion
		}
		if err := versionfile.Update(target, ver); err != nil {
			_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "%v\n", err)
			os.Exit(2)
		}
		fmt.Fprintf(cmd.OutOrStdout(), "[OK]    write-version-file: updated %s\n", target.RelPath)
		modifiedFiles = append(modifiedFiles, target.AbsPath)
	}
	content := strings.Join(modifiedFiles, "\n")
	if len(modifiedFiles) > 0 {
		content += "\n"
	}
	if err := os.WriteFile("/tmp/version_files_modified.txt", []byte(content), 0o644); err != nil {
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "write-version-file: write version_files_modified.txt: %v\n", err)
		os.Exit(2)
	}
	fmt.Fprintln(cmd.OutOrStdout(), "[OK]    write-version-file: version file update complete")
	return nil
}
