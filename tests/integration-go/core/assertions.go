package core

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// AssertPRCheck verifies the PR check result matches the expected value.
func AssertPRCheck(got CheckResult, expected string) error {
	want := CheckResult(expected)
	if got != want {
		return fmt.Errorf("pr_check: expected %q, got %q", want, got)
	}
	return nil
}

// AssertTagCreated verifies whether a new tag appeared (or not).
// Returns the tag name if created (empty string if expected absent).
func AssertTagCreated(driver PlatformDriver, scenario Scenario, tagBefore *string, timeout time.Duration) (string, error) {
	prefix := scenario.TagPrefix()
	if scenario.Expected.TagCreated {
		tag, err := driver.WaitForNewTag(tagBefore, prefix, timeout)
		if err != nil {
			return "", fmt.Errorf("tag_created=true but no new tag appeared: %w", err)
		}
		return tag, nil
	}
	// tag_created=false — wait briefly then verify no new tag appeared
	time.Sleep(15 * time.Second)
	current, err := driver.GetLatestTag(prefix)
	if err != nil {
		return "", fmt.Errorf("get latest tag: %w", err)
	}
	if current != nil && (tagBefore == nil || *current != *tagBefore) {
		return "", fmt.Errorf("tag_created=false but new tag appeared: %s", *current)
	}
	return "", nil
}

// AssertTagPattern verifies the tag matches the expected regex.
func AssertTagPattern(tag, pattern string) error {
	re, err := regexp.Compile(pattern)
	if err != nil {
		return fmt.Errorf("invalid tag_pattern %q: %w", pattern, err)
	}
	if !re.MatchString(tag) {
		return fmt.Errorf("tag %q does not match pattern %q", tag, pattern)
	}
	return nil
}

// AssertChangelogContains verifies the CHANGELOG at path/ref contains expected text.
// Strips conventional commit type prefix before comparing (mirrors Python harness).
func AssertChangelogContains(driver PlatformDriver, path, ref, expected string) error {
	content, err := driver.GetFileContent(path, ref)
	if err != nil {
		return fmt.Errorf("get changelog %s@%s: %w", path, ref, err)
	}
	if content == nil {
		return fmt.Errorf("changelog %s not found at %s", path, ref)
	}
	needle := stripTypePrefix(expected)
	if !strings.Contains(string(content), needle) {
		return fmt.Errorf("changelog %s does not contain %q", path, needle)
	}
	return nil
}

// AssertChangelogNotIn verifies that none of the given paths contain expected text.
func AssertChangelogNotIn(driver PlatformDriver, paths []string, ref, expected string) error {
	needle := stripTypePrefix(expected)
	for _, path := range paths {
		content, err := driver.GetFileContent(path, ref)
		if err != nil {
			return fmt.Errorf("get changelog %s@%s: %w", path, ref, err)
		}
		if content != nil && strings.Contains(string(content), needle) {
			return fmt.Errorf("changelog %s unexpectedly contains %q", path, needle)
		}
	}
	return nil
}

// AssertChangelogSectionMarker verifies the presence of a section marker in the changelog.
func AssertChangelogSectionMarker(driver PlatformDriver, path, ref, marker string) error {
	content, err := driver.GetFileContent(path, ref)
	if err != nil {
		return fmt.Errorf("get changelog %s@%s: %w", path, ref, err)
	}
	if content == nil {
		return fmt.Errorf("changelog %s not found at %s", path, ref)
	}
	if !strings.Contains(string(content), marker) {
		return fmt.Errorf("changelog %s missing section marker %q", path, marker)
	}
	return nil
}

// AssertVersionFile verifies the version file state.
func AssertVersionFile(driver PlatformDriver, path, ref, expectedTag string, shouldBeUpdated bool) error {
	content, err := driver.GetFileContent(path, ref)
	if err != nil {
		return fmt.Errorf("get version file %s@%s: %w", path, ref, err)
	}
	updated := content != nil && strings.TrimSpace(string(content)) == strings.TrimPrefix(expectedTag, "v")
	if shouldBeUpdated && !updated {
		return fmt.Errorf("version file %s should contain %q but got %q", path, expectedTag, string(content))
	}
	if !shouldBeUpdated && updated {
		return fmt.Errorf("version file %s should not be updated but contains %q", path, string(content))
	}
	return nil
}

// stripTypePrefix removes the conventional commit type prefix from a string
// (e.g. "feat: foo" → "foo", "feat(scope): foo" → "foo").
func stripTypePrefix(s string) string {
	idx := strings.Index(s, ": ")
	if idx >= 0 {
		return s[idx+2:]
	}
	return s
}
