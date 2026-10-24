# Dependency audit exceptions

`bash scripts/agent/audit-check.sh` (pre-push, `/finalize`, CI and the weekly Dependency audit) allows an
advisory only when its GHSA id is in `pnpm.auditConfig.ignoreGhsas` **and** has a row here: no release fixes
it yet, the reason says why it cannot reach users, and the end date is at most
90 days away (`AUDIT_EXCEPTION_MAX_DAYS`). A fix shipping, the date passing or
the package leaving the tree fails the gate. The goal is an empty table.

| Advisory | Package | Until | Why it is safe until then |
|---|---|---|---|

## Overrides

A `pnpm.overrides` entry scoped to the vulnerable versions of one line (`pkg@>=1.2.0 <1.2.5`: `^1.2.5`) needs
no row. One that crosses a breaking line (a major, or a 0.x minor), names no vulnerable range, or targets a
`parent>child` chain is a reviewed decision: a row here, with a review date at most
90 days away and why the parent still works. The weekly Dependency audit also
re-resolves the tree without each override and reports the ones nothing needs any more.

| Override | Review by | Why it is needed and safe |
|---|---|---|
| `basic-ftp` | 2027-01-21 | Every 5.x is in GHSA-c475-qrg2-pj4r; only release-it's proxy agent (get-uri) loads it, and 6.x keeps the client API it calls. Dev tooling, never in the package. |
| `esbuild` | 2027-01-21 | tsup 8 asks for ^0.27, and GHSA-g7r4-m6w7-qqqr is fixed only in 0.28.1; the built dist is byte-identical on 0.28. Drop it with tsup 9 (needs Node ≥ 22.18). |
