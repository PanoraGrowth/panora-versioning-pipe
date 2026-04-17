# Per-folder changelog — Fallback: file_path

Escenario: el commit no tiene scope (o el scope no matchea ninguna carpeta). En lugar de ir al root, el sistema intenta resolver la carpeta destino **según los archivos modificados** por el commit.

Regla: si los archivos tocados caen dentro de carpetas configuradas → escribe en **todas** las carpetas matcheadas. Si ningún archivo cae en carpetas configuradas → root.

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
| `api/main.go`, `web/index.html` | múltiples matches → escribe en ambas | `api/CHANGELOG.md` + `web/CHANGELOG.md` |
| `docs/readme.md` | sin match — fuera de todas las carpetas configuradas | `CHANGELOG.md` (root) |
| `README.md` | sin match — archivo en root | `CHANGELOG.md` (root) |

---

## Notas

- Los archivos en root (fuera de cualquier carpeta configurada) se **ignoran** en la resolución — no cuentan como match ni como ambigüedad.
- Si los archivos caen en múltiples carpetas configuradas → el CHANGELOG se escribe en **todas** ellas.
- Este fallback aplica **solo cuando el scope no matchea** ninguna carpeta por `scope_matching`. Si el scope matchea, `file_path` no se evalúa.
