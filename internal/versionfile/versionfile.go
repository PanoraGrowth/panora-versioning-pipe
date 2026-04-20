// Package versionfile writes version strings into configured target files.
// It supports JSON, YAML/TOML (by extension inference) and arbitrary pattern replacement.
package versionfile

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// Target represents a single resolved file to be updated.
type Target struct {
	AbsPath string
	RelPath string
	Kind    string // "json", "yaml", "toml", "pattern"
	Pattern string // only for kind=="pattern"
}

func writeType(path string) string {
	lower := strings.ToLower(path)
	switch {
	case strings.HasSuffix(lower, ".yaml") || strings.HasSuffix(lower, ".yml"):
		return "yaml"
	case strings.HasSuffix(lower, ".json"):
		return "json"
	case strings.HasSuffix(lower, ".toml"):
		return "toml"
	default:
		return "pattern"
	}
}

func expandGlobPath(repoRoot, pattern string) ([]string, error) {
	abs := filepath.Join(repoRoot, pattern)
	if !strings.ContainsAny(pattern, "*?[") {
		return []string{abs}, nil
	}
	matches, err := filepath.Glob(abs)
	if err != nil {
		return nil, fmt.Errorf("glob %q: %w", abs, err)
	}
	return matches, nil
}

func matchesGlob(file, pattern string) bool {
	re := strings.NewReplacer(".", `\.`).Replace(pattern)
	re = strings.ReplaceAll(re, "**", "\x00")
	re = strings.ReplaceAll(re, "*", `[^/]*`)
	re = strings.ReplaceAll(re, "\x00", ".*")
	matched, _ := regexp.MatchString("^"+re+"$", file)
	return matched
}

// GetChangedFiles returns changed files for trigger_paths evaluation.
// With targetBranch: diffs HEAD against origin/<branch>. Without: uses diff-tree HEAD.
func GetChangedFiles(repoRoot, targetBranch string) ([]string, error) {
	var out []byte
	var err error
	if targetBranch != "" {
		_ = exec.Command("git", "-C", repoRoot, "fetch", "origin", targetBranch).Run()
		out, err = exec.Command(
			"git", "-C", repoRoot,
			"diff", "--name-only", fmt.Sprintf("origin/%s...HEAD", targetBranch),
		).Output()
	} else {
		out, err = exec.Command(
			"git", "-C", repoRoot,
			"diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD",
		).Output()
	}
	if err != nil {
		return nil, nil
	}
	var files []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.EqualFold(line, "CHANGELOG.md") {
			continue
		}
		files = append(files, line)
	}
	return files, nil
}

func shouldUpdateGroup(group config.VersionFileGroup, changedFiles []string) bool {
	if len(group.TriggerPaths) == 0 {
		return true
	}
	for _, f := range changedFiles {
		for _, p := range group.TriggerPaths {
			if matchesGlob(f, p) {
				return true
			}
		}
	}
	return false
}

// Discover resolves all Target files for groups that should be updated.
func Discover(cfg config.VersionFileConfig, repoRoot string, changedFiles []string) ([]Target, []string, error) {
	var targets []Target
	var skipped []string
	for _, group := range cfg.Groups {
		if !shouldUpdateGroup(group, changedFiles) {
			skipped = append(skipped, group.Name)
			continue
		}
		for _, entry := range group.Files {
			if entry.Path == "" {
				continue
			}
			kind := writeType(entry.Path)
			if kind == "pattern" && entry.Pattern == "" {
				return nil, nil, fmt.Errorf(
					"write-version-file: group %q file %q requires a pattern (non-yaml/json extension) but none is configured",
					group.Name, entry.Path,
				)
			}
			expanded, err := expandGlobPath(repoRoot, entry.Path)
			if err != nil {
				return nil, nil, fmt.Errorf("write-version-file: %w", err)
			}
			for _, abs := range expanded {
				rel, _ := filepath.Rel(repoRoot, abs)
				targets = append(targets, Target{
					AbsPath: abs, RelPath: rel, Kind: kind, Pattern: entry.Pattern,
				})
			}
		}
	}
	return targets, skipped, nil
}

