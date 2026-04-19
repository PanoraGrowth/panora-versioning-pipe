// Package version exposes build-time identity information injected via
// `-ldflags -X`. Defaults are placeholders used by local `go run` builds.
package version

import "fmt"

var (
	// Version is the semver tag the binary was built from (e.g. "v0.11.22").
	Version = "dev"
	// Commit is the short git SHA of the build.
	Commit = "unknown"
	// BuiltAt is the RFC3339 timestamp of the build.
	BuiltAt = "unknown"
)

// Full returns the canonical one-line version string.
func Full() string {
	return fmt.Sprintf("%s (commit %s, built %s)", Version, Commit, BuiltAt)
}

// Template is the cobra `--version` template. Cobra prepends the binary name
// automatically when it sees `{{.Name}}`; we opt in explicitly so the output
// reads like the bash scripts' self-reporting lines.
func Template() string {
	return fmt.Sprintf("panora-versioning %s\n", Full())
}
