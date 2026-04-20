package changelog

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

// GeneratePerFolder reads git commits, routes them to folder-specific CHANGELOG.md
// files, writes /tmp/routed_commits.txt and /tmp/per_folder_changelogs.txt.
//
// repoRoot is the working directory of the git repo (/workspace in container).
// nextVersion is the version string (e.g. "v1.2.0").
// baseRef is CHANGELOG_BASE_REF env (empty = all commits from HEAD).
// headerSuffix is "" for dev releases, " (Hotfix)" for hotfix.
func GeneratePerFolder(cfg *config.Config, repoRoot, nextVersion, baseRef, headerSuffix string) error {
	const op = "changelog.per-folder"

	pf := cfg.Changelog.PerFolder
	if !pf.Enabled {
		return nil
	}
	if !cfg.IsConventional() {
		log.Warn("Per-folder changelogs require commits.format: 'conventional'. Skipping.")
		return nil
	}
	if len(pf.Folders) == 0 {
		log.Warn("No folders configured for per-folder changelogs. Skipping.")
		return nil
	}

	log.Section("GENERATING PER-FOLDER CHANGELOGS")
	log.Info(fmt.Sprintf("Folders: %s", strings.Join(pf.Folders, " ")))
	log.Info(fmt.Sprintf("Folder pattern: %s", orNone(pf.FolderPattern)))
	log.Info(fmt.Sprintf("Scope matching: %s", pf.ScopeMatching))
	log.Info(fmt.Sprintf("Fallback: %s", pf.Fallback))
	log.Info(fmt.Sprintf("Mode: %s", cfg.Changelog.Mode))
	fmt.Println()

	// Always truncate/create /tmp/routed_commits.txt
	if err := os.WriteFile("/tmp/routed_commits.txt", []byte{}, 0644); err != nil {
		return fmt.Errorf("%s: init routed_commits: %w", op, err)
	}

	commits, err := getCommits(baseRef, cfg.Validation.IgnorePatterns)
	if err != nil {
		return fmt.Errorf("%s: %w", op, err)
	}

	if len(commits) == 0 {
		log.Info("No commits to process for per-folder changelogs")
		return nil
	}

	// In last_commit mode only process the first (most recent) commit
	toProcess := commits
	if cfg.Changelog.Mode != "full" {
		toProcess = commits[:1]
	}

	tz := cfg.Version.Components.Timestamp.Timezone
	if tz == "" {
		tz = "UTC"
	}
	date := formatDate(tz)

	expandedFolders, err := expandFolders(pf.Folders, repoRoot)
	if err != nil {
		return fmt.Errorf("%s: expand folders: %w", op, err)
	}

	routedSHAs := map[string]bool{}
	updatedChangelogs := map[string]bool{}

	for _, commit := range toProcess {
		if commit.SHA == "" {
			continue
		}

		scope := extractScope(commit.Subject)
		if scope == "" {
			log.Info(fmt.Sprintf("No scope: %s → root CHANGELOG", commit.Subject))
			continue
		}

		depth := pf.ScopeMatchingDepth
		if depth == 0 {
			depth = 2
		}
		targetFolders := findFoldersForScope(scope, expandedFolders, pf.FolderPattern, pf.ScopeMatching, depth)

		if len(targetFolders) == 0 && pf.Fallback == "file_path" {
			targetFolders, err = findFoldersByFilePath(commit.SHA, expandedFolders, repoRoot)
			if err != nil {
				return fmt.Errorf("%s: file_path fallback: %w", op, err)
			}
			if len(targetFolders) > 0 {
				names := make([]string, len(targetFolders))
				for i, tf := range targetFolders {
					names[i] = filepath.Base(tf)
				}
				log.Info(fmt.Sprintf("Scope '%s' → fallback file_path → %s", scope, strings.Join(names, " ")))
			}
		}

		if len(targetFolders) == 0 {
			log.Info(fmt.Sprintf("Scope '%s' no match: %s → root CHANGELOG", scope, commit.Subject))
			continue
		}

		entry := buildEntryLinePerFolder(cfg, commit)
		routedSHAs[commit.SHA] = true

		for _, folder := range targetFolders {
			relFolder, _ := filepath.Rel(repoRoot, folder)
			changelogPath := filepath.Join(folder, "CHANGELOG.md")
			log.Info(fmt.Sprintf("Scope '%s' → %s/CHANGELOG.md", scope, relFolder))

			if err := upsertFolderChangelog(changelogPath, nextVersion, headerSuffix, date, entry); err != nil {
				return fmt.Errorf("%s: write %s: %w", op, changelogPath, err)
			}
			updatedChangelogs[changelogPath] = true
		}
	}

	// Write /tmp/routed_commits.txt
	if len(routedSHAs) > 0 {
		var routed strings.Builder
		for sha := range routedSHAs {
			routed.WriteString(sha)
			routed.WriteString("\n")
		}
		if err := os.WriteFile("/tmp/routed_commits.txt", []byte(routed.String()), 0644); err != nil {
			return fmt.Errorf("%s: write routed_commits: %w", op, err)
		}
	}

	// Write /tmp/per_folder_changelogs.txt
	if len(updatedChangelogs) > 0 {
		var list strings.Builder
		for cl := range updatedChangelogs {
			list.WriteString(cl)
			list.WriteString("\n")
		}
		if err := os.WriteFile("/tmp/per_folder_changelogs.txt", []byte(list.String()), 0644); err != nil {
			return fmt.Errorf("%s: write per_folder_changelogs: %w", op, err)
		}
		log.Success(fmt.Sprintf("Updated %d per-folder CHANGELOG(s)", len(updatedChangelogs)))
		for cl := range updatedChangelogs {
			log.Info(fmt.Sprintf("  - %s", cl))
		}
	} else {
		log.Info("No per-folder CHANGELOGs updated (no scoped commits matched)")
	}

	if len(routedSHAs) > 0 {
		log.Info(fmt.Sprintf("%d commit(s) routed to per-folder CHANGELOGs (excluded from root)", len(routedSHAs)))
	}

	return nil
}

