package version

import "testing"

// These tests pin the observable --version contract. The publish workflow
// injects Version/Commit/BuiltAt via `-ldflags -X`; if the format of Full()
// drifts silently, every operator running `panora-versioning --version`
// sees the break. The tests are contract-level, not formatter unit tests.

func TestFull_InjectedValues(t *testing.T) {
	orig := snapshot()
	defer restore(orig)

	Version = "v1.2.3"
	Commit = "abcdef1234567890abcdef1234567890abcdef12"
	BuiltAt = "2026-04-21T10:38:05Z"

	got := Full()
	want := "v1.2.3 (commit abcdef1234567890abcdef1234567890abcdef12, built 2026-04-21T10:38:05Z)"
	if got != want {
		t.Errorf("Full() contract drift\n got: %q\nwant: %q", got, want)
	}
}

func TestFull_DegradedDefaults(t *testing.T) {
	orig := snapshot()
	defer restore(orig)

	Version = "dev"
	Commit = "unknown"
	BuiltAt = "unknown"

	got := Full()
	want := "dev (commit unknown, built unknown)"
	if got != want {
		t.Errorf("Full() degraded contract drift\n got: %q\nwant: %q", got, want)
	}
}

type vars struct{ version, commit, builtAt string }

func snapshot() vars { return vars{Version, Commit, BuiltAt} }
func restore(v vars) { Version, Commit, BuiltAt = v.version, v.commit, v.builtAt }