// Update writes newVersion into the target file, preserving formatting.
func Update(target Target, newVersion string) error {
	switch target.Kind {
	case "json":
		return updateJSON(target.AbsPath, newVersion)
	case "yaml":
		return updateYAML(target.AbsPath, newVersion)
	case "toml":
		return updateTOML(target.AbsPath, newVersion)
	case "pattern":
		return updatePattern(target.AbsPath, newVersion, target.Pattern)
	default:
		return fmt.Errorf("write-version-file: unknown kind %q for %s", target.Kind, target.AbsPath)
	}
}

func updateJSON(path, version string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return fmt.Errorf("write-version-file: mkdir %s: %w", filepath.Dir(path), err)
		}
		return os.WriteFile(path, []byte(fmt.Sprintf("{\"version\": %q}\n", version)), 0o644)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", path, err)
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		return fmt.Errorf("write-version-file: parse %s: %w", path, err)
	}
	updated, err := replaceJSONVersionField(raw, version)
	if err != nil {
		return fmt.Errorf("write-version-file: update version field in %s: %w", path, err)
	}
	return os.WriteFile(path, updated, 0o644)
}

func replaceJSONVersionField(raw []byte, newVersion string) ([]byte, error) {
	re := regexp.MustCompile(`("version"\s*:\s*)"[^"]*"`)
	replaced := false
	result := re.ReplaceAllFunc(raw, func(match []byte) []byte {
		replaced = true
		prefix := re.FindSubmatch(match)[1]
		return append(prefix, []byte(fmt.Sprintf("%q", newVersion))...)
	})
	if !replaced {
		var m map[string]json.RawMessage
		if err := json.Unmarshal(raw, &m); err != nil {
			return nil, err
		}
		vb, _ := json.Marshal(newVersion)
		m["version"] = json.RawMessage(vb)
		out, err := json.MarshalIndent(m, "", "  ")
		if err != nil {
			return nil, err
		}
		return append(out, '\n'), nil
	}
	return result, nil
}

func updateYAML(path, version string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return fmt.Errorf("write-version-file: mkdir %s: %w", filepath.Dir(path), err)
		}
		return os.WriteFile(path, []byte(fmt.Sprintf("version: %q\n", version)), 0o644)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", path, err)
	}
	var doc yaml.Node
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return fmt.Errorf("write-version-file: parse %s: %w", path, err)
	}
	if doc.Kind == yaml.DocumentNode && len(doc.Content) > 0 {
		setYAMLNodeValue(doc.Content[0], "version", version)
	}
	out, err := yaml.Marshal(&doc)
	if err != nil {
		return fmt.Errorf("write-version-file: marshal %s: %w", path, err)
	}
	return os.WriteFile(path, out, 0o644)
}

func setYAMLNodeValue(node *yaml.Node, key, value string) {
	if node.Kind != yaml.MappingNode {
		return
	}
	for i := 0; i+1 < len(node.Content); i += 2 {
		if node.Content[i].Value == key {
			node.Content[i+1].Value = value
			node.Content[i+1].Tag = "!!str"
			return
		}
	}
	node.Content = append(node.Content,
		&yaml.Node{Kind: yaml.ScalarNode, Value: key, Tag: "!!str"},
		&yaml.Node{Kind: yaml.ScalarNode, Value: value, Tag: "!!str"},
	)
}

func updateTOML(path, version string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("write-version-file: file not found: %s", path)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", path, err)
	}
	lines := strings.Split(string(raw), "\n")
	re := regexp.MustCompile(`^(\s*version\s*=\s*)"[^"]*"(.*)$`)
	inTargetSection := false
	topLevel := true
	replaced := false
	result := make([]string, 0, len(lines))
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "[") {
			topLevel = false
			sectionName := strings.Trim(trimmed, "[]")
			inTargetSection = sectionName == "tool.poetry" || sectionName == "project"
		}
		if !replaced && re.MatchString(line) && (inTargetSection || topLevel) {
			line = re.ReplaceAllString(line, fmt.Sprintf(`${1}%q${2}`, version))
			replaced = true
		}
		result = append(result, line)
	}
	if !replaced {
		return fmt.Errorf("write-version-file: could not find 'version = \"...\"' line in %s", path)
	}
	return os.WriteFile(path, []byte(strings.Join(result, "\n")), 0o644)
}

func updatePattern(path, version, pattern string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("write-version-file: file not found: %s", path)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", path, err)
	}
	return os.WriteFile(path, []byte(strings.ReplaceAll(string(raw), pattern, version)), 0o644)
}
