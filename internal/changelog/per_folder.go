package changelog

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/util/log"
)

// PerFolderResult holds the output of GeneratePerFolder.
type PerFolderResult struct {
	// RoutedSHAs are the commit SHAs routed to at least one folder.
	RoutedSHAs []string
	// UpdatedFiles are the absolute paths of folder CHANGELOG.md files touched.
	UpdatedFiles []string
}

// GeneratePerFolder implements generate-changelog-per-folder.sh.
//
// It reads commits from the git range, routes scoped commits to folder
// CHANGELOG.md files, and writes /tmp/routed_commits.txt and
// /tmp/per_folder_changelogs.txt.
//
// repoRoot is the absolute path to the workspace (matches /workspace in Docker).
func GeneratePerFolder(
	repoRoot string,
	commits []Commit,
	nextVersion string,
	headerSuffix string,
	date string,
	cfg *config.Config,
) (*PerFolderResult, error) {
	pf := cfg.Changelog.PerFolder
	if !pf.Enabled {
		log.Info("Per-folder changelogs disabled — skipping")
		return &PerFolderResult{}, nil
	}
	if len(pf.Folders) == 0 {
		log.Warn("No folders configured for per-folder changelogs. Skipping.")
		return &PerFolderResult{}, nil
	}
	if !cfg.IsConventional() {
		log.Warn("Per-folder changelogs require commits.format: 'conventional'. Skipping.")
		return &PerFolderResult{}, nil
	}

	log.Info(fmt.Sprintf("Folders: %s", strings.Join(pf.Folders, " ")))
	log.Info(fmt.Sprintf("Scope matching: %s", pf.ScopeMatching))
	log.Info(fmt.Sprintf("Fallback: %s", pf.Fallback))

	result := &PerFolderResult{}
	// track which commits were routed (dedup)
	routedSet := map[string]bool{}
	// track which files were touched
	touchedSet := map[string]bool{}

	for _, c := range commits {
		scope := ExtractScope(c.Subject)
		if scope == "" {
			log.Info(fmt.Sprintf("No scope: %s → root CHANGELOG", c.Subject))
			continue
		}

		targetFolders := findFoldersForScope(scope, pf, repoRoot, c.SHA)
		if len(targetFolders) == 0 {
			log.Info(fmt.Sprintf("Scope '%s' no match: %s → root CHANGELOG", scope, c.Subject))
			continue
		}

		entry, err := BuildPerFolderEntry(c, cfg)
		if err != nil {
			return nil, fmt.Errorf("changelog.per-folder build entry: %w", err)
		}

		routedSet[c.SHA] = true

		for _, tf := range targetFolders {
			tf = strings.TrimSuffix(tf, "/")
			clPath := filepath.Join(tf, "CHANGELOG.md")

			relPath := strings.TrimPrefix(clPath, repoRoot+"/")
			log.Info(fmt.Sprintf("Scope '%s' → %s", scope, relPath))

			if err := writePerFolderEntry(clPath, nextVersion, headerSuffix, date, entry); err != nil {
				return nil, fmt.Errorf("changelog.per-folder write %s: %w", clPath, err)
			}
			touchedSet[clPath] = true
		}
	}

	for sha := range routedSet {
		result.RoutedSHAs = append(result.RoutedSHAs, sha)
	}
	sort.Strings(result.RoutedSHAs)

	for path := range touchedSet {
		result.UpdatedFiles = append(result.UpdatedFiles, path)
	}
	sort.Strings(result.UpdatedFiles)

	return result, nil
}

// findFoldersForScope resolves which absolute folder paths match the given
// scope, following the same priority as bash:
//  1. Exact scope match (scope == folder basename or depth-adjusted prefix)
//  2. file_path fallback (if configured)
func findFoldersForScope(scope string, pf config.PerFolderConfig, repoRoot, sha string) []string {
	// Step 1: scope match
	if matched := scopeMatch(scope, pf, repoRoot); len(matched) > 0 {
		return matched
	}
	// Step 2: file_path fallback
	if pf.Fallback == "file_path" {
		return filePathMatch(sha, pf.Folders, repoRoot)
	}
	return nil
}

