package core

import "strconv"

// Scenario represents a single integration test scenario loaded from YAML.
type Scenario struct {
	Name              string                 `yaml:"name"`
	Description       string                 `yaml:"description"`
	Base              string                 `yaml:"base"`
	MergeMethod       string                 `yaml:"merge_method"`
	BranchPrefix      string                 `yaml:"branch_prefix"`
	PRTitle           string                 `yaml:"pr_title"`
	MergeSubject      string                 `yaml:"merge_subject"`
	TagPrefixOverride string                 `yaml:"tag_prefix_override"`
	Merge             bool                   `yaml:"merge"`
	SeedTags          []string               `yaml:"seed_tags"`
	ConfigOverride    map[string]interface{} `yaml:"config_override"`
	Commits           []Commit               `yaml:"commits"`
	Expected          Expected               `yaml:"expected"`
	// SkipBitbucket marks a scenario as intentionally skipped on Bitbucket.
	// Use when a scenario depends on a GitHub-only primitive with no Bitbucket equivalent.
	SkipBitbucket bool `yaml:"skip_bitbucket"`
}

// Commit describes a single commit to create during setup.
type Commit struct {
	Message string            `yaml:"message"`
	Files   map[string]string `yaml:"files"`
}

// Expected holds the assertions to run after the scenario executes.
type Expected struct {
	PRCheck                string   `yaml:"pr_check"`
	TagCreated             bool     `yaml:"tag_created"`
	TagPattern             string   `yaml:"tag_pattern"`
	ChangelogContains      string   `yaml:"changelog_contains"`
	ChangelogLocation      string   `yaml:"changelog_location"`
	ChangelogLocations     []string `yaml:"changelog_locations"`
	ChangelogNotLocations  []string `yaml:"changelog_not_locations"`
	ChangelogSectionMarker string   `yaml:"changelog_section_marker"`
	VersionFileUpdated     bool     `yaml:"version_file_updated"`
	VersionFilePath        string   `yaml:"version_file_path"`
}

// IsMergeScenario returns true if the scenario requires a sandbox merge.
func (s Scenario) IsMergeScenario() bool {
	return s.Expected.TagCreated || s.Merge
}

// EffectiveBase returns the target branch (default: "main").
func (s Scenario) EffectiveBase() string {
	if s.Base != "" {
		return s.Base
	}
	return "main"
}

// EffectiveMergeMethod returns the merge method (default: "squash").
func (s Scenario) EffectiveMergeMethod() MergeMethod {
	switch s.MergeMethod {
	case "merge":
		return MergeMethodMerge
	default:
		return MergeMethodSquash
	}
}

// EffectivePRTitle returns the PR title (default: "test: {name}").
func (s Scenario) EffectivePRTitle() string {
	if s.PRTitle != "" {
		return s.PRTitle
	}
	return "test: " + s.Name
}

// EffectiveBranchPrefix returns the branch prefix (default: "test/auto").
func (s Scenario) EffectiveBranchPrefix() string {
	if s.BranchPrefix != "" {
		return s.BranchPrefix
	}
	return "test/auto"
}

// SandboxMajor extracts the numeric index from "sandbox-NN" base branches.
// Returns 0 for non-sandbox bases (e.g. "main").
func (s Scenario) SandboxMajor() int {
	base := s.EffectiveBase()
	if len(base) > 8 && base[:8] == "sandbox-" {
		n := 0
		for _, c := range base[8:] {
			if c < '0' || c > '9' {
				return 0
			}
			n = n*10 + int(c-'0')
		}
		return n
	}
	return 0
}

// TagPrefix returns the tag namespace for this scenario (e.g. "v3." for sandbox-03).
func (s Scenario) TagPrefix() string {
	if s.TagPrefixOverride != "" {
		return s.TagPrefixOverride
	}
	m := s.SandboxMajor()
	if m == 0 {
		return ""
	}
	return "v" + strconv.Itoa(m) + "."
}
