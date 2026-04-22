package core

import (
	"sort"
	"testing"
)

func TestComputeExcludesByPrefix(t *testing.T) {
	cases := []struct {
		name         string
		scenarios    []Scenario
		queryPrefix  string
		wantExcludes []string
	}{
		{
			name: "epoch_override_excluded_from_major",
			scenarios: []Scenario{
				{Base: "sandbox-01"},          // prefix: v1.
				{TagPrefixOverride: "v1.27."}, // prefix: v1.27.
				{Base: "sandbox-02"},          // prefix: v2.
			},
			queryPrefix:  "v1.",
			wantExcludes: []string{"v1.27."},
		},
		{
			name: "epoch_prefix_has_no_excludes",
			scenarios: []Scenario{
				{Base: "sandbox-01"},
				{TagPrefixOverride: "v1.27."},
			},
			queryPrefix:  "v1.27.",
			wantExcludes: []string{},
		},
		{
			name: "unrelated_prefixes_dont_exclude_each_other",
			scenarios: []Scenario{
				{Base: "sandbox-01"}, // v1.
				{Base: "sandbox-02"}, // v2.
				{Base: "sandbox-09"}, // v9.
			},
			queryPrefix:  "v1.",
			wantExcludes: []string{},
		},
		{
			// Hotfix tags like v9.1.1 are NOT excluded by "v9." — the sandbox-09 prefix
			// is "v9." and the hotfix tag belongs to the same namespace.
			name: "hotfix_tag_not_excluded_for_same_sandbox",
			scenarios: []Scenario{
				{Base: "sandbox-09"}, // v9.  — produces v9.0.1 hotfix tags
				{Base: "sandbox-10"}, // v10. — unrelated
			},
			queryPrefix:  "v9.",
			wantExcludes: []string{},
		},
		{
			// Two scenarios sharing the same prefix (same sandbox) must NOT exclude each other.
			name: "identical_prefixes_dont_exclude",
			scenarios: []Scenario{
				{Base: "sandbox-01"},
				{Base: "sandbox-01"},
			},
			queryPrefix:  "v1.",
			wantExcludes: []string{},
		},
		{
			// Empty prefix (no-merge scenarios targeting main) — nothing to exclude.
			name: "empty_prefix_no_excludes",
			scenarios: []Scenario{
				{},             // prefix: "" (no sandbox base)
				{Base: "main"}, // prefix: "" (non-sandbox base)
			},
			queryPrefix:  "",
			wantExcludes: []string{},
		},
		{
			// "v1." is NOT a string-prefix of "v12." — the dot boundary prevents the trap.
			// HasPrefix("v12.", "v1.") == false because the character after "v1" is "2", not ".".
			// This confirms the invariant that all prefixes end in ".".
			name: "partial_string_prefix_trap_prevented_by_dot",
			scenarios: []Scenario{
				{Base: "sandbox-01"},          // v1.
				{Base: "sandbox-12"},          // v12.  — must NOT be excluded by v1.
				{TagPrefixOverride: "v1.27."}, // v1.27. — must be excluded by v1.
			},
			queryPrefix:  "v1.",
			wantExcludes: []string{"v1.27."},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result := computeExcludesByPrefix(tc.scenarios)
			got := result[tc.queryPrefix]
			if got == nil {
				got = []string{}
			}
			sort.Strings(got)
			sort.Strings(tc.wantExcludes)

			if len(got) != len(tc.wantExcludes) {
				t.Fatalf("excludes for %q: got %v, want %v", tc.queryPrefix, got, tc.wantExcludes)
			}
			for i := range got {
				if got[i] != tc.wantExcludes[i] {
					t.Errorf("excludes[%d]: got %q, want %q", i, got[i], tc.wantExcludes[i])
				}
			}
		})
	}
}
