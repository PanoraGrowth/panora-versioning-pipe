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
| `suffix` | `folders` apunta a nivel intermedio (ej. `services/003-api-gateway`) para matchear subcarpetas como `routes/` | Un nivel de profundidad — no recursivo | ❌ sin test |
| `exact` | scope `api-gateway` → carpeta `api-gateway/` | El nombre de carpeta debe ser igual al scope | ✅ |
| `exact` | scope `services` → carpeta raíz `services/` | Coincidencia exacta en carpeta raíz | ✅ |
| `exact` | scope sin carpeta matching | Retorna vacío | ✅ |

---

**`changelog.per_folder.fallback`** — `"root"` · `"file_path"` · [→ L183](../../scripts/defaults.yml#L183) · [escenario: file_path](per-folder/fallback-file-path.md)

| Valor | Escenario probado | Comportamiento | Cobertura |
|-------|-------------------|----------------|-----------|
| `root` | Commit sin scope matching | Va al CHANGELOG raíz | ✅ |
| `file_path` | Commit toca archivos en una sola carpeta configurada (`api/main.go`) | Resuelve a esa carpeta | ✅ |
| `file_path` | Commit toca múltiples archivos en la misma carpeta (`web/index.html`, `web/style.css`) | Resuelve a esa carpeta | ✅ |
| `file_path` | Commit toca archivos en carpetas distintas (`api/main.go`, `web/index.html`) | Ambiguo — retorna vacío, va al root | ✅ |
| `file_path` | Commit toca archivos fuera de todas las carpetas configuradas (`docs/readme.md`) | Sin match — retorna vacío | ✅ |
| `file_path` | Commit toca archivos en carpeta configurada + archivos en root (`api/main.go`, `README.md`) | Los archivos en root se ignoran, resuelve a la carpeta | ✅ |
| `file_path` | Commit toca solo archivos en root (`README.md`) | Sin match — retorna vacío | ✅ |
| `file_path` | Archivos anidados dentro de carpeta configurada (`shared/utils/helpers.sh`) | Resuelve correctamente la carpeta padre | ✅ |

---

## version.components

[→ defaults.yml:29](../../scripts/defaults.yml#L29)

Controla qué componentes forman el número de versión y sus valores iniciales. Los componentes se renderizan en orden: `epoch.major.minor[.patch][.timestamp]`.

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
| `patch.enabled` | `true` · `false` · default `true` | `true` → incluido en el tag · bump patch → incrementa, resetea hotfix_counter a 0 | ✅ |
| `patch.initial` | `integer` · default `0` | Valor de inicio al crear el primer tag | ✅ |

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
| `timestamp.enabled` | `true` · `false` · default `true` ⚠️ pendiente cambiar a `false` ([ticket 041](../../temp/features/041-timestamp-disabled-by-default.md)) | `true` → timestamp appended al tag (`0.5.9.20260407120000`) · `false` → tag sin timestamp | ✅ ambos |
| `timestamp.format` | `string` (strftime) · default `"%Y%m%d%H%M%S"` | Formato aplicado al generar el timestamp · getter probado | ⚠️ solo getter — formato alternativo no probado en output |
| `timestamp.timezone` | `string` · default `"UTC"` | TZ aplicada al generar el timestamp · `build_full_tag` respeta el timezone | ✅ |

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

[→ defaults.yml:61](../../scripts/defaults.yml#L61)

Define los tipos de commit válidos, el bump que producen, el emoji y el grupo en el changelog. El sistema incluye 15 tipos por defecto. Los tipos se usan en validación (`require_commit_types`), en el cálculo de versión, y en la generación de changelog.

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

[→ defaults.yml:152](../../scripts/defaults.yml#L152)

Permite parchear o extender `commit_types` sin redefinir el array completo. Solo se especifican los campos a cambiar — el resto hereda los defaults. Soporta modificar tipos existentes y agregar tipos nuevos.

```yaml
# Ejemplo en .versioning.yml
commit_type_overrides:
  docs:
    bump: "patch"          # cambia solo el bump, emoji y changelog_group heredan
  infra:
    bump: "minor"          # tipo nuevo
    emoji: "🔩"
    changelog_group: "Infrastructure"
```

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
