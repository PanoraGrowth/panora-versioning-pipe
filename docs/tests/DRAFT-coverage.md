# Cobertura de Tests — Draft (revisión de formato)

> Draft que cubre las secciones: `commits`, `tickets`, `validation`, `changelog`, `changelog.per_folder`.
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