// scopeMatch returns absolute folder paths where the scope matches according
// to the configured scope_matching strategy.
func scopeMatch(scope string, pf config.PerFolderConfig, repoRoot string) []string {
	var matched []string
	for _, folder := range pf.Folders {
		abs := absFolder(folder, repoRoot)
		name := filepath.Base(abs)

		switch pf.ScopeMatching {
		case "exact":
			if scope == name {
				matched = append(matched, abs)
			}
		case "prefix":
			if strings.HasPrefix(scope, name) {
				matched = append(matched, abs)
			}
		default: // "exact" is default per config defaults
			if scope == name {
				matched = append(matched, abs)
			}
		}
	}
	return matched
}

// filePathMatch returns absolute folder paths for which the commit touched
// at least one file under that folder.
func filePathMatch(sha string, folders []string, repoRoot string) []string {
	out, err := exec.Command("git", "diff-tree", "--no-commit-id", "-r", "--name-only", sha).Output()
	if err != nil {
		return nil
	}
	changedFiles := strings.Split(strings.TrimSpace(string(out)), "\n")

	var matched []string
	for _, folder := range folders {
		abs := absFolder(folder, repoRoot)
		rel := strings.TrimPrefix(abs, repoRoot+"/")
		for _, f := range changedFiles {
			if strings.HasPrefix(f, rel+"/") || strings.HasPrefix(f, rel) {
				matched = append(matched, abs)
				break
			}
		}
	}
	return matched
}

// absFolder resolves a folder spec (relative or absolute) to an absolute path.
func absFolder(folder, repoRoot string) string {
	if filepath.IsAbs(folder) {
		return folder
	}
	return filepath.Join(repoRoot, folder)
}

// writePerFolderEntry writes or updates the folder-level CHANGELOG.md.
// Matches the bash awk-based insertion logic exactly.
func writePerFolderEntry(clPath, version, headerSuffix, date, entry string) error {
	if err := EnsureParentDir(clPath); err != nil {
		return err
	}

	versionHeader := fmt.Sprintf("## %s%s - %s", version, headerSuffix, date)

	existing, err := os.ReadFile(clPath)
	if os.IsNotExist(err) {
		// New file — bash uses: echo "# Changelog\n\n---\n\n## ver\n\nENTRY\n\n" > file
		// The shell echo adds a trailing \n, so the file ends with \n\n\n (entry\n + \n\n + echo\n).
		content := fmt.Sprintf("# Changelog\n\n---\n\n%s\n\n%s\n\n\n", versionHeader, entry)
		return os.WriteFile(clPath, []byte(content), 0o644)
	}
	if err != nil {
		return fmt.Errorf("changelog.writePerFolderEntry read %s: %w", clPath, err)
	}

	text := string(existing)

	if strings.Contains(text, "## "+version) {
		// Version section exists — insert entry after the blank line following the header.
		// Matches bash awk: find version header, then on the next blank line insert entry.
		updated := insertAfterVersionHeader(text, "## "+version, entry)
		return os.WriteFile(clPath, []byte(updated), 0o644)
	}

	// Append new version section — bash: echo "\n## ver\n\nENTRY\n\n" >> file
	// shell echo adds \n, so the appended block ends with \n\n\n.
	addition := fmt.Sprintf("\n%s\n\n%s\n\n\n", versionHeader, entry)
	return AppendToFile(clPath, addition)
}

// insertAfterVersionHeader inserts entry after the blank line that immediately
// follows the version header line. This replicates the bash awk logic:
//
//	index($0, version) == 1 { print; found=1; next }
//	found && /^$/ { print entry; print ""; found=0 }
//	{ print }
func insertAfterVersionHeader(text, versionHeader, entry string) string {
	lines := strings.Split(text, "\n")
	var out []string
	found := false
	for _, line := range lines {
		if strings.HasPrefix(line, versionHeader) {
			out = append(out, line)
			found = true
			continue
		}
		if found && line == "" {
			out = append(out, entry)
			out = append(out, "")
			found = false
			continue
		}
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}
