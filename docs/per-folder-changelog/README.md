# Per-folder CHANGELOG

Generate separate CHANGELOG files in subdirectories of a monorepo, routing commit entries by scope to the correct folder.

---

## Prerequisites

- `commits.format: "conventional"` (per-folder requires conventional commits with scopes)

---

## Configuration

```yaml
changelog:
  mode: "last_commit"           # "last_commit" (default) | "full"
  per_folder:
    enabled: true               # default: false
    folders:                    # list of folder paths that get their own CHANGELOG
      - "backend"
      - "frontend"
      - "infra"
    scope_matching: "exact"     # "exact" | "suffix"
    fallback: "file_path"       # "file_path" | "root" (default: "root")
    folder_pattern: ""          # regex filter for subfolders (suffix mode only)
```

### Configuration options

#### `changelog.mode`

Controls how many commits are included in each CHANGELOG entry.

| Value | Behavior |
|-------|----------|
| `last_commit` | Only the LAST commit in the PR is included (default, backward compatible) |
| `full` | ALL commits between the previous tag and HEAD are included |

#### `per_folder.enabled`

Enables or disables per-folder CHANGELOG routing. When `false`, all entries go to the root `CHANGELOG.md`.

#### `per_folder.folders`

List of directory paths where separate CHANGELOGs are maintained. Can be at any nesting level:

```yaml
folders:
  - "backend"                           # top-level folder
  - "frontend"                          # top-level folder
  - "backend/auth-service/microservices" # deep nesting (explicit path)
```

#### `per_folder.scope_matching`

How the commit scope is matched against folders.

| Value | Behavior | Example |
|-------|----------|---------|
| `exact` | Scope must match the folder name exactly, or a subfolder name within a configured folder | `feat(backend):` matches `backend/`, `feat(auth-service):` matches `backend/auth-service/` |
| `suffix` | Scope matches the suffix of a subfolder name after a dash | `feat(ecs):` matches `001-cluster-ecs/` |

#### `per_folder.fallback`

What to do when a scope doesn't match any configured folder or discoverable subfolder.

| Value | Behavior |
|-------|----------|
| `root` | Entry goes to root `CHANGELOG.md` (default, backward compatible) |
| `file_path` | Check which files the commit modified. If files fall within ONE configured folder, route there. Otherwise, root. |

#### `per_folder.folder_pattern`

Regex filter for subfolders (suffix mode only). Only subfolders matching this pattern are considered.

```yaml
folder_pattern: "^[0-9]{3}-"    # matches: 001-networking, 002-cluster-ecs
```

---

## Routing flow

Every commit is routed through this decision tree:

```
1. Has scope?
   NO  --> root CHANGELOG.md
   YES --> continue

2. Scope matches a configured folder name?
   YES --> {folder}/CHANGELOG.md
   NO  --> continue

3. Scope matches a SUBFOLDER within any configured folder?
   (scans one level deep: {folder}/{scope}/ — must exist on filesystem)
   YES --> {folder}/{scope}/CHANGELOG.md
   NO  --> continue

4. Is fallback == "file_path"?
   NO  --> root CHANGELOG.md
   YES --> continue

5. Do the commit's modified files fall within ONE configured folder?
   YES --> {folder}/CHANGELOG.md
   NO  --> root CHANGELOG.md (ambiguous or outside configured folders)
```

### Exclusive routing

Each commit entry goes to EITHER a subfolder CHANGELOG OR the root CHANGELOG, never both. This prevents duplicate entries.

### Subfolder discovery

The system automatically scans **one level** of subdirectories within each configured folder. If a subfolder name matches the commit scope exactly and the folder exists on the filesystem, the CHANGELOG is created there.

For deeper nesting, add the full path to `folders` explicitly:

```yaml
folders:
  - "backend"
  - "backend/auth-service/microservices"   # explicit deep path
```

---

## Examples

### Example 1: exact mode with subfolder discovery

**Config:**
```yaml
changelog:
  per_folder:
    enabled: true
    folders: ["backend", "frontend", "infra"]
    scope_matching: "exact"
    fallback: "file_path"
```

