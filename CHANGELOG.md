# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- New entries are added automatically by panora-versioning-pipe -->
## v0.1.1 - 2026-04-06

- fix: remove duplicate comment line in config-parser.sh
  - _agustin.manessi_
  - [Commit: 4f844d5](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/4f844d5318adabcdc011f4fcbb53caf42db5e782)


## v0.1.2 - 2026-04-07

- refactor: consolidate version calculation and simplify orchestrators
  - _agustin.manessi_
  - [Commit: 14fd7c2](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/14fd7c23f3c405b1daae0527db70b08366957cf9)


## v0.2.0 - 2026-04-07

- feat: per-folder changelog exclusive routing with subfolder discovery
  - _agustin.manessi_
  - [Commit: fca88c3](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/fca88c3199f5619ae2cfbb49ac04f92847e18c47)


## v0.2.1 - 2026-04-07

- fix: remove broken ignore pattern that filtered all chore commits
  - _agustin.manessi_
  - [Commit: e17a3f2](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/e17a3f29c47fb5b874ba6aa43d8e67d0de434841)


## v0.2.2 - 2026-04-07

- fix: multi-commit changelog bugs in per-folder routing
  - _agustin.manessi_
  - [Commit: ec8262c](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ec8262c0385ea067a95f8f10df85d9f2b0704b39)


## v0.2.3 - 2026-04-07

- fix: Docker image tag respects v-prefix and docs commits skip versioning
  - _agustin.manessi_
  - [Commit: a9a6f3f](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/a9a6f3fced399d20d3cd39d934be48cd1f55e1aa)


## v0.3.0 - 2026-04-07

- feat: implement changelog emoji support and enable for this repo
  - _agustin.manessi_
  - [Commit: 917e3e4](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/917e3e401900ee5dbe75f90b2b0f8822a05308a1)


## v0.4.0 - 2026-04-08

