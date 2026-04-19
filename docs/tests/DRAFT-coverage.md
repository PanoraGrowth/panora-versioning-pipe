# Test Coverage — panora-versioning-pipe

Cada sección mapea directamente a [`scripts/defaults.yml`](../../scripts/defaults.yml). Para cada key de configuración se listan los escenarios probados y su estado de cobertura.

**Leyenda:** ✅ cubierto · ⚠️ parcial · ❌ sin test

---

## commits

[→ defaults.yml:9](../../scripts/defaults.yml#L9)

Controla cómo se estructuran e interpretan los mensajes de commit.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`commits.format`](../../scripts/defaults.yml#L10) | `"ticket"` | `"conventional"` — acepta `tipo(scope): mensaje`, rechaza formato incorrecto | ✅ |
| | | `"ticket"` — acepta `AM-1234 - tipo: mensaje`, rechaza formato incorrecto | ✅ |

---

## tickets

[→ defaults.yml:12](../../scripts/defaults.yml#L12)

Aplica cuando `commits.format: "ticket"`. Controla la validación de prefijos y el linkeo en changelogs.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`tickets.prefixes`](../../scripts/defaults.yml#L13) | `[]` | Lista vacía — cualquier prefijo es aceptado | ✅ |
| | | Con valores (`["PROJ", "TEAM"]`) — solo esos prefijos pasan validación | ✅ |
| [`tickets.required`](../../scripts/defaults.yml#L14) | `false` | `false` — commit sin ticket es aceptado | ✅ |
| | | `true` — commit sin ticket es rechazado | ✅ |
| [`tickets.url`](../../scripts/defaults.yml#L15) | `""` | URL configurada — el link aparece en el changelog con el ticket como texto | ✅ |

---

## validation

[→ defaults.yml:17](../../scripts/defaults.yml#L17)

Controla qué commits son aceptados y cuáles se ignoran durante el cálculo de versión.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`validation.require_ticket_prefix`](../../scripts/defaults.yml#L18) | `false` | `false` — commit sin prefijo de ticket es aceptado | ✅ |
| | | `true` — commit sin prefijo es rechazado | ✅ |
| [`validation.require_commit_types`](../../scripts/defaults.yml#L19) | `true` | `false` — validación de tipo desactivada, cualquier commit pasa | ✅ |
| | | `true` + `changelog.mode: "last_commit"` — solo el último commit debe tener tipo válido | ✅ |
| | | `true` + `changelog.mode: "full"` — todos los commits deben tener tipo válido | ✅ |
| [`validation.ignore_patterns`](../../scripts/defaults.yml#L20) | ver defaults | Commits que matchean los patrones son ignorados en la validación y el cálculo de versión | ✅ |
| | | Merge commits (`^Merge`), reverts (`^Revert`), `fixup!`, `squash!` ignorados | ✅ |
| | | `chore(release)` y `chore(hotfix)` ignorados | ✅ |
| [`validation.hotfix_title_required`](../../scripts/defaults.yml#L20) | `"error"` | `"error"` (default) — bloquea el merge si el branch es hotfix pero el PR title no tiene el hotfix keyword | ✅ unit `pr-title.bats` |
| | | `"warn"` — emite warning pero no bloquea el merge | ✅ unit `pr-title.bats` |
| | | Sin `VERSIONING_BRANCH` — chequeo se saltea silenciosamente | ✅ unit `pr-title.bats` |
| | | SCENARIO distinto de `hotfix` — chequeo no aplica | ✅ unit `pr-title.bats` |
| [`validation.allow_version_regression`](../../scripts/defaults.yml#L20) | `false` | `false` (default) — regresión detectada bloquea el pipeline (exit 1) antes de emitir tag | ✅ unit `guardrails.bats` |
| | | `true` — regresión detectada degrada a warning (exit 2, `result=warned`), pipeline continúa | ✅ unit `guardrails.bats` |

**PR title validation** (`VERSIONING_PR_TITLE`) — feature 046

En squash merge, el PR title se convierte en el commit subject que determina el bump. Si `require_commit_types: true`, el pipe valida que el PR title siga el mismo formato que los commits.

| Escenario | Cobertura |
|-----------|-----------|
| PR title conventional válido (`feat: ...`) — pasa | ✅ unit `pr-title.bats` |
| PR title no-conventional (`Development (#17)`) — falla | ✅ unit `pr-title.bats` + integration `pr-title-invalid-squash` |
| PR title ticket-prefix válido (`AM-123 - feat: ...`) — pasa | ✅ unit `pr-title.bats` |
| PR title ticket-prefix inválido (`AM-123 - Development`) — falla | ✅ unit `pr-title.bats` |
| `VERSIONING_PR_TITLE` vacío — validación se saltea silenciosamente (Bitbucket, generic CI) | ✅ unit `pr-title.bats` |
| `require_commit_types: false` — ni commits ni PR title se validan | ✅ unit `pr-title.bats` + integration `pr-title-validation-disabled` |
| `mode: last_commit` — PR title se valida igual que en `mode: full` | ✅ unit `pr-title.bats` |
| PR title con hotfix keyword convencional (`hotfix: fix auth`) — pasa | ✅ unit `pr-title.bats` |
| PR title con hotfix keyword glob (`Hotfix/urgent security patch` matchea `[Hh]otfix/*`) — pasa | ✅ unit `pr-title.bats` (eval-based glob) + integration `hotfix-uppercase-branch-prefix` |
| PR title no-conventional + merge commit style — PR pipeline falla igual | ✅ integration `pr-title-invalid-merge-commit` |
| PR title conventional + squash merge — PR pipeline pasa, tag creado | ✅ integration `pr-title-valid-squash` (sandbox-21) |

**Squash-merge hotfix gap guard** (`VERSIONING_BRANCH` + `SCENARIO=hotfix`) — feature 051

En squash merge, si el branch es `hotfix/fix-auth` pero el PR title es `fix: resolve auth`, post-merge el pipe ve solo `fix: resolve auth` y clasifica como `development_release` — falla silenciosa. Este guardrail actúa en PR context para prevenir el problema antes del merge.

| Escenario | Cobertura |
|-----------|-----------|
| Branch `hotfix/*`, PR title con hotfix keyword (`hotfix: fix auth`) — sin error ni warning | ✅ unit `pr-title.bats` |
| Branch `hotfix/*`, PR title sin hotfix keyword (`fix: resolve auth`) — error (default) | ✅ unit `pr-title.bats` |
| Branch `hotfix/*`, PR title sin hotfix keyword (`fix: resolve auth`) — error (default) | ✅ unit `pr-title.bats` · ✅ integration `hotfix-squash-gap-blocked` |
| Branch `hotfix/*`, PR title sin hotfix keyword + `hotfix_title_required: warn` — warning, no bloquea | ✅ unit `pr-title.bats` · ✅ integration `hotfix-squash-gap-warn` |
| Branch `hotfix/*`, PR title con hotfix keyword + squash merge → tag con hotfix_counter | ✅ unit `pr-title.bats` · ✅ integration `hotfix-squash-gap-keyword-passes` (sandbox-24) |
| Branch `hotfix/*`, PR title con glob keyword (`Hotfix/urgent-fix` matchea `[Hh]otfix/*`) — pasa | ✅ unit `pr-title.bats` |
| Branch `hotfix/*`, PR title convencional con scope (`fix(auth): ...`) — error (no tiene keyword) | ✅ unit `pr-title.bats` |
| `VERSIONING_BRANCH` vacío — chequeo se saltea (Bitbucket, generic CI sin branch var) | ✅ unit `pr-title.bats` |
| SCENARIO=`development_release` — chequeo no aplica, aunque branch sea hotfix | ✅ unit `pr-title.bats` |

**Nota de implementación:** los hotfix keyword patterns como `[Hh]otfix/*` son globs con bracket expressions. Cuando el pattern viene de una variable shell, el `case` nativo no expande los brackets correctamente — se usa `eval` para forzar la expansión (mismo comportamiento que `detect-scenario.sh`).

**Gap pendiente:** Bitbucket no expone el PR title como variable nativa (`BITBUCKET_PR_TITLE` no existe). La validación se saltea silenciosamente. Cuando Bitbucket lo agregue, solo hay que mapearlo en `pipe.sh`. Ver ticket 022.

**Runtime guardrail: version regression** (`assert_no_version_regression`) — feature 060

Capa de enforcement que corre en `branch-pipeline.sh` entre `calculate-version.sh` y la emisión del tag. Valida que el tag calculado sea consistente con el `bump_type` declarado relativo al `latest_tag` del namespace activo. Bloquea antes de cualquier side-effect (tag, CHANGELOG, push).

| Escenario | Cobertura |
|-----------|-----------|
| Cold start (no latest tag) — pass con `reason=cold_start` | ✅ unit `guardrails.bats` |
| `bump=major` y major incrementa (v5.2.0 → v6.1.0) — pass | ✅ unit `guardrails.bats` |
| `bump=major` y major NO incrementa (v5.2.0 → v5.3.0) — block `violation=major_not_incremented` | ✅ unit `guardrails.bats` |
| `bump=major` y epoch regressed — block `violation=epoch_regressed` | ✅ unit `guardrails.bats` |
| `bump=patch` y patch incrementa (v5.2.0 → v5.3.0) — pass | ✅ unit `guardrails.bats` |
| `bump=patch` y patch NO incrementa (v5.2.0 → v5.2.0) — block `violation=patch_not_incremented` | ✅ unit `guardrails.bats` |
| `bump=patch` y major regressed — block `violation=major_regressed` | ✅ unit `guardrails.bats` |
| `bump=hotfix` mismo base, counter incrementa (v0.5.9 → v0.5.9.1) — pass | ✅ unit `guardrails.bats` |
| `bump=hotfix` mismo base, counter incrementa otra vez (v0.5.9.1 → v0.5.9.2) — pass | ✅ unit `guardrails.bats` |
| `bump=hotfix` mismo base, counter NO incrementa — block `violation=hotfix_counter_not_incremented` | ✅ unit `guardrails.bats` |
| `bump=hotfix` base cambió (major up, counter reset a 1, v0.5.9.3 → v0.6.0.1) — pass (tuple comparison) | ✅ unit `guardrails.bats` |
| `bump=hotfix` base cambió pero major regressed (v0.6.0.2 → v0.5.9.1) — block `violation=major_regressed` | ✅ unit `guardrails.bats` |
| `allow_version_regression: true` — regresión degradada a warning, exit 2, `result=warned` | ✅ unit `guardrails.bats` |
| Log estructurado emitido siempre (pass) — `GUARDRAIL name=no_version_regression result=pass ...` | ✅ unit `guardrails.bats` |
| Log estructurado emitido siempre (block) — `GUARDRAIL name=no_version_regression result=blocked next=v5.3.0 latest=v5.2.0 ...` | ✅ unit `guardrails.bats` |
| End-to-end flujo normal (el guardrail no rompe ningún escenario existente) — 37/37 integration scenarios pass con el guardrail instalado | ✅ integration (smoke test implícito de los 37 scenarios) |

**Gap pendiente (integration):** No hay un integration scenario que dispare intencionalmente un `result=blocked` end-to-end. Las violations son extremadamente difíciles de reproducir sin introducir un bug artificial en el pipe — después de los fixes de tickets 055, 058 y 059, el pipe no calcula versiones inconsistentes con configuración válida. El guardrail se validó en producción cuando el propio pipe se versionó a sí mismo (run `24618338339`, log visible `GUARDRAIL name=no_version_regression result=pass bump=patch next=v0.11.18 latest=v0.11.17`). El escape hatch (`allow_version_regression: true`) sí podría probarse end-to-end si se logra reproducir una regresión controlada — queda como trabajo futuro.

**Diseño:** el guardrail corre SOLO en `branch-pipeline.sh` (post-merge). El PR pipeline no calcula versiones, así que no hay nada que validar. Ver `docs/architecture/README.md#safety-guardrails` y `docs/troubleshooting.md#tag-on-merge-failed-with-version-regression-blocked-guardrail` para el flujo de recovery.

---

## changelog

[→ defaults.yml:72](../../scripts/defaults.yml#L72)

Controla cómo se genera y escribe el archivo CHANGELOG.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`changelog.file`](../../scripts/defaults.yml#L73) | `"CHANGELOG.md"` | Nombre de archivo respetado al escribir | ✅ |
| [`changelog.title`](../../scripts/defaults.yml#L74) | `"Changelog"` | Título correcto en el header del archivo | ✅ |
| [`changelog.mode`](../../scripts/defaults.yml#L75) | `"last_commit"` | `"last_commit"` — solo el último commit aparece en el entry | ✅ |
| | | `"full"` — todos los commits desde el último tag aparecen | ✅ |
| | | **Bump strategy acoplada al mode** | |
| | | `"last_commit"` — el último commit del rango determina el bump (ej: `[fix, feat, fix]` → patch porque el último es `fix:`) | ✅ unit `bump-strategy.bats` |
| | | `"full"` — el commit de mayor jerarquía gana (`[fix, feat, fix]` → minor porque `feat:` > `fix:`) | ✅ unit `bump-strategy.bats` · ✅ integration `multi-commit-highest-wins` (sandbox-25) |
| | | `"full"` con un solo commit — resultado idéntico a `"last_commit"` | ✅ unit `bump-strategy.bats` |
| | | `"full"` con commits solo `bump: none` — sin versión producida | ✅ unit `bump-strategy.bats` |
| [`changelog.use_emojis`](../../scripts/defaults.yml#L76) | `false` | `false` — output sin emojis | ✅ |
| | | `true` — output incluye emoji por tipo | ✅ |
| [`changelog.include_commit_link`](../../scripts/defaults.yml#L77) | `true` | Valor leído correctamente | ✅ |
| [`changelog.include_ticket_link`](../../scripts/defaults.yml#L78) | `true` | Valor leído correctamente | ✅ |
| [`changelog.include_author`](../../scripts/defaults.yml#L79) | `true` | Valor leído correctamente | ✅ |
| [`changelog.commit_url`](../../scripts/defaults.yml#L80) | `""` | Vacío — no aparece link de commit en output | ✅ |
| | | URL configurada — link al commit aparece en output | ✅ |
| [`changelog.ticket_link_label`](../../scripts/defaults.yml#L81) | `"View ticket"` | Label correcto en output | ✅ |

---

### changelog.per_folder

[→ defaults.yml:86](../../scripts/defaults.yml#L86)

Habilita changelogs independientes por carpeta en monorepos. Requiere `commits.format: "conventional"`. El routing es exclusivo — cada commit va a una sola carpeta o al root, nunca a ambos.

**`changelog.per_folder.enabled`** — default `false`

| Valor | Escenario | Cobertura |
|-------|-----------|-----------|
| `true` | Commits con scope son dirigidos a su carpeta | ✅ |
| `false` | Todo va al CHANGELOG raíz | ✅ |

---

**`changelog.per_folder.folders`** — `string[]` · default `[]` · [→ L88](../../scripts/defaults.yml#L88)

| Escenario | Cobertura |
|-----------|-----------|
| Múltiples carpetas raíz (`services`, `infrastructure`) — la búsqueda se extiende a todas | ✅ |
| Carpeta raíz inexistente — ignorada, no rompe la ejecución | ✅ |
| Glob pattern (`shared/*`) — expande a subdirectorios directos de `shared/` | ✅ |
| Glob pattern con directorio padre inexistente — no rompe la ejecución | ✅ |

---

**`changelog.per_folder.folder_pattern`** — `string` (regex) · default `""` · [→ L89](../../scripts/defaults.yml#L89)

| Escenario | Cobertura |
|-----------|-----------|
| Patrón `^[0-9]{3}-` — solo subcarpetas con prefijo numérico son candidatas | ✅ |
| Carpeta que matchea el scope pero NO el patrón — ignorada como destino | ✅ |
| Patrón vacío `""` — todas las subcarpetas son candidatas | ✅ |

---

**`changelog.per_folder.scope_matching`** — `"suffix"` · `"exact"` · [→ L90](../../scripts/defaults.yml#L90) · [escenario: suffix](per-folder/suffix-matching.md) · [escenario: exact](per-folder/exact-matching.md)

| Valor | Escenario | Cobertura |
|-------|-----------|-----------|
| `"suffix"` | `feat(cluster-ecs)` → resuelve a `001-cluster-ecs/` (termina con el scope) | ✅ |
| `"suffix"` | Scope con múltiples subcarpetas candidatas — resuelve la correcta | ✅ |
| `"suffix"` | Scope sin match en ninguna subcarpeta — sin resolución | ✅ |
| `"suffix"` | Scope vacío — sin resolución | ✅ |
| `"suffix"` | Subcarpeta a 2 niveles de profundidad (`services/003-api-gateway/001-routes/`) — encontrada con depth=2 | ✅ |
| `"suffix"` | Subcarpeta más profunda que `scope_matching_depth` — no matchea | ✅ |
| `"exact"` | `feat(api-gateway)` → resuelve exactamente a `api-gateway/` | ✅ |
| `"exact"` | Scope que coincide con una carpeta raíz configurada | ✅ |
| `"exact"` | Scope sin carpeta con nombre exacto — sin resolución | ✅ |

---

**`changelog.per_folder.scope_matching_depth`** — `integer` · default `2` · solo aplica a `scope_matching: "suffix"` · [→ L91](../../scripts/defaults.yml#L91)

| Escenario | Cobertura |
|-----------|-----------|
| Default `2` — encuentra subcarpeta a nivel 2 (`services/003-api-gateway/001-routes/`) | ✅ |
| Default `2` — no llega a nivel 3 (`services/001/002/003-routes/`) | ✅ |

---

**`changelog.per_folder.fallback`** — `"root"` · `"file_path"` · [→ L92](../../scripts/defaults.yml#L92) · [escenario: file_path](per-folder/fallback-file-path.md)

| Valor | Escenario | Cobertura |
|-------|-----------|-----------|
| `"root"` | Commit sin scope matching — va al CHANGELOG raíz | ✅ |
| `"file_path"` | Commit toca archivos en una sola carpeta configurada — resuelve a esa carpeta | ✅ |
| `"file_path"` | Commit toca múltiples archivos en la misma carpeta — resuelve a esa carpeta | ✅ |
| `"file_path"` | Commit toca archivos en carpetas distintas — escribe en todas las carpetas matcheadas | ✅ |
| `"file_path"` | Commit toca archivos en 3 carpetas distintas — escribe en las 3 | ✅ |
| `"file_path"` | Archivos fuera de todas las carpetas configuradas — sin match, va al root | ✅ |
| `"file_path"` | Archivos en carpeta configurada + archivos en root — los del root se ignoran | ✅ |
| `"file_path"` | Solo archivos en root — sin match, va al root | ✅ |
| `"file_path"` | Archivos anidados dentro de carpeta configurada (`shared/utils/helpers.sh`) — resuelve a la carpeta padre | ✅ |
| `"file_path"` | E2E: PR → merge → CHANGELOG escrito en carpeta correcta (single folder) | ✅ sandbox-17 (`per-folder-fallback-file-path`) |
| `"file_path"` | E2E: PR → merge → CHANGELOG escrito en múltiples carpetas (multi-folder) | ✅ sandbox-18 (`per-folder-multi-folder-write`) |

---

## version.components

[→ defaults.yml:29](../../scripts/defaults.yml#L29)

Controla qué componentes forman el número de versión. Los componentes se renderizan en orden: `epoch.major.patch[.hotfix_counter][.timestamp]`.

**`version.components.epoch`** — [→ L30](../../scripts/defaults.yml#L30)

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| `epoch.enabled` | `false` | `true` — el epoch aparece como primer componente del tag (`1.0.0`) | ✅ |
| | | `false` — el tag empieza en major (`0.5.9`) | ✅ |
| `epoch.initial` | `0` | Valor de inicio cuando el componente se habilita | ✅ |

---

**`version.components.major`** — [→ L33](../../scripts/defaults.yml#L33)

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| `major.enabled` | `true` | `true` — incluido en el tag · un commit `breaking` lo incrementa y resetea patch y hotfix_counter a 0 | ✅ |
| `major.initial` | `0` | Valor de inicio al crear el primer tag | ✅ |

---

**`version.components.patch`** — [→ L36](../../scripts/defaults.yml#L36)

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| `patch.enabled` | `true` | `true` — commits `fix`, `security`, `revert`, `perf` lo incrementan y resetean hotfix_counter a 0 | ✅ |
| | | `false` — patch no aparece en el tag · commits que normalmente bumparían patch son no-op | ✅ |
| `patch.initial` | `0` | `patch=0` siempre se renderiza en el tag (`0.12.0`, no `0.12`) | ✅ |

---

**`version.components.hotfix_counter`** — [→ L46](../../scripts/defaults.yml#L46)

Componente del flujo hotfix. Cuando está habilitado, un commit `hotfix` incrementa este contador. El `.0` se omite — el tag se renderiza como `v0.5.9.1` en lugar de `v0.5.9.0`.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| `hotfix_counter.enabled` | `true` | `true` — un hotfix bumpa el contador (`0.5.9` → `0.5.9.1`) | ✅ |
| | | `false` — commits hotfix son no-op (sin tag, se loguea el motivo) | ✅ |
| | | `patch=0` + `hotfix_counter > 0` — renderizado correcto (`0.12.0.1`) | ✅ |
| `hotfix_counter.initial` | `0` | Valor de inicio · se resetea a 0 cuando se bumpa major o patch | ✅ |

---

**`version.components.timestamp`** — [→ L49](../../scripts/defaults.yml#L49)

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| `timestamp.enabled` | `false` | `true` — timestamp appended al tag (`0.5.9.20260407120000`) | ✅ |
| | | `false` — tag sin timestamp | ✅ |
| `timestamp.format` | `"%Y%m%d%H%M%S"` | Formato por default — 14 dígitos en el tag | ✅ |
| | | Formato alternativo (`%Y-%m-%d`) — aplicado correctamente | ✅ |
| `timestamp.timezone` | `"UTC"` | `UTC` — timezone aplicada al generar el timestamp | ✅ |
| | | `America/Buenos_Aires` — timestamp generado correctamente | ✅ |
| | | `Europe/Madrid` — timestamp generado correctamente | ✅ |

---

## version.tag_prefix_v

[→ defaults.yml:54](../../scripts/defaults.yml#L54)

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`version.tag_prefix_v`](../../scripts/defaults.yml#L54) | `false` | `true` — tags con prefijo `v` (`v0.5.9`) · version files escritos sin `v` para compatibilidad con npm | ✅ |
| | | `false` — tags sin prefijo (`0.5.9`) | ✅ |

---

## version.separators

[→ defaults.yml:56](../../scripts/defaults.yml#L56)

Controla los caracteres que separan las partes del tag generado.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`separators.version`](../../scripts/defaults.yml#L57) | `"."` | Separa los componentes del número de versión — implícito en todos los tests de tag building | ✅ |
| [`separators.timestamp`](../../scripts/defaults.yml#L58) | `"."` | Separa la versión del timestamp (`0.5.9.20260407120000`) — implícito en tests de tag con timestamp | ✅ |
| [`separators.tag_append`](../../scripts/defaults.yml#L59) | `""` | Vacío por default — no se agrega nada al final del tag | ✅ |
| | | Valor no vacío (ej. `-rc1`) — appended al final del tag después del timestamp | ✅ |

---

## commit_types

[→ scripts/commit-types.yml](../../scripts/commit-types.yml)

Catálogo de tipos de commit. Cada tipo define el bump de versión que produce, su emoji, y el grupo en el changelog.

**Tipos core (siempre disponibles)**

| Tipo | Bump | Emoji | Grupo en changelog | Cobertura |
|------|------|-------|--------------------|-----------|
| `breaking` | `major` | 💥 | Breaking Changes | ✅ bump correcto |
| `feat` | `minor` | 🚀 | Features | ✅ bump correcto |
| `feature` | `minor` | 🚀 | Features | ✅ bump correcto |
| `fix` | `patch` | 🐛 | Bug Fixes | ✅ bump correcto |
| `hotfix` | `patch` | 🚑 | Hotfixes | ✅ bump correcto |
| `security` | `patch` | 🔒 | Security | ✅ bump correcto |
| `revert` | `patch` | ⏪ | Reverts | ✅ bump correcto |
| `perf` | `patch` | ⚡ | Performance | ✅ bump correcto |
| `refactor` | `none` | 🔨 | Refactoring | ✅ sin bump (estado vacío) |
| `docs` | `none` | 📚 | Documentation | ✅ sin bump (estado vacío) |
| `test` | `none` | 🧪 | Testing | ✅ sin bump (estado vacío) |
| `chore` | `none` | 🔧 | Chores | ✅ sin bump (estado vacío) |
| `build` | `none` | 🏗️ | Build | ✅ sin bump (estado vacío) |
| `ci` | `none` | ⚙️ | CI/CD | ✅ sin bump (estado vacío) |
| `style` | `none` | 🎨 | Style | ✅ sin bump (estado vacío) |

**Tipos extendidos (disponibles en el catálogo, se activan vía `commit_type_overrides`)**

| Tipo | Bump | Emoji | Grupo en changelog | Cobertura |
|------|------|-------|--------------------|-----------|
| `infra` | `patch` | 🔩 | Infrastructure | ✅ bump correcto |
| `deploy` | `patch` | 🚢 | Deployments | ✅ bump correcto |
| `config` | `none` | ⚙️ | Configuration | ✅ sin bump (estado vacío) |
| `deps` | `patch` | 📦 | Dependencies | ✅ bump correcto |
| `migration` | `patch` | 🗄️ | Migrations | ✅ bump correcto |
| `rollback` | `patch` | ⏮️ | Rollbacks | ✅ bump correcto |
| `data` | `patch` | 💾 | Data Changes | ✅ bump correcto |
| `compliance` | `none` | 📋 | Compliance | ✅ sin bump (estado vacío) |
| `audit` | `none` | 🔍 | Audit | ✅ sin bump (estado vacío) |
| `regulatory` | `patch` | ⚖️ | Regulatory | ✅ bump correcto |
| `iac` | `patch` | 🏗️ | Infrastructure as Code | ✅ bump correcto |
| `release` | `none` | 🏷️ | Releases | ✅ sin bump (estado vacío) |
| `wip` | `none` | 🚧 | Work in Progress | ✅ sin bump (estado vacío) |
| `experiment` | `none` | 🧪 | Experiments | ✅ sin bump (estado vacío) |

---

## commit_type_overrides

[→ defaults.yml:61](../../scripts/defaults.yml#L61)

Permite parchear o extender el catálogo de tipos sin redefinirlo completo. Solo se especifican los campos que cambian.

| Escenario | Cobertura |
|-----------|-----------|
| Override de emoji en tipo existente (`feat` → emoji distinto) — el bump original se mantiene | ✅ |
| Override de bump en tipo existente (`docs` → bump distinto) — el emoji original se mantiene | ✅ |
| Agregar tipo nuevo (`infra`) — disponible para validación, bump, y emoji | ✅ |
| Tipos no sobreescritos no cambian (`fix`, `chore`) | ✅ |
| Sin overrides — el catálogo base aplica sin modificaciones | ✅ |

---

## hotfix

[→ defaults.yml:94](../../scripts/defaults.yml#L94)

Controla cómo se detecta un commit de hotfix. La detección es puramente git — no depende de APIs de plataforma (funciona en GitHub, Bitbucket, GitLab, o cualquier host git).

**`hotfix.keyword`** — `string` · `string[]` · [→ L103](../../scripts/defaults.yml#L103)

Patrones glob evaluados contra el subject del commit (o el segundo padre en merge commits). Defaults: `["hotfix:*", "hotfix(*", "[Hh]otfix/*"]`.

| Escenario | Cobertura |
|-----------|-----------|
| `hotfix: descripción` — matchea patrón `hotfix:*` | ✅ |
| `hotfix(scope): descripción` — matchea patrón `hotfix(*` | ✅ |
| `Hotfix/branch-name` — matchea patrón `[Hh]otfix/*` (case-insensitive) | ✅ |
| `hotfixed: foo` — NO matchea (falso positivo bloqueado) | ✅ |
| `pre-hotfix: foo` — NO matchea (prefijo parcial no alcanza) | ✅ |
| `a hotfix: foo` — NO matchea (keyword no al inicio del subject) | ✅ |
| `fix: foo` — NO matchea, produce bump de patch normal | ✅ |
| Keyword custom (`urgent`) — `urgent: foo` matchea, `hotfix: foo` no (aislamiento) | ✅ |
| Keyword como string simple (`"urgent"`) — auto-expandido a array de patrones | ✅ |
| Keyword con underscore — soportado | ✅ |
| Multi-keyword — todos los patrones se evalúan | ✅ |
| Merge commit — detección via subject del segundo padre | ✅ |

> **Squash merge y detección de hotfix**: en squash merge, el branch name se pierde post-merge. Si el PR title no lleva el hotfix keyword, `detect-scenario.sh` clasifica el commit como `development_release`. El guardrail `validation.hotfix_title_required` (default `"error"`) previene esto bloqueando el merge en PR context cuando el branch es hotfix pero el título no tiene el keyword. Ver [ticket 051](../../temp/features/051-hotfix-squash-merge-gap.md).

---

## branches

[→ defaults.yml:108](../../scripts/defaults.yml#L108)

Mapea los roles del pipeline a nombres de rama.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`branches.tag_on`](../../scripts/defaults.yml#L109) | `"development"` | Default — PR a `development` produce `development_release` | ✅ |
| | | Custom (`"dev"`) — PR a `dev` produce `development_release` | ✅ |
| [`branches.hotfix_targets`](../../scripts/defaults.yml#L110) | `["main", "pre-production"]` | Default — PR de `hotfix/` a `main` o `pre-production` produce `hotfix` | ✅ |
| | | Custom (`["master", "staging"]`) — PR de `hotfix/` a esas ramas produce `hotfix` | ✅ |
| | | PR de `tag_on` a un `hotfix_target` produce `promotion_to_main` | ✅ |
| | | PR de feature a un `hotfix_target` produce `unknown` | ✅ |
| | | PR a rama no configurada produce `unknown` | ✅ |

**Scenarios de integración (end-to-end)**

| Escenario | Cobertura |
|-----------|-----------|
| PR check en rama con `tag_on=main`, `hotfix_targets=[main, pre-production]` | ✅ |
| Merge a `tag_on=main` — produce tag semver | ✅ |
| Merge de `hotfix/` a `hotfix_targets` extendido — produce tag con `.1` | ✅ |

---

## version_file

[→ defaults.yml:114](../../scripts/defaults.yml#L114)

Controla la actualización de archivos de versión (`package.json`, `version.yaml`, archivos con placeholder). Se ejecuta después de calcular la versión.

**Campos base**

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| `version_file.enabled` | `false` | `false` — sale sin tocar archivos | ✅ |
| | | `true` — procesa los grupos configurados | ✅ |
| `version_file.groups` | `[]` | Sin grupos configurados — sale con warning | ✅ |

---

**Tipo de escritura — inferido por extensión**

No hay campo `type` explícito. El comportamiento se determina por la extensión del archivo.

| Extensión | Comportamiento | Cobertura |
|-----------|---------------|-----------|
| `.yaml` / `.yml` | Actualiza el key `version` con yq · crea el archivo si no existe (path sin glob chars) | ✅ actualización · ✅ creación (fix PR #94) |
| `.json` | Actualiza el key `version` con yq (JSON output) · crea el archivo si no existe (path sin glob chars) | ✅ actualización · ✅ creación (fix PR #94) |
| Cualquier otra | Reemplaza el `pattern` configurado con la versión · error fatal si `pattern` no está configurado | ✅ reemplazo · ✅ error fatal |
| `.yaml` + `tag_prefix_v: true` | Escribe la versión sin el prefijo `v` (`v0.1.0` → `0.1.0` en el archivo) | ✅ |
| `.json` + `tag_prefix_v: true` | Escribe la versión sin el prefijo `v` | ✅ |
| Tipo pattern + `tag_prefix_v: true` | NO hace strip del prefijo — escribe el tag tal cual | ✅ |
| Path glob (ej. `packages/*/version.yaml`) | Expande y actualiza todos los archivos que matchean | ✅ |
| Path glob sin matches | Log warning + continúa (no fatal) | ✅ |

---

**Groups — activación y routing**

| Escenario | Cobertura |
|-----------|-----------|
| Grupo sin `trigger_paths` — siempre se actualiza | ✅ |
| Grupo con `trigger_paths` que matchea los archivos cambiados — se actualiza | ✅ |
| Grupo con `trigger_paths` que NO matchea — se saltea | ✅ |
| Múltiples grupos — solo el que matchea `trigger_paths` se actualiza, el otro queda intacto | ✅ |
| Múltiples files en un grupo — todos se actualizan | ✅ |

**Glob matching en `trigger_paths`**

| Escenario | Cobertura |
|-----------|-----------|
| Match exacto (`src/main.ts` vs `src/main.ts`) | ✅ |
| `*` no cruza directorios (`src/deep/main.ts` vs `src/*.ts` → no match) | ✅ |
| `**` matchea path anidado (`packages/frontend/src/app/main.ts` vs `packages/frontend/**`) | ✅ |
| `**` matchea un nivel (`packages/frontend/file.ts` vs `packages/frontend/**`) | ✅ |
| `**` al inicio del patrón (`deep/nested/file.js` vs `**/*.js`) | ✅ |
| Patrón vacío — sin match | ✅ |
| Punto en patrón es literal (`packageXjson` vs `package.json` → no match) | ✅ |

**Integración (end-to-end)**

| Escenario | Cobertura |
|-----------|-----------|
| PR con `version_file.groups` → merge → archivo actualizado en el repo | ✅ sandbox-19 (`version-file-groups-trigger-match`) |
| Monorepo: solo el grupo cuyo `trigger_paths` matchea se actualiza | ✅ sandbox-19 + sandbox-20 (`version-file-groups-trigger-no-match`) |

> **Nota (2026-04-18)**: los escenarios sandbox-19 y sandbox-20 estaban marcados ✅ desde PR #97 pero la cobertura era ilusoria — pasaban por un branch `development` residual en el test repo (ver ticket 058). El bug fue corregido en PR #111 (`fix(version_file): drop development default in get_changed_files`). Ambos escenarios fueron re-validados end-to-end post-fix y confirmados genuinos. Ver `temp/audits/trigger-paths-audit-2026-04-18.md`.

---

## notifications

[→ defaults.yml:134](../../scripts/defaults.yml#L134)

Controla las notificaciones a Microsoft Teams.

| Key | Default | Escenario | Cobertura |
|-----|---------|-----------|-----------|
| [`notifications.teams.enabled`](../../scripts/defaults.yml#L136) | `true` | `enabled` con trigger inválido — exit no-zero | ✅ |
| [`notifications.teams.on_success`](../../scripts/defaults.yml#L137) | `false` | `false` (default) + trigger "success" — sale 0 con mensaje "disabled" | ✅ |
| | | `true` + trigger "success" + sin webhook — sale 0 con skip warning | ✅ |
| [`notifications.teams.on_failure`](../../scripts/defaults.yml#L138) | `true` | `true` (default) + trigger "failure" + sin webhook — sale 0 con skip warning | ✅ |
| | | **Nota**: enabled=false y on_failure=false no son testeables en unit (REPO_ROOT=/pipe es read-only en el container de test — no se puede inyectar .versioning.yml custom) | ⚠️ |