**Repository structure:**
```
repo/
├── backend/
│   ├── auth-service/
│   │   └── src/
│   ├── api-gateway/
│   │   └── src/
│   └── shared-libs/
│       └── utils.py
├── frontend/
│   ├── web-app/
│   │   └── src/
│   └── mobile-app/
│       └── src/
├── infra/
│   ├── 001-networking/
│   ├── 002-cluster-ecs/
│   └── 003-monitoring/
├── docs/
│   └── architecture.md
├── scripts/
│   └── deploy.sh
└── CHANGELOG.md
```

**Routing results:**

| Commit | Files touched | Route | Destination CHANGELOG | Why |
|--------|-------------|-------|----------------------|-----|
| `feat(backend): new util` | `backend/utils.py` | Step 2: scope == folder | `backend/CHANGELOG.md` | Direct match |
| `feat(auth-service): add OAuth` | `backend/auth-service/src/oauth.py` | Step 3: subfolder discovery | `backend/auth-service/CHANGELOG.md` | Subfolder exists |
| `feat(api-gateway): new route` | `backend/api-gateway/src/route.py` | Step 3: subfolder discovery | `backend/api-gateway/CHANGELOG.md` | Subfolder exists |
| `feat(cloudfront): add CDN` | `backend/cdn.py` | Step 5: file_path fallback | `backend/CHANGELOG.md` | `cloudfront/` doesn't exist, files in `backend/` |
| `fix(mobile-app): fix nav` | `frontend/mobile-app/src/nav.tsx` | Step 3: subfolder discovery | `frontend/mobile-app/CHANGELOG.md` | Subfolder exists |
| `chore(scripts): deploy fix` | `scripts/deploy.sh` | Step 5: no match | `CHANGELOG.md` (root) | `scripts/` not configured |
| `feat: add feature` | `backend/new.py` | Step 1: no scope | `CHANGELOG.md` (root) | No scope = no routing |
| `feat(api): full stack` | `backend/api.py` + `frontend/api.tsx` | Step 5: ambiguous | `CHANGELOG.md` (root) | Files in multiple folders |

### Example 2: suffix mode (numbered folders)

**Config:**
```yaml
changelog:
  per_folder:
    enabled: true
    folders: ["infrastructure"]
    scope_matching: "suffix"
    folder_pattern: "^[0-9]{3}-"
```

**Repository structure:**
```
infrastructure/
├── 001-cluster-ecs/
├── 002-networking/
└── 003-monitoring/
```

**Routing results:**

| Commit | Destination CHANGELOG | Why |
|--------|----------------------|-----|
| `feat(cluster-ecs): add config` | `infrastructure/001-cluster-ecs/CHANGELOG.md` | Suffix match: `*-cluster-ecs` |
| `fix(networking): fix routes` | `infrastructure/002-networking/CHANGELOG.md` | Suffix match: `*-networking` |
| `feat(unknown): change` | `CHANGELOG.md` (root) | No suffix match found |

### Example 3: multi-commit with mode "full"

**Config:**
```yaml
changelog:
  mode: "full"
  per_folder:
    enabled: true
    folders: ["backend", "frontend"]
    scope_matching: "exact"
    fallback: "file_path"
```

**PR with 4 commits:**
```
1. feat(backend): new API endpoint
2. feat(auth-service): add OAuth support
3. fix(frontend): fix login page
4. chore: update CI config
```

**Result:**
```
backend/CHANGELOG.md:
  ## v0.3.0 - 2026-04-07
  - feat(backend): new API endpoint

backend/auth-service/CHANGELOG.md:
  ## v0.3.0 - 2026-04-07
  - feat(auth-service): add OAuth support

frontend/CHANGELOG.md:
  ## v0.3.0 - 2026-04-07
  - fix(frontend): fix login page

CHANGELOG.md (root):
  ## v0.3.0 - 2026-04-07
  - chore: update CI config
```

---

## Execution order

The changelog scripts run in this order:

```
1. generate-changelog-per-folder.sh
   → Routes commits to subfolder CHANGELOGs
   → Writes /tmp/routed_commits.txt (list of commits already handled)

2. generate-changelog-last-commit.sh (or generate-changelog.sh in full mode)
   → Reads /tmp/routed_commits.txt
   → EXCLUDES already-routed commits
   → Writes remaining commits to root CHANGELOG.md
```

This ensures exclusive routing: no commit appears in both a subfolder and root CHANGELOG.