- 🚀 feat: implement automated test framework (#24)
  - _Agustín Manessi_
  - [Commit: 9148f7a](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/9148f7ae1ad3201de724beb726d0b3478a3882f2)


## v0.4.1 - 2026-04-08

- 🐛 fix: atomic push for CHANGELOG and tag to prevent double release (#25)
  - _Agustín Manessi_
  - [Commit: fd3d85e](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/fd3d85e2d33c645df0992679ec1235abe50992a6)


## v0.4.2 - 2026-04-08

- Revert "ci: trigger pipeline test"
  - _agustin.manessi_
  - [Commit: 4eddfea](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/4eddfeaeacf7c6ffd59f8b05933169764442d281)


## v0.4.3 - 2026-04-08

- 🔧 chore: minor Makefile comment cleanup (#27)
  - _Agustín Manessi_
  - [Commit: 56c6e40](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/56c6e402f196c641f70444721d73a9105872eff2)


## v0.4.4 - 2026-04-08

- 🐛 fix: address code review findings (set -e, raw push, dead code, docs) (#28)
  - _Agustín Manessi_
  - [Commit: 9ee961a](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/9ee961a2c00644fd49ab9dca8c261ebc569fecca)


## v0.4.5 - 2026-04-08

- 🐛 fix: review findings — minimal permissions, consistent API, raw cat (#29)
  - _Agustín Manessi_
  - [Commit: 9633145](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/96331458465fc9a8ad823d67f5b7824ff190d703)


## v0.4.6 - 2026-04-09

- 🐛 fix: apply ignore patterns to commit subject, not full log line (#30)
  - _Agustín Manessi_
  - [Commit: ac8ed69](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ac8ed693862453619b3dadf7280b9f4d1ab0fc4a)


## v0.5.0 - 2026-04-09

- 🚀 feat: add Bitbucket integration tests — 8/8 scenarios passing (#31)
  - _Agustín Manessi_
  - [Commit: 6ff4db4](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/6ff4db466bae31d40320c1181c79fa02601d2bdc)


## v0.5.1 - 2026-04-09

- 🐛 fix: review findings — HTTP timeouts, .PHONY, docs update (#32)
  - _Agustín Manessi_
  - [Commit: 407470a](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/407470a80316b30d94ad00cc7724591e4be74371)


## v0.5.2 - 2026-04-10

- 🐛 fix(examples): align configs with v0.5.0 features (#33)
  - _Agustín Manessi_
  - [Commit: 61924f8](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/61924f8fbbb1bcd0bad4954bf9378cb8c840ef80)


## v0.5.3 - 2026-04-10

- 🔨 refactor(workflows): inline PR reusable and drop redundant env vars (#35)
  - _Agustín Manessi_
  - [Commit: e6d8118](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/e6d81189d96274bb6d7e6d2fced816941cccf867)


## v0.5.4 - 2026-04-10

- 🔨 refactor(workflows): remove dead paths-ignore for LICENSE (#36)
  - _Agustín Manessi_
  - [Commit: effbfae](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/effbfaed7277cad50a5ddd5a40a0383e9e8bf29e)


## v0.5.5 - 2026-04-10

- 🐛 fix(docs): align public documentation with v0.5.4 state (#37)
  - _Agustín Manessi_
  - [Commit: fad391b](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/fad391b8ff805d4fefae20a0aabf2ff841d7631f)


## v0.5.6 - 2026-04-10

- 🐛 fix(tests): rename multi-commit-highest-bump to multi-commit-last-wins (#38)
  - _Agustín Manessi_
  - [Commit: f8b98cd](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/f8b98cd40c2e24577331cbff03d5e35bbb2763a4)


## v0.5.7 - 2026-04-11

- 🧪 test(hotfix): cover generate-hotfix-changelog.sh and update-changelog.sh hotfix path (#43)
  - _Agustín Manessi_
  - [Commit: 0e96110](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/0e96110b63f4764803f90360288af0cbe9ee1c61)


## v0.5.8 - 2026-04-11

- ⚙️ ci(lint): add commit message hygiene lint (#42)
  - _Agustín Manessi_
  - [Commit: 12b9ec9](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/12b9ec95a87fe35c30006e8dfab1578d171d089b)


## v0.5.9 - 2026-04-11

- ⚙️ ci(release): add automated release readiness gate (#41)
  - _Agustín Manessi_
  - [Commit: c1871d7](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/c1871d73c7f235975d7608828c0adf59b2222f2d)


## v0.6.0 - 2026-04-11

- 🚀 feat(versioning): wire up hotfix flow with PATCH component (#45)
  - _Agustín Manessi_
  - [Commit: 0edd192](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/0edd192a4245b3328f69dda2eece4f5c009b0c58)


## v0.6.1 - 2026-04-11

- 🐛 fix: add hotfix example config and complete integration scenario override (#46)
  - _Agustín Manessi_
  - [Commit: 299c10f](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/299c10f5e168f4fcf6fd5f5f6dc6e3f69961cbbb)


## v0.6.2 - 2026-04-11

- 🐛 fix(version-file): strip tag_prefix_v when writing json/yaml targets (#48)
  - _Agustín Manessi_
  - [Commit: c032a00](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/c032a000e37436c1a66ea99b69698e90d8ee6e3b)


## v0.6.3 - 2026-04-12

- 🐛 fix(detection): platform-agnostic hotfix detection + scenario unification (#49)
  - _Agustín Manessi_
  - [Commit: 170ecf7](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/170ecf730ac6aaa5e31f554dff21cbdb8f65822f)


## v0.6.4 - 2026-04-12

- 🐛 fix: address review findings — set -e, write_state, stale doc reference (#50)
  - _Agustín Manessi_
  - [Commit: 6f1637e](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/6f1637e29068f6df284cf4037737b54a2747348e)


## v0.7.0 - 2026-04-12

- 🚀 feat(detection): multi-keyword hotfix detection with glob patterns (#33)
  - _agustin.manessi_
  - [Commit: 955288c](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/955288c2473571e05fdd0d71e05842cacd2da1ee)


## v0.8.0 - 2026-04-12

- 🚀 feat(tests): deep-merge config_override instead of replacing .versioning.yml (#51)
  - _Agustín Manessi_
  - [Commit: bda9815](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/bda98151a234f91151aa85514e619f5690edd387)


## v0.9.0 - 2026-04-12

- 🚀 feat(tests): add hotfix scoped and uppercase branch prefix integration scenarios (#52)
  - _Agustín Manessi_
  - [Commit: 1fb8796](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/1fb8796ee8b0888d31537e5cf70eb6ab2568d0d5)


## v0.9.1 - 2026-04-13

- 🐛 fix(lint): resolve all shellcheck warnings and add lint to CI (#54)
  - _Agustín Manessi_
  - [Commit: b6f7fb3](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/b6f7fb3083dade0fb904a4c6dc3003c88d7982fd)


## v0.10.0 - 2026-04-13

- 🚀 feat(publish): add floating version tags per release (#55)
  - _Agustín Manessi_
  - [Commit: b81df77](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/b81df7707b98c1674c0eddf3233e58b9c1a3d738)


## v0.10.1 - 2026-04-13

- 🔨 refactor(ci): remove :latest and migrate pipe to container.image (#56)
  - _Agustín Manessi_
  - [Commit: 78da33e](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/78da33e461d7ec80f5e75dca0ba43fbc4c4ea217)


## v0.11.0 - 2026-04-14

- 🚀 feat(tests): add preview image support for integration tests (#57)
  - _Agustín Manessi_
  - [Commit: 0c2ddcd](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/0c2ddcdd201c78de405a0eb18c4156ca454f7754)


## v0.11.1 - 2026-04-14

- 🐛 fix(tests): move /tmp writes inside flock to prevent race conditions (#58)
  - _Agustín Manessi_
  - [Commit: fca712f](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/fca712f5992aac7ec8ffa1c0d03c6e000d0b65f1)


## v0.11.2 - 2026-04-14

- 🐛 fix(validation): replace require_type_in_last_commit with require_commit_types (#59)
  - _Agustín Manessi_
  - [Commit: d281623](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/d2816232424924cccd32ac7b6d3c835c332e7f1a)


## v0.12 - 2026-04-15

- 🔨 refactor(config): rename period → epoch + SemVer-aligned bump mapping
  - _Agustín Manessi_
  - [Commit: ef4d21b](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ef4d21b31e467eea6420775331109e599ce4373e)


## v0.11.3 - 2026-04-16

- 🚀 feat(config): separate commit_types into commit-types.yml catalog (#63)
  - _Agustín Manessi_
  - [Commit: 913ba45](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/913ba453aae3826c2bdebe29b590af67ce77a431)


## v0.11.4 - 2026-04-16

- 🚀 feat(config): change timestamp.enabled default to false (#65)
  - _Agustín Manessi_
  - [Commit: 7cd42b6](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/7cd42b6a3858d6fa38d4a30f88ee6a7aae08d612)


## v0.11.5 - 2026-04-16

- 🚀 feat(detection): unify hotfix detection to branch name as single source of truth (#66)
  - _Agustín Manessi_
  - [Commit: 2363250](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/23632507505c3465bd7e0447ceb7d0d62b0e09bc)


## v0.11.6 - 2026-04-16

- 🐛 fix(tests): correct fix-patch-bump tag_pattern after timestamp.enabled default change (#67)
  - _Agustín Manessi_
  - [Commit: 0cfb9a8](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/0cfb9a80d10351929367c8d4027a279e284d0ad5)


## v0.11.7 - 2026-04-16

- 🚀 feat(version_file): unify config into groups, remove legacy top-level fields (#68)
  - _Agustín Manessi_
  - [Commit: ca43bd5](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ca43bd5b845bcc0afa8bda6c00793d05871fb442)


## v0.11.8 - 2026-04-17

- 🚀 feat(changelog): per-folder enhancements — glob folders, multi-level suffix, multi-folder write (#73)
  - _Agustín Manessi_
  - [Commit: 408d2dd](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/408d2dd9ae975bc06d2047fd90fe24c3b9ce4c19)


## v0.11.9 - 2026-04-17

- 🐛 fix(scripts): add set -e to all executable scripts (Finding #21) (#76)
  - _Agustín Manessi_
  - [Commit: b1c239f](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/b1c239f0f2f433468c55895016bf177afe3fb502)


## v0.11.10 - 2026-04-17

- 🐛 fix(scripts): document eval safety invariant and audit git log output chain (#78)
  - _Agustín Manessi_
  - [Commit: 745146e](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/745146e0b10288755ee3e1d41111e4d2019ef6a7)


## v0.11.11 - 2026-04-17

- 🐛 fix(lint): exempt Dependabot and Renovate PRs from commit hygiene lint (#87)
  - _Agustín Manessi_
  - [Commit: ebc18d4](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ebc18d4de4cea951f5ac2a793089d9f5d695abac)


## v0.11.12 - 2026-04-17

- 🐛 fix(ci): pin unpinned build-push-action and bump trivy-action to v0.35.0 (#88)
  - _Agustín Manessi_
  - [Commit: c98d92d](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/c98d92d8bfbcf505be845f71fe4d4c41b63cb0bb)


## v0.11.13 - 2026-04-17

- 🐛 fix(docker): apk upgrade to patch musl CVE-2026-40200 (HIGH) (#89)
  - _Agustín Manessi_
  - [Commit: bdc1324](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/bdc13243d3ec151cb4d03e6a3dc356951a71e42b)


## v0.11.14 - 2026-04-17

- 🐛 fix(version-file): create file when path has no glob chars (#94)
  - _Agustín Manessi_
  - [Commit: dc86249](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/dc86249c66a2d347aa623bb0baa2a8ab200fe6c7)


## v0.11.15 - 2026-04-17

- 🐛 fix(versioning): respect epoch.initial and major.initial with existing tags (#95)
  - _Agustín Manessi_
  - [Commit: e3f1342](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/e3f134269f41acadd7f5eca12d9e49aeba845d66)


## v0.1.3 - 2026-04-17

- 🚀 feat(validation): validate PR title as conventional commit (#99)
  - _Agustín Manessi_
  - [Commit: 725692e](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/725692e81d8e2efdcd5e648567ff0f22b7c5f2b4)


## v0.1.4 - 2026-04-17

- 🐛 fix(validation): accept hotfix keyword patterns as valid PR titles (#100)
  - _Agustín Manessi_
  - [Commit: 871fe62](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/871fe629abaf7906f52a2983b334d31d25778346)


## v0.1.5 - 2026-04-17

- 🐛 fix(validation): use eval for hotfix keyword glob matching in PR title (#101)
  - _Agustín Manessi_
  - [Commit: ded815f](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ded815f4932f696635a5d0b371ed64e2e603882f)


## v0.1.6 - 2026-04-17

- 🐛 fix(validation): remove false arm from eval case to avoid set-e exit in Alpine ash (#103)
  - _Agustín Manessi_
  - [Commit: 3c42942](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/3c4294252bb7e51be050d10b181c0865d9b197c9)


## v0.1.7 - 2026-04-17

- 🐛 fix(validation): escape open-paren in hotfix keywords before eval case expansion (#104)
  - _Agustín Manessi_
  - [Commit: 56e8778](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/56e8778a27ab1cd22fe3e0c920ac23bfb6440090)


## v0.1.8 - 2026-04-18

- 🚀 feat(validation): block hotfix PR merge when title lacks hotfix keyword (#105)
  - _Agustín Manessi_
  - [Commit: 861de46](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/861de46db73465215c18cfadd9f9b305fd8fdc6a)


## v0.1.9 - 2026-04-18

- 🐛 fix(detection): detect hotfix when tag_on and hotfix_target are the same branch (#107)
  - _Agustín Manessi_
  - [Commit: 8aefd78](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/8aefd78fcce29d99da0115b063428994c9395c8e)


## v0.1.10 - 2026-04-18

- 🚀 feat(versioning): couple bump strategy to changelog.mode (#108)
  - _Agustín Manessi_
  - [Commit: ffc698a](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ffc698a090127be0ca2df8cf169828e9efc0b6cb)


## v0.1.11 - 2026-04-18

- 🐛 fix(version_file): repair trigger_paths in branch pipeline + cover bump strategy docs (#111)
  - _Agustín Manessi_
  - [Commit: b98ed8d](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/b98ed8d387cbaff5d87339ad7a71507c49e95daf)


## v0.1.12 - 2026-04-18

- 🐛 fix: update publish workflow trigger to use unified Versioning workflow (#113)
  - _Agustín Manessi_
  - [Commit: f100e9b](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/f100e9bb5e22884d74e1c988beb76d4a9f3fb4ac)


## v0.1.13 - 2026-04-18

- 🐛 fix(integration): eliminate spurious workflow_dispatch + harness cleanup (#114)
  - _Agustín Manessi_
  - [Commit: 355e2d0](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/355e2d066c72643663edefd41b18cf572523707c)


## v0.11.16 - 2026-04-18

- 🐛 fix(versioning): initial=0 no longer resets version silently (#059) (#115)
  - _Agustín Manessi_
  - [Commit: 4382308](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/4382308047cb26b3c1a0505bfad679a6efab2334)


## v0.11.17 - 2026-04-19

- 🚀 feat(validation): runtime guardrail blocks version regression (#060) (#116)
  - _Agustín Manessi_
  - [Commit: 0a05b17](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/0a05b172303b7de0d2455ff6a8cc0b608a6c8275)


## v0.11.18 - 2026-04-19

- 🐛 fix(integration): extend harness for merge-but-no-tag scenarios + remove unrepresentable guardrail scenario (#117)
  - _Agustín Manessi_
  - [Commit: c15d617](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/c15d61742dc2ae43a5a82c09d1b429a8de3ff391)


## v0.11.19 - 2026-04-19

- 🐛 fix(ci): prevent Release from firing on unified Versioning PR runs (#119)
  - _Agustín Manessi_
  - [Commit: 4237f90](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/4237f908ea69461ee5457bbf2f816d9908ff81a3)


## v0.11.20 - 2026-04-19

- 🐛 fix(ci): document the workflow_run if-gate in publish.yml (#120)
  - _Agustín Manessi_
  - [Commit: 6f6c150](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/6f6c1505ac99e94785cb5d46ab3f05730a281999)


## v0.11.21 - 2026-04-19

- 🐛 fix(ci): switch Release trigger to tag push instead of workflow_run (#121)
  - _Agustín Manessi_
  - [Commit: f94fc2d](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/f94fc2dfaa63b58603bb51bd5b36ac0e31227294)


## v0.11.22 - 2026-04-19

- ⏪ revert(ci): restore workflow_run trigger for Release (#121) (#122)
  - _Agustín Manessi_
  - [Commit: 5091ef0](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/5091ef0caa31b004e8a7be466cb7ff958b018f74)


## v0.11.23 - 2026-04-19

- 🚀 feat(go): bootstrap Go foundation + port configure-git (GO-00) (#123)
  - _Agustín Manessi_
  - [Commit: c21ea5e](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/c21ea5e7cdc413224d49f2560c63f9cf7b8aa29d)


## v0.11.24 - 2026-04-19

- 🐛 fix(go): ignore Fprintf return in stub + document Go toolchain floor (#124)
  - _Agustín Manessi_
  - [Commit: b26f938](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/b26f9386124036ccf2562e2d7d3c1e8184a4b0b7)


## v0.11.25 - 2026-04-19

- 🐛 fix(deps): bump golang.org/x/crypto to v0.35.0 (CVE-2025-22869) (#125)
  - _Agustín Manessi_
  - [Commit: e332152](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/e332152edbfeda1c7dd6ef0a637adc4c52f4d5c9)


## v0.11.26 - 2026-04-19

- 🚀 feat(go): port reporting adapters to Go (GO-04)
  - _Agustín Manessi_
  - [Commit: d00777d](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/d00777d498d156143769c6b357964d858f4267a8)


## v0.11.27 - 2026-04-19

- 🚀 feat(go): port validate-commits + check-commit-hygiene to Go (GO-03)
  - _Agustín Manessi_
  - [Commit: 181e270](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/181e270937a07424bbd27089f5b58f79b95ee1ec)


## v0.11.28 - 2026-04-19

- 🚀 feat(go): port calc-version to Go (GO-01) (#130)
  - _Agustín Manessi_
  - [Commit: da8a9a0](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/da8a9a0fe9b362c70b6700aa38902fb4591b7133)


## v0.11.29 - 2026-04-19

- 🚀 feat(go): port guardrails + run-guardrails to Go (GO-05) (#126)
  - _Agustín Manessi_
  - [Commit: 5867ea2](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/5867ea2e3ebbe0a1714842f3f9ac1eb42a528747)


## v0.11.30 - 2026-04-19

- 🐛 fix(go): wire Wave 1 subcommands lost in merge conflict (#131)
  - _Agustín Manessi_
  - [Commit: ef2221a](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/ef2221ab135e9efeb6e65e723b82e0b68f517b9e)


## v0.11.31 - 2026-04-19

- 🚀 feat(ci): run Go integration tests in go-ci.yml + drop stub safety net (#133)
  - _Agustín Manessi_
  - [Commit: 7eabc4a](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/7eabc4a3990f16fccc3cab9a7e08483370ad3025)


## v0.11.32 - 2026-04-20

- 🚀 feat(go): add typed config loader for merged YAML (GO-09) (#134)
  - _Agustín Manessi_
  - [Commit: a85da59](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/a85da592dadd377b0cca77ab3a85283d00da677e)


## v0.11.33 - 2026-04-20

- 🚀 feat(go): port write-version-file to Go (GO-06) (#143)
  - _Agustín Manessi_
  - [Commit: 9175713](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/917571326f20b3fb69a95e622e7efb16dd0de7d6)


## v0.11.34 - 2026-04-20

- 🚀 feat(go): port check-release-readiness to Go (GO-08)
  - _CI Pipeline_
  - [Commit: af137a6](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/af137a6641832a11c52a2f3b43e270f3288d3b02)


## v0.11.35 - 2026-04-20

- 🚀 feat(go): port changelog generation to Go (GO-07)
  - _CI Pipeline_
  - [Commit: 01fe886](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/01fe886404c43b0211cce93fb25c44c67f24f573)


## v0.11.36 - 2026-04-20

- 🐛 fix(versioning): write bump_type=hotfix in hotfix scenario (#146)
  - _Agustín Manessi_
  - [Commit: 95d5a36](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/95d5a367775843ba1584a2eaace2835ac55acdf1)


## v0.11.37 - 2026-04-20

- 🚀 feat(go): port config-parser.sh to Go (GO-10) (#149)
  - _Agustín Manessi_
  - [Commit: 610e0d1](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/610e0d1df111e2bda91eff1835af434fc2627002)


## v0.11.38 - 2026-04-21

- 🚀 feat(go): port pr/branch orchestrators + pipe.sh dispatch to Go (GO-11) (#150)
  - _Agustín Manessi_
  - [Commit: 0030f07](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/0030f070b1fc536829832b272637be52efb94689)


## v1.0 - 2026-04-21

- 🚀 feat(go)!: cutover a binario único — eliminación de bash runtime
  - _Agustín Manessi_
  - [Commit: 831b577](https://github.com/PanoraGrowth/panora-versioning-pipe/commit/831b5774c1121e9e5c4425cac0ff068bde961e37)


