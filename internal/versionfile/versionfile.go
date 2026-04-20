// Package versionfile writes a version string into configured project files
// (package.json, pyproject.toml, version.txt, YAML files, etc.) according to
// the version_file section of the merged .versioning.yml config.
//
// It is a pure-function layer: callers own I/O orchestration (reading /tmp
// inputs, iterating groups, writing the modified-files list). All writers in
// this package operate on absolute paths and return errors — no side effects
// other than the file write.
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
)

// Target is a resolved file to update (absolute path + inferred write strategy).
type Target struct {
	AbsPath   string
	WriteType string // "json" | "yaml" | "toml" | "plain" | "pattern"
	Pattern   string // only for "pattern" type
}

// InferWriteType maps a file path to a write strategy, matching bash behaviour.
func InferWriteType(path string) string {
	lower := strings.ToLower(path)
	switch {
	case strings.HasSuffix(lower, ".yaml") || strings.HasSuffix(lower, ".yml"):
		return "yaml"
	case strings.HasSuffix(lower, ".json"):
		return "json"
	case strings.HasSuffix(lower, ".toml"):
		return "toml"
	case filepath.Base(lower) == "version.txt":
		return "plain"
	default:
		return "pattern"
	}
}

// ExpandGlobPath resolves a (possibly glob) relative path against repoRoot.
// If the path contains no glob characters it is returned as-is (absolute).
// With globs it uses filepath.Glob — files must already exist.
func ExpandGlobPath(pattern, repoRoot string) ([]string, error) {
	abs := filepath.Join(repoRoot, pattern)

	hasGlob := strings.ContainsAny(pattern, "*?[")
	if !hasGlob {
		return []string{abs}, nil
	}

	matches, err := filepath.Glob(abs)
	if err != nil {
		return nil, fmt.Errorf("versionfile.ExpandGlobPath %q: %w", pattern, err)
	}
	return matches, nil
}

// matchesGlob returns true when filePath matches the glob pattern using the
// same logic as the bash write-version-file.sh matches_glob helper:
//   - ** matches any number of path segments
//   - *  matches any non-separator sequence
func matchesGlob(filePath, pattern string) bool {
	// Normalise separators
	filePath = filepath.ToSlash(filePath)
	pattern = filepath.ToSlash(pattern)

	// Convert glob to regex: escape dots, then translate * and **
	re := regexp.QuoteMeta(pattern)
	// Replace escaped ** first (it became \*\* after QuoteMeta)
	re = strings.ReplaceAll(re, `\*\*`, `DOUBLESTAR`)
	re = strings.ReplaceAll(re, `\*`, `[^/]*`)
	re = strings.ReplaceAll(re, `DOUBLESTAR`, `.*`)
	re = "^" + re + "$"

	matched, err := regexp.MatchString(re, filePath)
	if err != nil {
		return false
	}
	return matched
}

// ChangedFiles returns the list of files changed in the workspace using the
// same heuristic as the bash script:
//   - If VERSIONING_TARGET_BRANCH is set → git diff --name-only origin/<branch>...HEAD
//   - Otherwise → git diff-tree --no-commit-id --name-only -r HEAD
//
// CHANGELOG.md is always excluded. Returns an empty slice on error (non-fatal).
func ChangedFiles(repoRoot, targetBranch string) []string {
	var args []string
	if targetBranch != "" {
		// Fetch is best-effort
		_ = exec.Command("git", "-C", repoRoot, "fetch", "origin", targetBranch).Run()
		args = []string{"-C", repoRoot, "diff", "--name-only", fmt.Sprintf("origin/%s...HEAD", targetBranch)}
	} else {
		args = []string{"-C", repoRoot, "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"}
	}

	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return nil
	}

	var result []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.EqualFold(filepath.Base(line), "CHANGELOG.md") {
			continue
		}
		result = append(result, line)
	}
	return result
}

// GroupMatches returns true when a group's trigger_paths match at least one of
// the changed files. If trigger_paths is empty the group always matches.
func GroupMatches(triggerPaths []string, changedFiles []string) bool {
	if len(triggerPaths) == 0 {
		return true
	}
	for _, cf := range changedFiles {
		for _, tp := range triggerPaths {
			if matchesGlob(cf, tp) {
				return true
			}
		}
	}
	return false
}

// =============================================================================
// Writers — pure functions, one per file type
// =============================================================================