// upsertFolderChangelog creates or updates a folder-level CHANGELOG.md.
func upsertFolderChangelog(path, version, headerSuffix, date, entry string) error {
	header := buildVersionHeader(version, headerSuffix, date)

	existing, readErr := os.ReadFile(path)
	if readErr != nil && !os.IsNotExist(readErr) {
		return readErr
	}

	if os.IsNotExist(readErr) || len(existing) == 0 {
		content := fmt.Sprintf("# Changelog\n\n---\n\n%s\n\n%s\n\n", header, entry)
		return os.WriteFile(path, []byte(content), 0644)
	}

	text := string(existing)

	if strings.Contains(text, header) {
		// Version section exists — insert entry after the header's blank line
		lines := strings.Split(text, "\n")
		out := make([]string, 0, len(lines)+10)
		found := false
		inserted := false
		for _, line := range lines {
			out = append(out, line)
			if !inserted && !found && strings.HasPrefix(line, header) {
				found = true
				continue
			}
			if found && !inserted && strings.TrimSpace(line) == "" {
				out = append(out, entry)
				inserted = true
			}
		}
		return os.WriteFile(path, []byte(strings.Join(out, "\n")), 0644)
	}

	// Append new version section at end
	section := fmt.Sprintf("\n%s\n\n%s\n\n", header, entry)
	return os.WriteFile(path, append(existing, []byte(section)...), 0644)
}

// getCommits runs git log and returns commits, filtered by ignore patterns.
func getCommits(baseRef string, ignorePatterns []string) ([]RawCommit, error) {
	var args []string
	if baseRef == "" {
		log.Info("No base ref set (first run) — using all commits")
		args = []string{"log", "HEAD", "--no-merges", "--pretty=format:%H|%an|%s"}
	} else {
		args = []string{"log", baseRef + "..HEAD", "--no-merges", "--pretty=format:%H|%an|%s"}
	}

	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return nil, nil
	}

	ignoreRe := buildIgnoreRegex(ignorePatterns)
	lines := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	var result []RawCommit

	for _, line := range lines {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 3)
		if len(parts) < 3 {
			continue
		}
		subject := parts[2]
		if ignoreRe != nil && ignoreRe.MatchString(subject) {
			continue
		}
		result = append(result, RawCommit{SHA: parts[0], Author: parts[1], Subject: subject})
	}
	return result, nil
}

