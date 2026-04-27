# Integration test harness — Go

End-to-end test runner for panora-versioning-pipe against live CI platforms (GitHub Actions, Bitbucket Pipelines).

See `Makefile` targets for `test-harness-go` and `test-harness-go-filter` for how to invoke.

---

## Marking scenarios as xfail

Use `xfail: true` when a scenario exercises a bug that has been **diagnosed, has an open ticket, but is not yet fixed** in the pipe Go implementation.

### When to use

- Pipe Go has a known bug with an open ticket.
- The scenario fails consistently because of that bug.
- You want the CI gate to remain green while the fix is pending, without losing the test coverage.

### When NOT to use

- Bugs in the harness itself (fix the harness).
- Flaky / intermittent failures (investigate the root cause).
- Infrastructure problems (network, GitHub rate limits, sandbox state).

### YAML example

```yaml
- name: hotfix-squash-gap-blocked
  xfail: true
  xfail_reason: "ticket 082 — guard validation.hotfix_title_required no portado al pipe Go"
  base: sandbox-22
  # ... rest of scenario
```

### Conventions

- `xfail_reason` is **mandatory** when `xfail: true` — the loader will fail-fast if missing.
- Start the reason with `"ticket NNN —"` so the owning ticket is always traceable.

### Runner behavior

| Marked xfail | Scenario outcome | Status | Exit code |
|---|---|---|---|
| `true` | fails (expected) | `XFAIL` | 0 |
| `true` | passes (unexpected) | `XPASS` | **1** |
| `false` / absent | fails | `FAIL` | 1 |
| `false` / absent | passes | `PASS` | 0 |

`XPASS` exits 1 to force maintenance: it means the bug was fixed and the `xfail` marker must be removed.

### Workflow when closing the ticket

1. Remove `xfail: true` and `xfail_reason` from the scenario in `test-scenarios.yml`.
2. Run the scenario: `make test-harness-go-filter F=<scenario-name>`.
3. Verify it reports `PASS` and exit code 0.
4. Commit and close the ticket.
