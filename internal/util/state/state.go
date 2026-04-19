// Package state provides helpers for the `/tmp/*` contract the bats tests
// depend on. Paths are always passed in — never hardcoded — so callers stay
// testable and so the bats fixtures can still assert on the canonical
// `/tmp/...` locations.
package state

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// WriteLine writes value plus a trailing newline, truncating any prior content.
func WriteLine(path, value string) error {
	if err := os.WriteFile(path, []byte(value+"\n"), 0o644); err != nil {
		return fmt.Errorf("state.WriteLine %s: %w", path, err)
	}
	return nil
}

// ReadLine reads the first line of path, stripped of its trailing newline.
func ReadLine(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("state.ReadLine %s: %w", path, err)
	}
	text := string(data)
	if idx := strings.IndexByte(text, '\n'); idx >= 0 {
		text = text[:idx]
	}
	return text, nil
}

// AppendEnv appends `KEY=value` to an env-style file, creating it if missing.
// Values containing whitespace are wrapped in double quotes so downstream
// `source file` calls in bash still work.
func AppendEnv(path, key, value string) error {
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("state.AppendEnv %s: %w", path, err)
	}
	defer f.Close()

	line := formatEnvLine(key, value)
	if _, err := fmt.Fprintln(f, line); err != nil {
		return fmt.Errorf("state.AppendEnv %s: %w", path, err)
	}
	return nil
}

// LoadEnv parses a `KEY=VALUE` env file into a map. Blank lines and `#`
// comments are ignored. Surrounding quotes on the value are stripped.
func LoadEnv(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("state.LoadEnv %s: %w", path, err)
	}
	defer f.Close()

	out := make(map[string]string)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		raw := strings.TrimSpace(scanner.Text())
		if raw == "" || strings.HasPrefix(raw, "#") {
			continue
		}
		eq := strings.IndexByte(raw, '=')
		if eq <= 0 {
			continue
		}
		key := strings.TrimSpace(raw[:eq])
		value := strings.TrimSpace(raw[eq+1:])
		if len(value) >= 2 {
			first, last := value[0], value[len(value)-1]
			if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
				value = value[1 : len(value)-1]
			}
		}
		out[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("state.LoadEnv %s: %w", path, err)
	}
	return out, nil
}

// CreateFlag creates an empty marker file, mirroring `touch`.
func CreateFlag(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("state.CreateFlag %s: %w", path, err)
	}
	return f.Close()
}

// HasFlag returns true if path exists as a regular file.
func HasFlag(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}

func formatEnvLine(key, value string) string {
	if strings.ContainsAny(value, " \t") {
		return fmt.Sprintf(`%s="%s"`, key, value)
	}
	return fmt.Sprintf("%s=%s", key, value)
}