// UpdateJSON updates the top-level "version" key in a JSON file while
// preserving key order and all other fields byte-for-byte.
func UpdateJSON(absPath, newVersion string) error {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", absPath, err)
	}

	// Use map[string]json.RawMessage to preserve other fields verbatim.
	// This does NOT preserve key order — we need ordered JSON.
	// Use a two-pass approach: decode into ordered key-value pairs, update
	// the version key, re-encode preserving the original indentation.
	updated, err := updateJSONVersion(data, newVersion)
	if err != nil {
		return fmt.Errorf("write-version-file: update JSON %s: %w", absPath, err)
	}

	if err := os.WriteFile(absPath, updated, 0o644); err != nil {
		return fmt.Errorf("write-version-file: write %s: %w", absPath, err)
	}
	return nil
}

// updateJSONVersion performs a minimal byte-level replacement of the "version"
// field value in JSON data, preserving key order and whitespace.
// It uses encoding/json to decode then re-encodes with the original indentation
// detected from the input.
func updateJSONVersion(data []byte, newVersion string) ([]byte, error) {
	// Detect indentation from the first indented line
	indent := detectJSONIndent(data)

	// Decode into ordered representation using a raw decoder
	var ordered orderedJSON
	if err := json.Unmarshal(data, &ordered); err != nil {
		return nil, err
	}

	// Update the version field
	versionBytes, err := json.Marshal(newVersion)
	if err != nil {
		return nil, err
	}
	found := false
	for i, kv := range ordered.pairs {
		if kv.key == "version" {
			ordered.pairs[i].value = json.RawMessage(versionBytes)
			found = true
			break
		}
	}
	if !found {
		return nil, fmt.Errorf("field \"version\" not found in JSON")
	}

	// Re-encode preserving order
	out, err := marshalOrderedJSON(ordered, indent)
	if err != nil {
		return nil, err
	}
	// Preserve trailing newline if original had one
	if len(data) > 0 && data[len(data)-1] == '\n' && (len(out) == 0 || out[len(out)-1] != '\n') {
		out = append(out, '\n')
	}
	return out, nil
}

// orderedJSON holds JSON key-value pairs in insertion order.
type orderedJSON struct {
	pairs []jsonKV
}

type jsonKV struct {
	key   string
	value json.RawMessage
}

func (o *orderedJSON) UnmarshalJSON(data []byte) error {
	dec := json.NewDecoder(strings.NewReader(string(data)))
	// consume '{'
	tok, err := dec.Token()
	if err != nil {
		return err
	}
	if delim, ok := tok.(json.Delim); !ok || delim != '{' {
		return fmt.Errorf("expected '{', got %v", tok)
	}

	for dec.More() {
		// key
		keyTok, err := dec.Token()
		if err != nil {
			return err
		}
		key, ok := keyTok.(string)
		if !ok {
			return fmt.Errorf("expected string key, got %T", keyTok)
		}
		// value
		var raw json.RawMessage
		if err := dec.Decode(&raw); err != nil {
			return err
		}
		o.pairs = append(o.pairs, jsonKV{key: key, value: raw})
	}
	// consume '}'
	if _, err := dec.Token(); err != nil {
		return err
	}
	return nil
}

func detectJSONIndent(data []byte) string {
	lines := strings.Split(string(data), "\n")
	for _, line := range lines[1:] {
		trimmed := strings.TrimLeft(line, " \t")
		if trimmed == "" || trimmed == "}" || trimmed == "]" {
			continue
		}
		indent := line[:len(line)-len(trimmed)]
		if indent != "" {
			return indent
		}
		break
	}
	return "  "
}

func marshalOrderedJSON(o orderedJSON, indent string) ([]byte, error) {
	var sb strings.Builder
	sb.WriteString("{\n")
	for i, kv := range o.pairs {
		keyBytes, err := json.Marshal(kv.key)
		if err != nil {
			return nil, err
		}

		// Re-indent nested values
		valStr := string(kv.value)
		if json.Valid(kv.value) {
			// For complex values, pretty-print with correct indent
			var tmp interface{}
			if err := json.Unmarshal(kv.value, &tmp); err == nil {
				pretty, err := json.MarshalIndent(tmp, indent, indent)
				if err == nil {
					valStr = string(pretty)
				}
			}
		}

		sb.WriteString(indent)
		sb.Write(keyBytes)
		sb.WriteString(": ")
		sb.WriteString(valStr)
		if i < len(o.pairs)-1 {
			sb.WriteString(",")
		}
		sb.WriteString("\n")
	}
	sb.WriteString("}")
	return []byte(sb.String()), nil
}

