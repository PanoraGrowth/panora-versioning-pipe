package versioning

import (
	"github.com/PanoraGrowth/panora-versioning-pipe/internal/config"
)

// FromConfig projects the fields needed by versioning from the canonical config.
func FromConfig(c *config.Config) (BumpConfig, VersionConfig) {
	bumpCfg := BumpConfig{}
	for _, ct := range c.CommitTypes {
		bumpCfg.CommitTypes = append(bumpCfg.CommitTypes, CommitType{
			Name: ct.Name,
			Bump: BumpType(ct.Bump),
		})
	}

	v := c.Version.Components
	verCfg := VersionConfig{
		EpochEnabled:         v.Epoch.Enabled,
		EpochInitial:         v.Epoch.Initial,
		MajorEnabled:         v.Major.Enabled,
		MajorInitial:         v.Major.Initial,
		PatchEnabled:         v.Patch.Enabled,
		PatchInitial:         v.Patch.Initial,
		HotfixCounterEnabled: v.HotfixCounter.Enabled,
		HotfixCounterInitial: v.HotfixCounter.Initial,
		TagPrefixV:           c.Version.TagPrefixV,
	}

	return bumpCfg, verCfg
}
