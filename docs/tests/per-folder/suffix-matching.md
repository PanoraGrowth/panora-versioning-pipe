# Per-folder changelog — Suffix matching

Escenario: monorepo con carpetas numeradas. El scope del commit se resuelve a la carpeta cuyo nombre **termina con** el scope.

---

## Configuración

```yaml
commits:
  format: "conventional"

changelog:
  per_folder:
    enabled: true
    folders:
      - services
      - infrastructure
    folder_pattern: "^[0-9]{3}-"
    scope_matching: "suffix"
    fallback: "root"
```

---

## Estructura del repositorio

```
repo/
├── CHANGELOG.md
├── services/
│   ├── 001-cluster-ecs/
│   │   └── CHANGELOG.md
│   ├── 002-cluster-rds/
│   │   └── CHANGELOG.md
│   └── 003-api-gateway/
│       └── CHANGELOG.md
└── infrastructure/
    ├── 001-vpc/
    │   └── CHANGELOG.md
    └── 002-alb/
        └── CHANGELOG.md
```

---

## Routing por commit

| Commit | Scope extraído | Carpeta resuelta | CHANGELOG actualizado |
|--------|---------------|------------------|-----------------------|
| `feat(cluster-ecs): add autoscaling` | `cluster-ecs` | `services/001-cluster-ecs/` | `services/001-cluster-ecs/CHANGELOG.md` |
| `fix(cluster-rds): fix connection pool` | `cluster-rds` | `services/002-cluster-rds/` | `services/002-cluster-rds/CHANGELOG.md` |
| `feat(vpc): add private subnets` | `vpc` | `infrastructure/001-vpc/` | `infrastructure/001-vpc/CHANGELOG.md` |
| `fix(alb): correct listener rules` | `alb` | `infrastructure/002-alb/` | `infrastructure/002-alb/CHANGELOG.md` |
| `chore: update dependencies` | *(sin scope)* | sin match → fallback `root` | `CHANGELOG.md` |
| `feat(payments): add stripe` | `payments` | sin match en ninguna carpeta → fallback `root` | `CHANGELOG.md` |

---

## Notas

- La búsqueda se extiende a **todas** las carpetas listadas en `folders` — primero `services`, luego `infrastructure`.
- `folder_pattern: "^[0-9]{3}-"` filtra las subcarpetas: una carpeta llamada `cluster-ecs/` (sin prefijo numérico) **no** sería candidata aunque el suffix coincida.
- Commits sin scope y commits con scope que no matchea ninguna carpeta van al `CHANGELOG.md` raíz por `fallback: "root"`.

## Limitaciones conocidas

**Un solo nivel de profundidad** — `suffix` escanea solo `services/*/`, no baja recursivamente. `feat(routes)` con `folders: [services]` no matchea `services/003-api-gateway/routes/`. Ver [ticket 036](../../../temp/features/036-per-folder-suffix-multi-level.md) — **no implementado, sin test**.

**Glob patterns en folders[]** — `folders: [shared/**]` no funciona, `folders` solo acepta paths literales. Ver [ticket 038](../../../temp/features/038-per-folder-glob-in-folders.md) — **no implementado, sin test**.