// UpdateTOML updates a version field in a TOML file using line-level regex,
// matching the bash behaviour (sed on the version = "..." line).
// Only updates the first occurrence under a [tool.poetry] or [project] section,
// or the first top-level version line if no section header is found.
func UpdateTOML(absPath, newVersion string) error {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", absPath, err)
	}

	updated, err := updateTOMLVersion(string(data), newVersion)
	if err != nil {
		return fmt.Errorf("write-version-file: update TOML %s: %w", absPath, err)
	}

	if err := os.WriteFile(absPath, []byte(updated), 0o644); err != nil {
		return fmt.Errorf("write-version-file: write %s: %w", absPath, err)
	}
	return nil
}

var tomlVersionRe = regexp.MustCompile(`(?m)^(version\s*=\s*")([^"]*)(")`)

func updateTOMLVersion(content, newVersion string) (string, error) {
	if !tomlVersionRe.MatchString(content) {
		return "", fmt.Errorf("no version field found in TOML")
	}
	replaced := false
	result := tomlVersionRe.ReplaceAllStringFunc(content, func(match string) string {
		if replaced {
			return match
		}
		replaced = true
		return tomlVersionRe.ReplaceAllString(match, "${1}"+newVersion+"${3}")
	})
	return result, nil
}

// UpdateYAML updates the top-level "version" key in a YAML file using
// yaml.v3's Node API to preserve comments and formatting.
func UpdateYAML(absPath, newVersion string) error {
	data, err := os.ReadFile(absPath)
	if err != nil {
		// If file doesn't exist, create it with just the version key
		if os.IsNotExist(err) {
			if mkErr := os.MkdirAll(filepath.Dir(absPath), 0o755); mkErr != nil {
				return fmt.Errorf("write-version-file: mkdir %s: %w", filepath.Dir(absPath), mkErr)
			}
			content := fmt.Sprintf("version: %q\n", newVersion)
			return os.WriteFile(absPath, []byte(content), 0o644)
		}
		return fmt.Errorf("write-version-file: read %s: %w", absPath, err)
	}

	updated, err := updateYAMLVersion(data, newVersion)
	if err != nil {
		return fmt.Errorf("write-version-file: update YAML %s: %w", absPath, err)
	}

	if err := os.WriteFile(absPath, updated, 0o644); err != nil {
		return fmt.Errorf("write-version-file: write %s: %w", absPath, err)
	}
	return nil
}

func updateYAMLVersion(data []byte, newVersion string) ([]byte, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, err
	}

	if doc.Kind == yaml.DocumentNode && len(doc.Content) > 0 {
		mapping := doc.Content[0]
		if mapping.Kind == yaml.MappingNode {
			for i := 0; i+1 < len(mapping.Content); i += 2 {
				if mapping.Content[i].Value == "version" {
					mapping.Content[i+1].Value = newVersion
					mapping.Content[i+1].Tag = "!!str"
					break
				}
			}
		}
	}

	out, err := yaml.Marshal(&doc)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// UpdatePlain replaces the entire content of a plain text file with the
// version string (e.g. version.txt).
func UpdatePlain(absPath, newVersion string) error {
	if err := os.WriteFile(absPath, []byte(newVersion+"\n"), 0o644); err != nil {
		return fmt.Errorf("write-version-file: write %s: %w", absPath, err)
	}
	return nil
}

// UpdatePattern applies a sed-style string replacement: every occurrence of
// pattern in the file is replaced with newVersion.
func UpdatePattern(absPath, pattern, newVersion string) error {
	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		// bash logs a warning and skips — we do the same via sentinel error
		return fmt.Errorf("write-version-file: file not found, skipping: %s", absPath)
	}

	data, err := os.ReadFile(absPath)
	if err != nil {
		return fmt.Errorf("write-version-file: read %s: %w", absPath, err)
	}

	updated := strings.ReplaceAll(string(data), pattern, newVersion)
	if err := os.WriteFile(absPath, []byte(updated), 0o644); err != nil {
		return fmt.Errorf("write-version-file: write %s: %w", absPath, err)
	}
	return nil
}

// UpdateFile dispatches to the appropriate writer based on the target's WriteType.
func UpdateFile(t Target, newVersion string) error {
	switch t.WriteType {
	case "json":
		return UpdateJSON(t.AbsPath, newVersion)
	case "yaml":
		return UpdateYAML(t.AbsPath, newVersion)
	case "toml":
		return UpdateTOML(t.AbsPath, newVersion)
	case "plain":
		return UpdatePlain(t.AbsPath, newVersion)
	case "pattern":
		return UpdatePattern(t.AbsPath, t.Pattern, newVersion)
	default:
		return fmt.Errorf("write-version-file: unknown write type %q for %s", t.WriteType, t.AbsPath)
	}
}
