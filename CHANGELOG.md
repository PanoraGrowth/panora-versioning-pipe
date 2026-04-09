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


