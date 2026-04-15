# Per-folder changelog — Fallback: file_path

Escenario: el commit no tiene scope (o el scope no matchea ninguna carpeta). En lugar de ir al root, el sistema intenta resolver la carpeta destino **según los archivos modificados** por el commit.

Regla actual: si todos los archivos tocados caen dentro de **exactamente una** carpeta configurada → escribe en esa carpeta. Cualquier otra situación → root.

> ⚠️ Comportamiento pendiente de mejora: si los archivos caen en múltiples carpetas configuradas, debería escribir en todas — hoy va al root. Ver [ticket 037](../../../temp/features/037-per-folder-fallback-multi-folder-write.md).

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
│   ├── main.go
│   └── handler.go
├── web/
│   ├── CHANGELOG.md
│   ├── index.html
│   └── style.css
├── shared/
│   ├── CHANGELOG.md
│   └── utils/
│       └── helpers.sh
└── README.md
```

---

## Routing por archivos modificados

| Archivos tocados por el commit | Carpeta resuelta | CHANGELOG actualizado |
|-------------------------------|------------------|-----------------------|
| `api/main.go` | `api/` — único match | `api/CHANGELOG.md` |
| `web/index.html`, `web/style.css` | `web/` — todos en la misma carpeta | `web/CHANGELOG.md` |
| `shared/utils/helpers.sh` | `shared/` — archivo anidado dentro de `shared/` | `shared/CHANGELOG.md` |
| `api/main.go`, `README.md` | `api/` — `README.md` está fuera de carpetas configuradas, se ignora | `api/CHANGELOG.md` |
| `api/main.go`, `web/index.html` | ⚠️ comportamiento actual: ambiguo → root · comportamiento esperado: escribir en `api/CHANGELOG.md` + `web/CHANGELOG.md` — ver [ticket 037](../../../temp/features/037-per-folder-fallback-multi-folder-write.md) | `CHANGELOG.md` (root) — pendiente fix |
| `docs/readme.md` | sin match — fuera de todas las carpetas configuradas | `CHANGELOG.md` (root) |
| `README.md` | sin match — archivo en root | `CHANGELOG.md` (root) |

---

## Notas

- Los archivos en root (fuera de cualquier carpeta configurada) se **ignoran** en la resolución — no cuentan como match ni como ambigüedad.
- Si el resultado es ambiguo (archivos en dos o más carpetas distintas) → root. No hay prioridad entre carpetas.
- Este fallback aplica **solo cuando el scope no matchea** ninguna carpeta por `scope_matching`. Si el scope matchea, `file_path` no se evalúa.
