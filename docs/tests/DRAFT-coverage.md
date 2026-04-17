# Cobertura de Tests — Draft (revisión de formato)

> Draft que cubre las secciones: `commits`, `tickets`, `validation`, `changelog`, `changelog.per_folder`, `version`.
> El objetivo es encontrar el formato antes de escribir el documento completo.

---

Cada sección mapea directamente a [`scripts/defaults.yml`](../../scripts/defaults.yml). Cada key linkea a su definición. La columna de cobertura indica si el comportamiento está validado por tests unitarios.

Leyenda: ✅ cubierto · ⚠️ parcial · ❌ sin test

---

## commits

[→ defaults.yml:9](../../scripts/defaults.yml#L9)

Controla cómo se estructuran e interpretan los mensajes de commit.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`commits.format`](../../scripts/defaults.yml#L10) | `"ticket"` · `"conventional"` | `conventional` → `tipo(scope): mensaje` aceptado/rechazado · `ticket` → `AM-1234 - tipo: mensaje` aceptado/rechazado | ✅ ambos |

---

## tickets

[→ defaults.yml:12](../../scripts/defaults.yml#L12)

Aplica cuando `commits.format` es `"ticket"`. Controla la validación de prefijos y el linkeo en changelogs.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`tickets.prefixes`](../../scripts/defaults.yml#L13) | `string[]` · default `[]` | Vacío = cualquier prefijo se acepta · Con valores = solo los prefijos listados pasan validación | ✅ ambos |
| [`tickets.required`](../../scripts/defaults.yml#L14) | `true` · `false` | `false` = commit sin ticket pasa · `true` = commit sin ticket es rechazado | ✅ ambos |
| [`tickets.url`](../../scripts/defaults.yml#L15) | `string` · default `""` | El getter lee el valor correctamente | ⚠️ solo getter — el renderizado del link no está probado |

---

## validation

[→ defaults.yml:17](../../scripts/defaults.yml#L17)

Controla qué commits son aceptados y cuáles se ignoran durante el cálculo de versión.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`validation.require_ticket_prefix`](../../scripts/defaults.yml#L18) | `true` · `false` | `false` = commit sin prefijo pasa · `true` = commit sin prefijo es rechazado | ✅ ambos |
| [`validation.require_commit_types`](../../scripts/defaults.yml#L19) | `true` · `false` | `false` = validación desactivada · `true` + `changelog.mode: last_commit` = solo el último commit debe tener tipo · `true` + `changelog.mode: full` = todos los commits deben tener tipo | ✅ todos |
| [`validation.ignore_patterns`](../../scripts/defaults.yml#L20) | `string[]` | Commits que matchean los patrones son ignorados · Merge commits, reverts, fixup!, squash!, chore(release), chore(hotfix) cubiertos | ✅ |

---

## changelog

[→ defaults.yml:164](../../scripts/defaults.yml#L164)

Controla cómo se genera y escribe el archivo CHANGELOG.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`changelog.file`](../../scripts/defaults.yml#L165) | `string` · default `"CHANGELOG.md"` | El getter retorna el nombre de archivo correcto | ✅ |
| [`changelog.title`](../../scripts/defaults.yml#L166) | `string` · default `"Changelog"` | El getter retorna el título correcto | ✅ |
| [`changelog.mode`](../../scripts/defaults.yml#L167) | `"last_commit"` · `"full"` | `last_commit` = solo el último commit se escribe · `full` = todos los commits desde el último tag | ✅ ambos |
| [`changelog.use_emojis`](../../scripts/defaults.yml#L168) | `true` · `false` | El getter lee el valor · el rendering con/sin emojis en el output no está probado en unit tests | ⚠️ solo getter |
| [`changelog.include_commit_link`](../../scripts/defaults.yml#L169) | `true` · `false` | El getter retorna el valor correcto | ✅ |
| [`changelog.include_ticket_link`](../../scripts/defaults.yml#L170) | `true` · `false` | El getter retorna el valor correcto | ✅ |
| [`changelog.include_author`](../../scripts/defaults.yml#L171) | `true` · `false` | El getter retorna el valor correcto | ✅ |
| [`changelog.commit_url`](../../scripts/defaults.yml#L172) | `string` · default `""` | El getter retorna vacío por default | ⚠️ solo getter — construcción de la URL en el output no está probada |
| [`changelog.ticket_link_label`](../../scripts/defaults.yml#L173) | `string` · default `"View ticket"` | El getter retorna el label correcto | ✅ |

### changelog.per_folder

[→ defaults.yml:178](../../scripts/defaults.yml#L178)

Habilita changelogs independientes por carpeta. Requiere `commits.format: conventional`. El routing es exclusivo — cada commit va a una sola carpeta o al root, nunca a ambos.

**`changelog.per_folder.enabled`** — `true` · `false`

| Valor | Escenario probado | Cobertura |
|-------|-------------------|-----------|
| `true` | Routing por carpeta activo — commits con scope son dirigidos a su carpeta | ✅ |
| `false` | Todo va al CHANGELOG raíz | ✅ |

---

**`changelog.per_folder.folders`** — `string[]` · default `[]` · [→ L180](../../scripts/defaults.yml#L180)

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| Lista con múltiples carpetas raíz (`services`, `infrastructure`) | Búsqueda se extiende a todas las carpetas configuradas | ✅ |
| Carpeta raíz inexistente | Se ignora gracefully, no rompe la ejecución | ✅ |
| Glob pattern (`shared/*`) | Expande a subdirectorios directos de `shared/` | ✅ |
| Glob pattern con padre inexistente | No rompe la ejecución | ✅ |

---

**`changelog.per_folder.folder_pattern`** — `string` (regex) · default `""` · [→ L181](../../scripts/defaults.yml#L181)

Ejemplos de uso:
- `"^[0-9]{3}-"` → solo carpetas con prefijo numérico: `001-cluster-ecs/`, `002-cluster-rds/`, `003-api-gateway/`
- `""` → sin filtro, todas las subcarpetas son candidatas

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| Patrón `^[0-9]{3}-` | Solo subcarpetas con prefijo numérico son candidatas | ✅ |
| Carpeta que matchea el scope pero NO el patrón (`cluster-ecs/` sin prefijo) | Ignorada — no se usa como destino | ✅ |
| Patrón vacío `""` | Sin filtro — todas las subcarpetas son candidatas | ✅ |

---

**`changelog.per_folder.scope_matching`** — `"suffix"` · `"exact"` · [→ L182](../../scripts/defaults.yml#L182) · [escenario: suffix](per-folder/suffix-matching.md) · [escenario: exact](per-folder/exact-matching.md)

| Valor | Escenario probado | Comportamiento | Cobertura |
|-------|-------------------|----------------|-----------|
| `suffix` | scope `cluster-ecs` → carpeta `001-cluster-ecs/` | La carpeta termina con el scope | ✅ |
| `suffix` | scope `cluster-rds` con múltiples subcarpetas | Encuentra la correcta entre varias | ✅ |
| `suffix` | scope sin match en ninguna subcarpeta | Retorna vacío | ✅ |
| `suffix` | scope vacío | Retorna vacío | ✅ |
| `suffix` | scope matchea subcarpeta a 2 niveles de profundidad (`services/003-api-gateway/001-routes/`) | Encuentra con default depth=2 | ✅ |
| `suffix` | scope más profundo que `scope_matching_depth` | No matchea — respeta el límite | ✅ |
| `exact` | scope `api-gateway` → carpeta `api-gateway/` | El nombre de carpeta debe ser igual al scope | ✅ |
| `exact` | scope `services` → carpeta raíz `services/` | Coincidencia exacta en carpeta raíz | ✅ |
| `exact` | scope sin carpeta matching | Retorna vacío | ✅ |

---

**`changelog.per_folder.scope_matching_depth`** — `integer` · default `2` · solo aplica a `scope_matching: "suffix"`

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| Default `2` — encuentra subcarpeta a nivel 2 | `services/003-api-gateway/001-routes/` matchea | ✅ |
| Default `2` — no llega a nivel 3 | `services/001/002/003-routes/` no matchea | ✅ |

---

**`changelog.per_folder.fallback`** — `"root"` · `"file_path"` · [→ L184](../../scripts/defaults.yml#L184) · [escenario: file_path](per-folder/fallback-file-path.md)

| Valor | Escenario probado | Comportamiento | Cobertura |
|-------|-------------------|----------------|-----------|
| `root` | Commit sin scope matching | Va al CHANGELOG raíz | ✅ |
| `file_path` | Commit toca archivos en una sola carpeta configurada (`api/main.go`) | Resuelve a esa carpeta | ✅ |
| `file_path` | Commit toca múltiples archivos en la misma carpeta (`web/index.html`, `web/style.css`) | Resuelve a esa carpeta | ✅ |
| `file_path` | Commit toca archivos en carpetas distintas (`api/main.go`, `web/index.html`) | Escribe en ambas carpetas | ✅ |
| `file_path` | Commit toca archivos en 3 carpetas distintas | Escribe en las 3 carpetas | ✅ |
| `file_path` | Commit toca archivos fuera de todas las carpetas configuradas (`docs/readme.md`) | Sin match — retorna vacío | ✅ |
| `file_path` | Commit toca archivos en carpeta configurada + archivos en root (`api/main.go`, `README.md`) | Los archivos en root se ignoran, resuelve a la carpeta | ✅ |
| `file_path` | Commit toca solo archivos en root (`README.md`) | Sin match — retorna vacío | ✅ |
| `file_path` | Archivos anidados dentro de carpeta configurada (`shared/utils/helpers.sh`) | Resuelve correctamente la carpeta padre | ✅ |

---

## version.components

[→ defaults.yml:29](../../scripts/defaults.yml#L29)

Controla qué componentes forman el número de versión y sus valores iniciales. Los componentes se renderizan en orden: `epoch.major.patch[.hotfix_counter][.timestamp]`.

**`version.components.epoch`** — [→ L30](../../scripts/defaults.yml#L30)

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| `epoch.enabled` | `true` · `false` · default `false` | `true` → agrega primer componente al tag (`1.0.0`) · `false` → tag empieza en major (`0.5.9`) | ✅ ambos |
| `epoch.initial` | `integer` · default `0` | Valor de inicio cuando el componente se habilita por primera vez | ✅ |

---

**`version.components.major`** — [→ L33](../../scripts/defaults.yml#L33)

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| `major.enabled` | `true` · `false` · default `true` | `true` → incluido en el tag · bump major → incrementa, resetea patch y hotfix_counter a 0 | ✅ |
| `major.initial` | `integer` · default `0` | Valor de inicio al crear el primer tag | ✅ |

---

**`version.components.patch`** — [→ L36](../../scripts/defaults.yml#L36)

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| `patch.enabled` | `true` · `false` · default `true` | `true` → incluido en el tag · `fix/security/revert/perf` incrementan patch, resetean hotfix_counter a 0 · `false` → patch no aparece en el tag, commits con `bump: patch` son no-op | ✅ ambos |
| `patch.initial` | `integer` · default `0` | Valor de inicio — primer tag renderiza `0.12.0` (patch=0 siempre se incluye) · `0.12.0` → primer fix → `0.12.1` | ✅ |

---

**`version.components.hotfix_counter`** — [→ L46](../../scripts/defaults.yml#L46)

Componente especial del flujo hotfix (v0.6.3+). Cuando está habilitado, un commit de tipo `hotfix` incrementa este componente. El tag se renderiza como `v0.5.9.1` — el `.0` se omite por backward compatibility.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| `hotfix_counter.enabled` | `true` · `false` · default `true` | `true` → hotfix bumps hotfix_counter (`0.5.9` → `0.5.9.1`) · `false` → hotfix es no-op (sin tag, log info) | ✅ ambos |
| `hotfix_counter.initial` | `integer` · default `0` | Valor de inicio · reset a 0 cuando se bumpa major o patch | ✅ |

---

**`version.components.timestamp`** — [→ L49](../../scripts/defaults.yml#L49)

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| `timestamp.enabled` | `true` · `false` · default `false` | `true` → timestamp appended al tag (`0.5.9.20260407120000`) · `false` → tag sin timestamp | ✅ ambos |
| `timestamp.format` | `string` (strftime) · default `"%Y%m%d%H%M%S"` | Formato aplicado al generar el timestamp · getter probado | ⚠️ solo getter — formato alternativo no probado en output |
| `timestamp.timezone` | `string` · default `"UTC"` | TZ aplicada al generar el timestamp · `build_full_tag` respeta el timezone · solo probado con `UTC` — otras zonas (`America/Buenos_Aires`, `Europe/Madrid`) sin test | ⚠️ solo UTC |

---

## version.tag_prefix_v

[→ defaults.yml:54](../../scripts/defaults.yml#L54)

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`version.tag_prefix_v`](../../scripts/defaults.yml#L54) | `true` · `false` · default `false` | `true` → tags con `v` (`v0.5.9`) · version files escritos sin `v` (npm compat) · `false` → tags sin prefijo (`0.5.9`) | ✅ ambos |

---

## version.separators

[→ defaults.yml:56](../../scripts/defaults.yml#L56)

Controla los caracteres que separan las partes del tag generado.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`separators.version`](../../scripts/defaults.yml#L57) | `string` · default `"."` | Separa los componentes del número de versión (`0.5.9`) · implícito en todos los tests de tag building | ✅ |
| [`separators.timestamp`](../../scripts/defaults.yml#L58) | `string` · default `"."` | Separa la versión del timestamp (`0.5.9.20260407120000`) · implícito en `build_full_tag` tests | ✅ |
| [`separators.tag_append`](../../scripts/defaults.yml#L59) | `string` · default `""` | String que se appenda al final del tag, después del timestamp (ej. `-rc1`) · aplica globalmente a todos los tags mientras esté activo · getter probado, valor vacío por default | ⚠️ solo getter — valor no vacío no está probado en tag building |

---

## commit_types

[→ commit-types.yml](../../scripts/commit-types.yml)

**Bump mapping por tipo (SemVer-aligned)**

| Tipo | Bump | Emoji | Changelog group |
|------|------|-------|-----------------|
| `breaking` | `major` | 💥 | Breaking Changes |
| `feat` | `minor` | 🚀 | Features |
| `feature` | `minor` | 🚀 | Features |
| `fix` | `patch` | 🐛 | Bug Fixes |
| `hotfix` | `patch` | 🚑 | Hotfixes |
| `security` | `patch` | 🔒 | Security |
| `revert` | `patch` | ⏪ | Reverts |
| `perf` | `patch` | ⚡ | Performance |
| `refactor` | `none` | 🔨 | Refactoring |
| `docs` | `none` | 📚 | Documentation |
| `test` | `none` | 🧪 | Testing |
| `chore` | `none` | 🔧 | Chores |
| `build` | `none` | 🏗️ | Build |
| `ci` | `none` | ⚙️ | CI/CD |
| `style` | `none` | 🎨 | Style |

**Cobertura**

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| `get_commit_types_pattern` — lista pipe-separated de todos los tipos | Contiene `feat`, `fix`, `chore` | ✅ |
| `get_bump_action("feat")` | Retorna `minor` | ✅ |
| `get_bump_action("fix")` | Retorna `patch` | ✅ |
| `get_bump_action("nonexistent")` | Retorna `none` (fallback) | ✅ |
| `get_types_for_bump("major")` | Incluye `breaking` | ✅ |
| `get_types_for_bump("minor")` | Incluye `feat` | ✅ |
| `get_types_for_bump("patch")` | Incluye `fix` | ✅ |
| `get_commit_type_emoji("feat")` | Retorna `🚀` | ✅ |
| `get_commit_type_emoji("fix")` | Retorna `🐛` | ✅ |
| Tipos `feature`, `hotfix`, `security`, `revert`, `perf` — bump correcto | No probados individualmente | ❌ sin test |
| Tipos `refactor`, `build`, `ci`, `style` — bump `none` | No probados individualmente | ❌ sin test |
| `changelog_group` de cada tipo — valor correcto | No probado | ❌ sin test |

---

## commit_type_overrides

[→ defaults.yml:61](../../scripts/defaults.yml#L61)

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| Override de emoji en tipo existente (`feat` → `🆕`) | Emoji cambia, bump se mantiene (`minor`) | ✅ |
| Override de bump en tipo existente (`docs` → `none`) | Bump cambia, emoji se mantiene (`📚`) | ✅ |
| Agregar tipo nuevo (`infra`) — aparece en `get_commit_types_pattern` | Tipo disponible para validación y bump | ✅ |
| Nuevo tipo `infra` — `get_bump_action` retorna `minor` | Bump correcto para tipo agregado | ✅ |
| Nuevo tipo `infra` — `get_commit_type_emoji` retorna `🔩` | Emoji correcto para tipo agregado | ✅ |
| Nuevo tipo `infra` — aparece en `get_types_for_bump("minor")` | Incluido en lista de tipos con bump minor | ✅ |
| Tipos no sobreescritos no cambian (`fix`, `chore`) | `fix` sigue siendo `patch`, `chore` sigue siendo `none` | ✅ |
| Sin overrides — fixture `minimal` usa defaults | feat emoji `🚀`, docs bump `none`, `infra` retorna `none` | ✅ |

---

## hotfix

[→ defaults.yml:93](../../scripts/defaults.yml#L93)

Controla cómo se detecta un commit de hotfix. La detección es puramente git — no depende de APIs de plataforma (funciona en GitHub, Bitbucket, GitLab).

**`hotfix.keyword`** — `string` · `string[]` · [→ L102](../../scripts/defaults.yml#L102)

Patrones glob evaluados contra el subject del commit (o el segundo padre en merge commits). Un string simple se auto-expande a array. Defaults: `["hotfix:*", "hotfix(*", "[Hh]otfix/*"]`.

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| `hotfix: foo` → scenario=hotfix (patrón `hotfix:*`) | Match correcto | ✅ |
| `hotfix(scope): foo` → scenario=hotfix (patrón `hotfix(*`) | Match con scope | ✅ |
| `Hotfix/branch-name` → scenario=hotfix (patrón `[Hh]otfix/*`) | Match case-insensitive | ✅ |
| `hotfixed: foo` → NO match | Falso positivo bloqueado | ✅ |
| `pre-hotfix: foo` → NO match | Prefijo parcial no matchea | ✅ |
| `a hotfix: foo` → NO match | Keyword no al inicio → no matchea | ✅ |
| `fix: foo` → scenario=development_release | `fix` no es `hotfix` | ✅ |
| keyword custom `urgent` → `urgent: foo` matchea | Keyword configurable | ✅ |
| keyword custom `urgent` → `hotfix: foo` NO matchea | Aislamiento — default no aplica cuando hay custom | ✅ |
| keyword scalar `"urgent"` → auto-expand a `["urgent:*", "urgent(*"]` | Backward compat | ✅ |
| keyword custom con underscore `branch_hotfix` → matchea | Soporta underscores | ✅ |
| multi-keyword array → todos los patrones evaluados | `hotfix:*`, `hotfix(*`, `[Hh]otfix/*` | ✅ |
| merge commit — segundo padre matchea keyword | Detección via parent commit | ✅ |

> ⚠️ **Limitación conocida**: el sistema usa dos fuentes de verdad distintas. En PR context detecta hotfix por **nombre de rama** (`hotfix/fix-auth`). En branch context post-merge detecta por **subject del commit**. Si el commit dice `fix: resolve auth bug` en lugar de `hotfix: fix auth`, el hotfix no se detecta post-merge aunque la rama se llamara `hotfix/fix-auth`. Ver [ticket 048](../../temp/features/048-hotfix-detection-source-of-truth.md).

---

## branches

[→ defaults.yml:107](../../scripts/defaults.yml#L107)

Mapea los roles del pipeline a nombres de rama. **Breaking change v050**: las keys `development`, `pre_production`, `production` fueron reemplazadas por `tag_on` + `hotfix_targets`.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`branches.tag_on`](../../scripts/defaults.yml#L108) | `string` · default `"development"` | Getter retorna `"development"` por default · custom fixture `"dev"` funciona · PR a `tag_on` → `development_release` | ✅ |
| [`branches.hotfix_targets`](../../scripts/defaults.yml#L109) | `string[]` · default `["main", "pre-production"]` | Getter retorna lista correcta · custom fixture `["master", "staging"]` funciona · PR de `hotfix/` a target en lista → `hotfix` · PR de `tag_on` a target en lista → `promotion_to_main` · PR de feature a target en lista → `unknown` | ✅ |

**Scenarios de detección probados (unit)**

| Escenario | Config | Cobertura |
|-----------|--------|-----------|
| feature → tag_on → `development_release` | default + custom fixture | ✅ |
| hotfix/ → hotfix_target → `hotfix` | default (pre-production, main) + custom (staging, master) | ✅ |
| tag_on branch → hotfix_target → `promotion_to_main` | default + custom | ✅ |
| feature → hotfix_target → `unknown` | default | ✅ |
| feature → branch no configurada → `unknown` | default | ✅ |

**Scenarios de integration probados (end-to-end)**

| Escenario | Config | Cobertura |
|-----------|--------|-----------|
| `hotfix-custom-target-pr-check` | `tag_on=main`, `hotfix_targets=[main, pre-production]` · PR check only | ✅ |
| `tag-on-main-development-release` | `tag_on=main`, `hotfix_targets=[main, pre-production, uat]` · merge · tag semver | ✅ |
| `hotfix-to-main-extended-targets` | `tag_on=main`, `hotfix_targets=[main, pre-production, uat]` · merge · tag con `.1` | ✅ |

---

## version_file

[→ defaults.yml](../../scripts/defaults.yml)

Controla la actualización de archivos de versión como `package.json`, `version.yaml`, o archivos con patrones placeholder. Se ejecuta después de calcular la versión. **Breaking change v049**: estructura unificada en `groups` — los campos top-level `type`, `key`, `file`, `files`, `pattern`, `replacement`, `unmatched_files_behavior` fueron eliminados.

**Campos base**

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| `version_file.enabled` | `true` · `false` · default `false` | `false` → script sale con exit 0 sin tocar archivos · `true` → procesa grupos | ✅ ambos |
| `version_file.groups` | `Group[]` · default `[]` | Sin grupos configurados → exit 0 con warning | ✅ |

---

**Type inference por extensión**

El tipo de escritura se infiere automáticamente de la extensión del archivo — no hay campo `type` explícito.

| Extensión | Tipo inferido | Comportamiento |
|-----------|--------------|----------------|
| `.yaml` / `.yml` | yaml | `yq -i ".version = ..."` — crea el archivo si no existe |
| `.json` | json | `yq -i -o=json ".version = ..."` — crea el archivo si no existe |
| cualquier otra | pattern | Reemplaza `files[].pattern` con la versión — error fatal si `pattern` ausente |

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| `.yaml` + `tag_prefix_v: false` | `1.2.0` → `version: "1.2.0"` | ✅ |
| `.yaml` + `tag_prefix_v: true` | `v0.1.0` → escribe `0.1.0` (strip) | ✅ |
| `.yml` extension | Inferido como yaml | ✅ |
| `.json` + `tag_prefix_v: false` | `1.0.0` → `"version": "1.0.0"` | ✅ |
| `.json` + `tag_prefix_v: true` | `v0.1.0` → escribe `0.1.0` (strip) | ✅ |
| `.ts` + `pattern: "__VERSION__"` | Reemplaza placeholder, NO hace strip del prefijo | ✅ |
| `.ts` sin `pattern` | Error fatal | ✅ |
| path glob sin matches | Log warning + continúa (no fatal) | ✅ |
| `/tmp/next_version.txt` ausente | Exit != 0 | ✅ |
| path glob con matches (ej. `packages/*/version.yaml`) | Expande y actualiza todos los archivos que matchean | ❌ sin test |
| yaml — archivo no existe → se crea | Crea el archivo con `version: "X.Y.Z"` | ❌ sin test |
| json — archivo no existe → se crea | Crea el archivo con `{"version": "X.Y.Z"}` | ❌ sin test |

---

**`version_file.groups`** — estructura y getters

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| `groups` con entradas → `has_version_file_groups` retorna true | Función detecta grupos presentes | ✅ |
| `groups: []` → `has_version_file_groups` retorna false | Sin grupos | ✅ |
| `get_version_file_groups_count` → retorna cantidad correcta | 2 grupos → `2` | ✅ |
| `get_version_file_group_trigger_paths(0)` → retorna los paths | Incluye todos los patterns | ✅ |
| `get_version_file_group_trigger_paths` vacío cuando no hay trigger_paths | Grupo siempre activo | ✅ |
| `get_version_file_group_name` → default `group_N` cuando ausente | Fallback al índice | ✅ |
| `get_version_file_group_files_count(0)` → cantidad de files en grupo | 2 files → `2` | ✅ |
| `get_version_file_group_file_path(0,0)` → path del primer file | Retorna string correcto | ✅ |
| `get_version_file_group_file_path(0,1)` → path del segundo file | Retorna string correcto | ✅ |
| `get_version_file_group_file_pattern(0,0)` → pattern cuando está set | Retorna `__VERSION__` | ✅ |
| `get_version_file_group_file_pattern(0,0)` → vacío cuando ausente | Auto-infer por extensión | ✅ |
| Múltiples files en un grupo | Todos se actualizan | ✅ |

---

**trigger_paths — lógica de activación**

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| Sin `trigger_paths` → grupo siempre se actualiza | No requiere changed files | ✅ (test de getter vacío) |
| Con `trigger_paths` que matchea → grupo se actualiza | should_update_group retorna true | ❌ sin test (unit) |
| Con `trigger_paths` que NO matchea → grupo se saltea | should_update_group retorna false | ❌ sin test (unit) |
| Múltiples grupos: solo el que matchea se actualiza | El otro grupo queda sin tocar | ❌ sin test |
| `matches_glob` — match exacto | `src/main.ts` vs `src/main.ts` → match | ✅ |
| `matches_glob` — `*` no cruza directorios | `src/deep/main.ts` vs `src/*.ts` → no match | ✅ |
| `matches_glob` — `**` matchea path anidado | `packages/frontend/src/app/main.ts` vs `packages/frontend/**` → match | ✅ |
| `matches_glob` — `**` matchea un nivel | `packages/frontend/file.ts` vs `packages/frontend/**` → match | ✅ |
| `matches_glob` — `**` al inicio | `deep/nested/file.js` vs `**/*.js` → match | ✅ |
| `matches_glob` — patrón vacío | Sin match | ✅ |
| `matches_glob` — punto en patrón es literal | `packageXjson` vs `package.json` → no match | ✅ |

---

**Integration (end-to-end)**

| Escenario | Comportamiento probado | Cobertura |
|-----------|------------------------|-----------|
| PR con `version_file.groups` configurado → merge → archivo actualizado | Verifica que el archivo en el repo queda con la versión nueva | ❌ sin test |
| Monorepo: solo el grupo cuyo `trigger_paths` matchea se actualiza | El otro grupo no se toca | ❌ sin test |

---

## notifications

[→ defaults.yml:138](../../scripts/defaults.yml#L138)

Controla las notificaciones a Microsoft Teams. La sección se lee directamente con `yq` desde `scripts/reporting/notify-teams.sh` — no hay getters en `config-parser.sh`.

| Key | Type / Values | Comportamiento probado | Cobertura |
|-----|---------------|------------------------|-----------|
| [`notifications.teams.enabled`](../../scripts/defaults.yml#L140) | `true` · `false` · default `true` | `false` → script loguea "disabled" y sale sin enviar · `true` → flujo de envío | ❌ sin test |
| [`notifications.teams.on_success`](../../scripts/defaults.yml#L141) | `true` · `false` · default `false` | Controla si se notifica en ejecuciones exitosas | ❌ sin test |
| [`notifications.teams.on_failure`](../../scripts/defaults.yml#L142) | `true` · `false` · default `true` | Controla si se notifica en fallos | ❌ sin test |
