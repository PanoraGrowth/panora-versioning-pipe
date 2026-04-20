package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	ulog "github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/versionfile"
)

func newWriteVersionFileCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "write-version-file",
		Short: "Write version string into configured project files",
		RunE:  runWriteVersionFile,
	}
}

func runWriteVersionFile(_ *cobra.Command, _ []string) error {
	cfg, err := config.Load(config.MergedConfigPath)
	if err != nil {
		ulog.Error("load config", err)
		os.Exit(1)
	}

	if !cfg.VersionFile.Enabled {
		ulog.Info("Version file feature is disabled, skipping")
		return nil
	}

	ulog.Section("WRITING VERSION FILE")

	versionBytes, err := os.ReadFile(nextVersionPath)
	if err != nil {
		ulog.Error("version file not found. Run calculate-version first", err)
		os.Exit(1)
	}
	version := strings.TrimSpace(string(versionBytes))
	ulog.Info(fmt.Sprintf("Version to write: %s", version))
	fmt.Println()

	// Strip tag prefix to get the plain version written into files
	versionPlain := version
	if cfg.Version.TagPrefixV {
		versionPlain = strings.TrimPrefix(version, "v")
	}

	repoRoot := wvfRepoRoot()

	groups := cfg.VersionFile.Groups
	if len(groups) == 0 {
		ulog.Warn("No groups configured in version_file. Nothing to update.")
		return nil
	}

	targetBranch := os.Getenv("VERSIONING_TARGET_BRANCH")
	changedFiles := versionfile.ChangedFiles(repoRoot, targetBranch)

	var modifiedFiles []string

	for _, group := range groups {
		if !versionfile.GroupMatches(group.TriggerPaths, changedFiles) {
			ulog.Info(fmt.Sprintf("Group %q: trigger_paths did not match changed files, skipping", group.Name))
			continue
		}

		ulog.Info(fmt.Sprintf("Group %q: updating files", group.Name))

		for j, filePath := range group.Files {
			if filePath == "" {
				ulog.Warn(fmt.Sprintf("Group %q file[%d]: path is empty, skipping", group.Name, j))
				continue
			}

			writeType := versionfile.InferWriteType(filePath)
			pattern := cfg.VersionFile.Pattern

			if writeType == "pattern" && pattern == "" {
				_, _ = fmt.Fprintf(os.Stderr,
					"write-version-file: group %q file[%d]: %q requires a pattern (non-yaml/json extension) but none is configured\n",
					group.Name, j, filePath)
				os.Exit(1)
			}

			expanded, err := versionfile.ExpandGlobPath(filePath, repoRoot)
			if err != nil {
				ulog.Error(fmt.Sprintf("expand %q", filePath), err)
				os.Exit(2)
			}

			if len(expanded) == 0 {
				ulog.Warn(fmt.Sprintf("Group %q file[%d]: no files matched %q, skipping", group.Name, j, filePath))
				continue
			}

			for _, absPath := range expanded {
				target := versionfile.Target{
					AbsPath:   absPath,
					WriteType: writeType,
					Pattern:   pattern,
				}

				// pattern writes use the version with prefix; all others use plain
				writeVersion := versionPlain
				if writeType == "pattern" {
					writeVersion = version
				}

				if err := versionfile.UpdateFile(target, writeVersion); err != nil {
					if strings.Contains(err.Error(), "skipping:") {
						ulog.Warn(err.Error())
						continue
					}
					ulog.Error("updating file", err)
					os.Exit(2)
				}

				relPath, _ := filepath.Rel(repoRoot, absPath)
				if relPath == "" {
					relPath = absPath
				}
				ulog.Success(fmt.Sprintf("Updated %s", relPath))
				modifiedFiles = append(modifiedFiles, relPath)
			}
		}
	}

	modifiedContent := strings.Join(modifiedFiles, "\n")
	if len(modifiedFiles) > 0 {
		modifiedContent += "\n"
	}
	if err := os.WriteFile("/tmp/version_files_modified.txt", []byte(modifiedContent), 0o644); err != nil {
		ulog.Error("write modified files list", err)
		os.Exit(2)
	}

	fmt.Println()
	ulog.Success("Version file update complete")
	return nil
}

func wvfRepoRoot() string {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		cwd, _ := os.Getwd()
		return cwd
	}
	return strings.TrimSpace(string(out))
}
