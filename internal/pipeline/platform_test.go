package pipeline

import (
	"os"
	"path/filepath"
	"testing"
)

// stubEnv is a deterministic Env used in unit tests — no reliance on os.Getenv.
type stubEnv map[string]string

func (s stubEnv) Get(k string) string { return s[k] }

func TestDetectPlatform(t *testing.T) {
	cases := []struct {
		name string
		env  stubEnv
		want Platform
	}{
		{"bitbucket wins", stubEnv{"BITBUCKET_BUILD_NUMBER": "42", "GITHUB_ACTIONS": "true"}, PlatformBitbucket},
		{"github actions", stubEnv{"GITHUB_ACTIONS": "true"}, PlatformGitHub},
		{"generic fallback", stubEnv{}, PlatformGeneric},
		{"empty bitbucket build number → not bitbucket", stubEnv{"BITBUCKET_BUILD_NUMBER": "", "GITHUB_ACTIONS": "true"}, PlatformGitHub},
		{"github actions non-true value", stubEnv{"GITHUB_ACTIONS": "false"}, PlatformGeneric},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := DetectPlatform(tc.env); got != tc.want {
				t.Errorf("DetectPlatform = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestMapEnv_Bitbucket(t *testing.T) {
	env := stubEnv{
		"BITBUCKET_PR_ID":                 "99",
		"BITBUCKET_BRANCH":                "feature/x",
		"BITBUCKET_PR_DESTINATION_BRANCH": "main",
		"BITBUCKET_COMMIT":                "abc123",
	}
	got := MapEnv(env, PlatformBitbucket)
	if got.PRID != "99" || got.Branch != "feature/x" || got.TargetBranch != "main" || got.Commit != "abc123" {
		t.Errorf("bitbucket mapping wrong: %+v", got)
	}
}

func TestMapEnv_VersioningOverridesWin(t *testing.T) {
	env := stubEnv{
		"VERSIONING_BRANCH": "override-branch",
		"BITBUCKET_BRANCH":  "platform-branch",
		"BITBUCKET_COMMIT":  "abc",
		"VERSIONING_COMMIT": "", // empty => platform fills in
	}
	got := MapEnv(env, PlatformBitbucket)
	if got.Branch != "override-branch" {
		t.Errorf("override lost: got %q", got.Branch)
	}
	if got.Commit != "abc" {
		t.Errorf("empty override not filled: got %q", got.Commit)
	}
}

func TestMapEnv_GitHubPREvent(t *testing.T) {
	env := stubEnv{
		"GITHUB_EVENT_NAME": "pull_request",
		"GITHUB_PR_NUMBER":  "55",
		"GITHUB_PR_TITLE":   "feat: add x",
		"GITHUB_HEAD_REF":   "feature/x",
		"GITHUB_BASE_REF":   "main",
		"GITHUB_SHA":        "sha1",
	}
	got := MapEnv(env, PlatformGitHub)
	if got.PRID != "55" || got.PRTitle != "feat: add x" || got.Branch != "feature/x" || got.TargetBranch != "main" || got.Commit != "sha1" {
		t.Errorf("github PR mapping wrong: %+v", got)
	}
}

func TestMapEnv_GitHubPushEvent(t *testing.T) {
	env := stubEnv{
		"GITHUB_EVENT_NAME": "push",
		"GITHUB_REF_NAME":   "main",
		"GITHUB_SHA":        "sha1",
	}
	got := MapEnv(env, PlatformGitHub)
	if got.Branch != "main" || got.TargetBranch != "" || got.PRID != "" {
		t.Errorf("github push mapping wrong: %+v", got)
	}
}

func TestLoadGitHubPREventFile(t *testing.T) {
	tmp := t.TempDir()
	path := filepath.Join(tmp, "event.json")
	_ = os.WriteFile(path, []byte(`{"pull_request":{"number":77,"title":"feat: x"}}`), 0o644)

	t.Setenv("GITHUB_PR_NUMBER", "")
	t.Setenv("GITHUB_PR_TITLE", "")
	t.Setenv("GITHUB_EVENT_PATH", path)

	LoadGitHubPREventFile(OSEnv{})
	if got := os.Getenv("GITHUB_PR_NUMBER"); got != "77" {
		t.Errorf("GITHUB_PR_NUMBER = %q, want 77", got)
	}
	if got := os.Getenv("GITHUB_PR_TITLE"); got != "feat: x" {
		t.Errorf("GITHUB_PR_TITLE = %q, want feat: x", got)
	}
}

func TestLoadGitHubPREventFile_MissingFile(t *testing.T) {
	t.Setenv("GITHUB_EVENT_PATH", "/nonexistent/path.json")
	// Must not panic or error — pipe.sh silently tolerated this.
	LoadGitHubPREventFile(OSEnv{})
}

func TestLoadGitHubPREventFile_PreservesManualOverride(t *testing.T) {
	tmp := t.TempDir()
	path := filepath.Join(tmp, "event.json")
	_ = os.WriteFile(path, []byte(`{"pull_request":{"number":77,"title":"from payload"}}`), 0o644)

	t.Setenv("GITHUB_EVENT_PATH", path)
	t.Setenv("GITHUB_PR_TITLE", "manual override")

	LoadGitHubPREventFile(OSEnv{})
	if got := os.Getenv("GITHUB_PR_TITLE"); got != "manual override" {
		t.Errorf("manual override lost: got %q", got)
	}
}
