// Package gitops is a thin, opinionated wrapper around go-git/v5 that exposes
// only the operations the versioning pipe needs. No interfaces are introduced
// here: every method is called from exactly one place today, and adding an
// abstraction before the second implementation exists would be premature.
//
// Errors always wrap with the package operation name (e.g. "gitops.Fetch: ...")
// so operator logs stay greppable.
package gitops

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"os/exec"
	"regexp"
	"sort"
	"strings"

	"github.com/Masterminds/semver/v3"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/config"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/object"
	"github.com/go-git/go-git/v5/plumbing/transport"
	githttp "github.com/go-git/go-git/v5/plumbing/transport/http"
)

// Repo is a concrete wrapper around a checked-out working tree.
type Repo struct {
	path string
	repo *git.Repository
	auth transport.AuthMethod
}

// Commit is the subject + body shape callers (changelog, bump detection) need.
type Commit struct {
	SHA     string
	Subject string
	Body    string
}

// AuthOptions describes push credentials. Exactly one auth family should be
// populated; Setup picks GitHub when GitHubToken is non-empty, Bitbucket
// otherwise, and is a no-op if both are empty.
type AuthOptions struct {
	GitHubToken          string
	BitbucketUser        string
	BitbucketAppPassword string
}

// Open returns a Repo for the working tree at path.
func Open(path string) (*Repo, error) {
	r, err := git.PlainOpen(path)
	if err != nil {
		return nil, fmt.Errorf("gitops.Open %s: %w", path, err)
	}
	return &Repo{path: path, repo: r}, nil
}

// Path returns the working-tree path the repo was opened from.
func (r *Repo) Path() string { return r.path }

// ConfigureIdentity sets user.name and user.email at the global scope — the
// bash script used `git config --global`, so we match that to avoid surprising
// a downstream `git commit` that relies on global config.
func (r *Repo) ConfigureIdentity(name, email string) error {
	if name == "" || email == "" {
		return errors.New("gitops.ConfigureIdentity: name and email required")
	}
	if err := exec.Command("git", "config", "--global", "user.name", name).Run(); err != nil {
		return fmt.Errorf("gitops.ConfigureIdentity user.name: %w", err)
	}
	if err := exec.Command("git", "config", "--global", "user.email", email).Run(); err != nil {
		return fmt.Errorf("gitops.ConfigureIdentity user.email: %w", err)
	}
	return nil
}

// ConfigureSafeDirectory registers path under `safe.directory` globally. go-git
// does not enforce git's `safe.directory` check (that's the CLI), so we shell
// out to the git binary. This is the one intentional shell-out in gitops.
func (r *Repo) ConfigureSafeDirectory(path string) error {
	if err := exec.Command("git", "config", "--global", "--add", "safe.directory", path).Run(); err != nil {
		return fmt.Errorf("gitops.ConfigureSafeDirectory %s: %w", path, err)
	}
	return nil
}

// SetupRemoteAuth rewrites origin to carry embedded credentials (matching the
// bash behaviour) and caches the auth method for future pushes/fetches.
// Returns nil with no side effects when no credentials are supplied.
func (r *Repo) SetupRemoteAuth(opts AuthOptions) error {
	switch {
	case opts.GitHubToken != "":
		r.auth = &githttp.BasicAuth{Username: "x-access-token", Password: opts.GitHubToken}
		return r.rewriteOrigin("github.com", "x-access-token", opts.GitHubToken)
	case opts.BitbucketUser != "" && opts.BitbucketAppPassword != "":
		r.auth = &githttp.BasicAuth{Username: opts.BitbucketUser, Password: opts.BitbucketAppPassword}
		return r.rewriteOrigin("bitbucket.org", opts.BitbucketUser, opts.BitbucketAppPassword)
	}
	return nil
}

