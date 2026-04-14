# Per-folder changelog — Exact matching

Escenario: monorepo con carpetas planas. El scope del commit debe coincidir **exactamente** con el nombre de la carpeta.

---

## Configuración

```yaml
commits:
  format: "conventional"

changelog:
  per_folder:
    enabled: true
    folders:
      - api
      - web
      - shared
    folder_pattern: ""
    scope_matching: "exact"
    fallback: "file_path"
```

---

## Estructura del repositorio

```
repo/
├── CHANGELOG.md
├── api/
│   ├── CHANGELOG.md
│   └── main.go
├── web/
│   ├── CHANGELOG.md
│   └── index.html
└── shared/
    ├── CHANGELOG.md
    └── utils/
        └── helpers.sh
```

---

## Routing por commit

| Commit | Scope extraído | Carpeta resuelta | CHANGELOG actualizado |
|--------|---------------|------------------|-----------------------|
| `feat(api): add auth endpoint` | `api` | `api/` | `api/CHANGELOG.md` |
| `fix(web): correct layout` | `web` | `web/` | `web/CHANGELOG.md` |
| `refactor(shared): extract helpers` | `shared` | `shared/` | `shared/CHANGELOG.md` |
| `feat(API): add endpoint` | `API` | sin match (case sensitive) → fallback | según `fallback` |
| `feat(api-v2): new version` | `api-v2` | sin match (`api-v2` ≠ `api`) → fallback | según `fallback` |
| `chore: update deps` | *(sin scope)* | sin match → fallback | según `fallback` |

---

## Notas

- `folder_pattern: ""` — sin filtro, todas las subcarpetas directas de cada carpeta raíz son candidatas.
- El matching es **case sensitive** — scope `API` no resuelve a carpeta `api/`.
- A diferencia de `suffix`, no hay tolerancia a prefijos numéricos ni sufijos adicionales — el scope debe ser el nombre exacto.
- Los commits sin match siguen el comportamiento definido en `fallback`. En este escenario es `file_path` — ver [fallback: file_path](fallback-file-path.md).
- `fallback: "file_path"` no es un typo de `"filePath"` ni `"file-path"` — el valor exacto es `file_path` con underscore.

## Limitaciones conocidas

**file_path con archivos en múltiples carpetas** — si el commit toca `api/main.go` y `web/index.html`, el comportamiento actual manda al root en lugar de escribir en `api/CHANGELOG.md` + `web/CHANGELOG.md`. Ver [ticket 037](../../../temp/features/037-per-folder-fallback-multi-folder-write.md) — **no implementado, sin test**.
