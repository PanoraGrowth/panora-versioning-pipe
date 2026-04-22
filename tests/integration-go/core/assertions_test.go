package core

import "testing"

func TestContainsVersion(t *testing.T) {
	cases := []struct {
		name    string
		content string
		version string
		want    bool
	}{
		{"yaml double-quoted match", `version: "19.1"`, "19.1", true},
		{"yaml double-quoted NO substring trap", `version: "19.10"`, "19.1", false},
		{"json match", `{"version": "19.1"}`, "19.1", true},
		{"toml match", `version = "19.1"`, "19.1", true},
		{"plain match", "19.1\n", "19.1", true},
		{"empty content", "", "19.1", false},
		{"no version in content", `version: "0.0.0"`, "19.1", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := containsVersion([]byte(tc.content), tc.version)
			if got != tc.want {
				t.Errorf("containsVersion(%q, %q) = %v, want %v", tc.content, tc.version, got, tc.want)
			}
		})
	}
}