func (r *Repo) rewriteOrigin(host, user, secret string) error {
	remote, err := r.repo.Remote("origin")
	if err != nil {
		return fmt.Errorf("gitops.SetupRemoteAuth origin lookup: %w", err)
	}
	urls := remote.Config().URLs
	if len(urls) == 0 {
		return errors.New("gitops.SetupRemoteAuth: origin has no URL")
	}
	current := urls[0]
	if !strings.Contains(current, host) {
		return nil
	}
	rewritten, err := embedBasicAuth(current, host, user, secret)
	if err != nil {
		return fmt.Errorf("gitops.SetupRemoteAuth rewrite: %w", err)
	}
	cfg, err := r.repo.Config()
	if err != nil {
		return fmt.Errorf("gitops.SetupRemoteAuth config: %w", err)
	}
	cfg.Remotes["origin"].URLs = []string{rewritten}
	if err := r.repo.SetConfig(cfg); err != nil {
		return fmt.Errorf("gitops.SetupRemoteAuth setconfig: %w", err)
	}
	return nil
}

// Fetch replicates `git fetch --unshallow || true; git fetch --tags --force`.
func (r *Repo) Fetch(ctx context.Context) error {
	opts := &git.FetchOptions{
		RemoteName: "origin",
		Auth:       r.auth,
		Force:      true,
		Tags:       git.AllTags,
	}
	if err := r.repo.FetchContext(ctx, opts); err != nil {
		if errors.Is(err, git.NoErrAlreadyUpToDate) || errors.Is(err, transport.ErrEmptyRemoteRepository) {
			return nil
		}
		return fmt.Errorf("gitops.Fetch: %w", err)
	}
	return nil
}

// FetchBranch fetches a single branch into a local ref of the same name,
// matching the bash `git fetch origin "branch:branch"` form.
func (r *Repo) FetchBranch(ctx context.Context, branch string) error {
	if branch == "" {
		return errors.New("gitops.FetchBranch: branch required")
	}
	ref := config.RefSpec(fmt.Sprintf("+refs/heads/%s:refs/heads/%s", branch, branch))
	err := r.repo.FetchContext(ctx, &git.FetchOptions{
		RemoteName: "origin",
		RefSpecs:   []config.RefSpec{ref},
		Auth:       r.auth,
		Force:      true,
	})
	if err != nil && !errors.Is(err, git.NoErrAlreadyUpToDate) {
		return fmt.Errorf("gitops.FetchBranch %s: %w", branch, err)
	}
	return nil
}

// LatestTag returns the highest semver tag matching pattern, or "" when no tag
// matches. Non-semver tags that still satisfy the regex are ignored.
func (r *Repo) LatestTag(pattern *regexp.Regexp) (string, error) {
	iter, err := r.repo.Tags()
	if err != nil {
		return "", fmt.Errorf("gitops.LatestTag: %w", err)
	}
	type candidate struct {
		name string
		ver  *semver.Version
	}
	var matches []candidate
	err = iter.ForEach(func(ref *plumbing.Reference) error {
		name := ref.Name().Short()
		if pattern != nil && !pattern.MatchString(name) {
			return nil
		}
		v, parseErr := semver.NewVersion(name)
		if parseErr != nil {
			return nil
		}
		matches = append(matches, candidate{name: name, ver: v})
		return nil
	})
	if err != nil {
		return "", fmt.Errorf("gitops.LatestTag iterate: %w", err)
	}
	if len(matches) == 0 {
		return "", nil
	}
	sort.Slice(matches, func(i, j int) bool {
		return matches[i].ver.LessThan(matches[j].ver)
	})
	return matches[len(matches)-1].name, nil
}

// CommitsBetween returns commits reachable from `to` but not from `from`,
// ordered newest-first — equivalent to `git log from..to`.
func (r *Repo) CommitsBetween(from, to string) ([]Commit, error) {
	fromHash, err := r.resolve(from)
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsBetween resolve from %q: %w", from, err)
	}
	toHash, err := r.resolve(to)
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsBetween resolve to %q: %w", to, err)
	}
	excluded, err := r.ancestors(fromHash)
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsBetween ancestors: %w", err)
	}
	iter, err := r.repo.Log(&git.LogOptions{From: toHash})
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsBetween log: %w", err)
	}
	var out []Commit
	err = iter.ForEach(func(c *object.Commit) error {
		if _, skip := excluded[c.Hash]; skip {
			return nil
		}
		out = append(out, toCommit(c))
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsBetween walk: %w", err)
	}
	return out, nil
}