// buildIgnoreRegex builds a combined regex from ignore patterns.
func buildIgnoreRegex(patterns []string) *regexp.Regexp {
	if len(patterns) == 0 {
		return nil
	}
	combined := "(" + strings.Join(patterns, "|") + ")"
	re, err := regexp.Compile(combined)
	if err != nil {
		return nil
	}
	return re
}

// expandFolders expands glob patterns in folder list relative to repoRoot.
func expandFolders(folders []string, repoRoot string) ([]string, error) {
	var result []string
	for _, f := range folders {
		abs := filepath.Join(repoRoot, f)
		if !strings.ContainsAny(f, "*?[") {
			result = append(result, abs)
			continue
		}
		matches, err := filepath.Glob(abs)
		if err != nil {
			return nil, err
		}
		result = append(result, matches...)
	}
	return result, nil
}

// findFoldersForScope tries to match scope to a configured folder.
// Supports "exact" (name match + subfolder discovery), "suffix", and "prefix" (default).
func findFoldersForScope(scope string, folders []string, pattern, matchingMode string, depth int) []string {
	if matchingMode == "" {
		matchingMode = "prefix"
	}

	for _, folder := range folders {
		info, err := os.Stat(folder)
		if err != nil || !info.IsDir() {
			continue
		}
		folderName := filepath.Base(folder)

		switch matchingMode {
		case "exact":
			if scope == folderName {
				return []string{folder}
			}
			sub := filepath.Join(folder, scope)
			if info2, err := os.Stat(sub); err == nil && info2.IsDir() {
				return []string{sub}
			}
		case "suffix":
			entries := findSubfolders(folder, depth)
			for _, sub := range entries {
				subName := filepath.Base(sub)
				if pattern != "" {
					if matched, _ := filepath.Match(pattern, subName); !matched {
						if re, err := regexp.Compile(pattern); err != nil || !re.MatchString(subName) {
							continue
						}
					}
				}
				if strings.HasSuffix(subName, "-"+scope) {
					return []string{sub}
				}
			}
		default: // "prefix"
			if strings.HasPrefix(folderName, scope) || scope == folderName {
				return []string{folder}
			}
			sub := filepath.Join(folder, scope)
			if info2, err := os.Stat(sub); err == nil && info2.IsDir() {
				return []string{sub}
			}
		}
	}
	return nil
}

// findSubfolders returns all subdirectories of root up to maxDepth levels.
func findSubfolders(root string, maxDepth int) []string {
	var result []string
	walkDepth(root, 0, maxDepth, &result)
	return result
}

func walkDepth(dir string, current, max int, result *[]string) {
	if current >= max {
		return
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		sub := filepath.Join(dir, e.Name())
		*result = append(*result, sub)
		walkDepth(sub, current+1, max, result)
	}
}

// findFoldersByFilePath finds which configured folders contain files modified by commit.
func findFoldersByFilePath(sha string, folders []string, repoRoot string) ([]string, error) {
	out, err := exec.Command("git", "diff-tree", "--no-commit-id", "--name-only", "-r", sha).Output()
	if err != nil {
		return nil, nil
	}

	changedFiles := strings.Split(strings.TrimSpace(string(out)), "\n")
	matched := map[string]bool{}

	for _, file := range changedFiles {
		if file == "" {
			continue
		}
		for _, folder := range folders {
			relFolder, _ := filepath.Rel(repoRoot, folder)
			if strings.HasPrefix(file, relFolder+"/") {
				matched[folder] = true
				break
			}
		}
	}

	var result []string
	for f := range matched {
		result = append(result, f)
	}
	return result, nil
}

func orNone(s string) string {
	if s == "" {
		return "(none)"
	}
	return s
}
