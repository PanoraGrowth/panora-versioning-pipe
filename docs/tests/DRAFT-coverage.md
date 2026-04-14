# Cobertura de Tests — Draft (revisión de formato)

> Draft que cubre las primeras tres secciones de configuración (`commits`, `tickets`, `validation`).
> El objetivo es encontrar el formato antes de escribir el documento completo.

---

Cada sección mapea directamente a [`scripts/defaults.yml`](../../scripts/defaults.yml). Cada key linkea a su definición. La columna de cobertura indica si el comportamiento está validado por tests unitarios.

Leyenda: ✅ cubierto · ⚠️ parcial · ❌ sin test

---

## commits

[→ defaults.yml:9](../../scripts/defaults.yml#L9)

Controla cómo se estructuran e interpretan los mensajes de commit.

| Key | Default | Comportamiento probado | Cobertura |
|-----|---------|------------------------|-----------|
| [`commits.format`](../../scripts/defaults.yml#L9) | `"ticket"` | `conventional` → `tipo(scope): mensaje` aceptado/rechazado · `ticket` → `AM-1234 - tipo: mensaje` aceptado/rechazado | ✅ |

---

## tickets

[→ defaults.yml:12](../../scripts/defaults.yml#L12)

Aplica cuando `commits.format` es `"ticket"`. Controla la validación de prefijos y el linkeo en changelogs.

| Key | Default | Comportamiento probado | Cobertura |
|-----|---------|------------------------|-----------|
| [`tickets.prefixes`](../../scripts/defaults.yml#L13) | `[]` | Vacío = cualquier prefijo se acepta · Con valores = solo los prefijos listados pasan validación | ✅ |
| [`tickets.required`](../../scripts/defaults.yml#L14) | `false` | `false` = commit sin ticket pasa · `true` = commit sin ticket es rechazado | ✅ |
| [`tickets.url`](../../scripts/defaults.yml#L15) | `""` | El getter lee el valor correctamente | ⚠️ solo getter — el renderizado del link no está probado |

---

## validation

[→ defaults.yml:17](../../scripts/defaults.yml#L17)

Controla qué commits son aceptados y cuáles se ignoran durante el cálculo de versión.

| Key | Default | Comportamiento probado | Cobertura |
|-----|---------|------------------------|-----------|
| [`validation.require_ticket_prefix`](../../scripts/defaults.yml#L18) | `false` | `false` = commit sin prefijo pasa · `true` = commit sin prefijo es rechazado | ✅ |
| [`validation.require_commit_types`](../../scripts/defaults.yml#L19) | `true` | `false` = validación de tipos desactivada · `true` + `changelog.mode: last_commit` = solo el último commit debe tener tipo · `true` + `changelog.mode: full` = todos los commits deben tener tipo | ❌ |
| [`validation.ignore_patterns`](../../scripts/defaults.yml#L20) | `["^Merge", "^Revert", ...]` | Commits que matchean los patrones son ignorados en validación y changelog · Merge commits, reverts, fixup!, squash!, chore(release) y chore(hotfix) están cubiertos | ✅ |