// CommitsOn returns every commit reachable from ref, newest-first.
func (r *Repo) CommitsOn(ref string) ([]Commit, error) {
	hash, err := r.resolve(ref)
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsOn resolve %q: %w", ref, err)
	}
	iter, err := r.repo.Log(&git.LogOptions{From: hash})
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsOn log: %w", err)
	}
	var out []Commit
	err = iter.ForEach(func(c *object.Commit) error {
		out = append(out, toCommit(c))
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("gitops.CommitsOn walk: %w", err)
	}
	return out, nil
}

// PushBranch pushes a single local branch to origin.
func (r *Repo) PushBranch(ctx context.Context, branch string) error {
	refSpec := config.RefSpec(fmt.Sprintf("refs/heads/%s:refs/heads/%s", branch, branch))
	return r.pushRefs(ctx, []config.RefSpec{refSpec}, "PushBranch", branch)
}

// PushTag pushes a single tag to origin.
func (r *Repo) PushTag(ctx context.Context, tag string) error {
	refSpec := config.RefSpec(fmt.Sprintf("refs/tags/%s:refs/tags/%s", tag, tag))
	return r.pushRefs(ctx, []config.RefSpec{refSpec}, "PushTag", tag)
}

// PushBranchAndTag pushes branch + tag in a single atomic call.
func (r *Repo) PushBranchAndTag(ctx context.Context, branch, tag string) error {
	refs := []config.RefSpec{
		config.RefSpec(fmt.Sprintf("refs/heads/%s:refs/heads/%s", branch, branch)),
		config.RefSpec(fmt.Sprintf("refs/tags/%s:refs/tags/%s", tag, tag)),
	}
	return r.pushRefs(ctx, refs, "PushBranchAndTag", fmt.Sprintf("%s+%s", branch, tag))
}

func (r *Repo) pushRefs(ctx context.Context, refs []config.RefSpec, op, target string) error {
	err := r.repo.PushContext(ctx, &git.PushOptions{
		RemoteName: "origin",
		RefSpecs:   refs,
		Auth:       r.auth,
		Atomic:     true,
	})
	if err != nil && !errors.Is(err, git.NoErrAlreadyUpToDate) {
		return fmt.Errorf("gitops.%s %s: %w", op, target, err)
	}
	return nil
}

func (r *Repo) resolve(rev string) (plumbing.Hash, error) {
	hash, err := r.repo.ResolveRevision(plumbing.Revision(rev))
	if err != nil {
		return plumbing.ZeroHash, err
	}
	return *hash, nil
}

func (r *Repo) ancestors(hash plumbing.Hash) (map[plumbing.Hash]struct{}, error) {
	seen := map[plumbing.Hash]struct{}{}
	iter, err := r.repo.Log(&git.LogOptions{From: hash})
	if err != nil {
		return nil, err
	}
	err = iter.ForEach(func(c *object.Commit) error {
		seen[c.Hash] = struct{}{}
		return nil
	})
	return seen, err
}

func toCommit(c *object.Commit) Commit {
	msg := c.Message
	subject, body := splitSubjectBody(msg)
	return Commit{SHA: c.Hash.String(), Subject: subject, Body: body}
}

func splitSubjectBody(msg string) (string, string) {
	msg = strings.TrimRight(msg, "\n")
	idx := strings.Index(msg, "\n")
	if idx < 0 {
		return msg, ""
	}
	return msg[:idx], strings.TrimLeft(msg[idx+1:], "\n")
}

func embedBasicAuth(raw, host, user, secret string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if u.Host == "" {
		// SSH-style URL: git@host:owner/repo.git -> rewrite to https.
		if at := strings.IndexByte(raw, '@'); at > 0 {
			rest := raw[at+1:]
			rest = strings.Replace(rest, ":", "/", 1)
			return fmt.Sprintf("https://%s:%s@%s", user, secret, rest), nil
		}
		return "", fmt.Errorf("cannot parse remote URL %q", raw)
	}
	u.Scheme = "https"
	u.Host = host
	u.User = url.UserPassword(user, secret)
	return u.String(), nil
}
