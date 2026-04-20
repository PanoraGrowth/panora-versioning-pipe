// Package pipeline implements the orchestration layer that dispatches to
// either the PR pipeline or the branch pipeline — the Go replacement for
// pipe.sh + scripts/orchestration/*.sh.
//
// Design note (GO-11): each stage is executed as a sub-process invocation of
// this same binary (self-exec), matching the bash model where every
// orchestration script invoked smaller scripts. This keeps stage isolation
// identical to bash, preserves exit-code propagation, and respects the
// isolation paths defined in the ticket.
package pipeline

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
)

// Platform identifies the CI system the pipeline is running on.
type Platform int

const (
	// PlatformGeneric means the pipeline runs outside Bitbucket/GitHub and
	// expects the caller to set VERSIONING_* variables directly.
	PlatformGeneric Platform = iota
	// PlatformBitbucket runs inside a Bitbucket Pipelines build.
	PlatformBitbucket
	// PlatformGitHub runs inside a GitHub Actions workflow.
	PlatformGitHub
)

// Label returns the human-readable banner string used by pipe.sh for the
// "Platform detected:" log line.
func (p Platform) Label() string {
	switch p {
	case PlatformBitbucket:
		return "Bitbucket Pipelines"
	case PlatformGitHub:
		return "GitHub Actions"
	default:
		return "Generic CI (using VERSIONING_* variables)"
	}
}

// Env abstracts the process environment so tests can exercise DetectPlatform
// and MapEnv without mutating os.Getenv.
type Env interface {
	Get(key string) string
}

// OSEnv wires Env to os.Getenv. Use this at the cmd/ layer.
type OSEnv struct{}

// Get returns os.Getenv(key).
func (OSEnv) Get(key string) string { return os.Getenv(key) }

// DetectPlatform matches the bash order in pipe.sh:
//  1. BITBUCKET_BUILD_NUMBER set and non-empty → Bitbucket
//  2. GITHUB_ACTIONS == "true" → GitHub
//  3. otherwise → Generic
func DetectPlatform(env Env) Platform {
	if env.Get("BITBUCKET_BUILD_NUMBER") != "" {
		return PlatformBitbucket
	}
	if env.Get("GITHUB_ACTIONS") == "true" {
		return PlatformGitHub
	}
	return PlatformGeneric
}

// EnvMapping is the set of VERSIONING_* values to export, after platform
// auto-mapping. Only keys whose value is non-empty are written — idempotent
// with respect to pre-existing VERSIONING_* values (we never overwrite).
type EnvMapping struct {
	Branch       string
	TargetBranch string
	PRID         string
	PRTitle      string
	Commit       string
}

// MapEnv returns the VERSIONING_* values auto-derived from platform-specific
// environment variables. Pre-existing VERSIONING_* values always win — this
// function only fills in the gaps (matches ${VERSIONING_X:-${PLATFORM_X:-}}).
//
// For GitHub PR events, the caller should supply the pull_request.number /
// pull_request.title via GITHUB_PR_NUMBER / GITHUB_PR_TITLE if it has already
// parsed GITHUB_EVENT_PATH — see LoadGitHubPREventFile.
func MapEnv(env Env, p Platform) EnvMapping {
	m := EnvMapping{
		Branch:       env.Get("VERSIONING_BRANCH"),
		TargetBranch: env.Get("VERSIONING_TARGET_BRANCH"),
		PRID:         env.Get("VERSIONING_PR_ID"),
		PRTitle:      env.Get("VERSIONING_PR_TITLE"),
		Commit:       env.Get("VERSIONING_COMMIT"),
	}

	switch p {
	case PlatformBitbucket:
		m.PRID = coalesce(m.PRID, env.Get("BITBUCKET_PR_ID"))
		m.Branch = coalesce(m.Branch, env.Get("BITBUCKET_BRANCH"))
		m.TargetBranch = coalesce(m.TargetBranch, env.Get("BITBUCKET_PR_DESTINATION_BRANCH"))
		m.Commit = coalesce(m.Commit, env.Get("BITBUCKET_COMMIT"))

	case PlatformGitHub:
		if env.Get("GITHUB_EVENT_NAME") == "pull_request" {
			m.PRID = coalesce(m.PRID, env.Get("GITHUB_PR_NUMBER"))
			m.PRTitle = coalesce(m.PRTitle, env.Get("GITHUB_PR_TITLE"))
			m.Branch = coalesce(m.Branch, env.Get("GITHUB_HEAD_REF"))
			m.TargetBranch = coalesce(m.TargetBranch, env.Get("GITHUB_BASE_REF"))
		} else {
			m.Branch = coalesce(m.Branch, env.Get("GITHUB_REF_NAME"))
		}
		m.Commit = coalesce(m.Commit, env.Get("GITHUB_SHA"))
	}
	return m
}

// Apply exports each non-empty field of m into the process environment.
// Empty VERSIONING_* values are left alone — matches the bash behavior where
// `export VERSIONING_X="${VERSIONING_X:-}"` writes an empty string but the
// downstream `-n` tests still detect "absent". We keep semantics identical:
// empty string in, empty string out — os.Setenv with "" is harmless since
// downstream readers use env.Get which treats missing and empty the same.
func (m EnvMapping) Apply() error {
	writes := []struct {
		key, val string
	}{
		{"VERSIONING_BRANCH", m.Branch},
		{"VERSIONING_TARGET_BRANCH", m.TargetBranch},
		{"VERSIONING_PR_ID", m.PRID},
		{"VERSIONING_PR_TITLE", m.PRTitle},
		{"VERSIONING_COMMIT", m.Commit},
	}
	for _, w := range writes {
		if err := os.Setenv(w.key, w.val); err != nil {
			return fmt.Errorf("pipeline.mapenv set %s: %w", w.key, err)
		}
	}
	return nil
}

// LoadGitHubPREventFile reads the JSON pointed to by GITHUB_EVENT_PATH and
// exports GITHUB_PR_NUMBER / GITHUB_PR_TITLE so MapEnv can consume them
// without duplicating JSON parsing. Matches the jq calls in pipe.sh:42-49.
//
// Any parse or read error is silent — pipe.sh tolerated these (2>/dev/null
// || echo "") because pull_request events on non-PR triggers may not have
// the fields set. We preserve that behavior.
func LoadGitHubPREventFile(env Env) {
	path := env.Get("GITHUB_EVENT_PATH")
	if path == "" {
		return
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var payload struct {
		PullRequest struct {
			Number int    `json:"number"`
			Title  string `json:"title"`
		} `json:"pull_request"`
	}
	if err := json.Unmarshal(b, &payload); err != nil {
		return
	}
	if payload.PullRequest.Number != 0 && env.Get("GITHUB_PR_NUMBER") == "" {
		_ = os.Setenv("GITHUB_PR_NUMBER", fmt.Sprintf("%d", payload.PullRequest.Number))
	}
	if payload.PullRequest.Title != "" && env.Get("GITHUB_PR_TITLE") == "" {
		_ = os.Setenv("GITHUB_PR_TITLE", payload.PullRequest.Title)
	}
}

// PrintPlatformBanner writes the "Platform detected:" line used by pipe.sh.
func PrintPlatformBanner(w io.Writer, p Platform) {
	_, _ = fmt.Fprintf(w, "Platform detected: %s\n", p.Label())
}

func coalesce(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
