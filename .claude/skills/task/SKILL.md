---
name: task
description: >-
  Builds one change to this repo: reads the skills that govern it, plans as much as the work
  type needs (hotfix: none; change: printed; new: approved first), does the work and runs the
  gates at the plan's risk. Runs inside /flow for every request, or when the user types /task <request>.
disable-model-invocation: true
---

# Task — read, plan by type, work, gate

Request: $ARGUMENTS

Most bad changes start with typing before reading the rule that governs the area. `/task` is the
order of work that prevents that: read first, plan as much as the work type needs, build, gate. A
skill beats a doc; the source beats both, and the doc gets fixed. Every change follows the rules in
`CLAUDE.md` and this repo's own skills. With `TASK_MODE=auto`, `/flow` runs this for every request
and owns the ticket, the commit question and the ship; alone, `/task` ends at a green gate.

## 0. Type, then how much stops you

| Type | Plan | Gates in step 4 |
|---|---|---|
| `hotfix` | none: print the read-only diagnosis (cause, `file:line`, the one fix) and go | `low` |
| `change` | print the plan and continue; stop for approval only when a step touches auth, payments, routing infrastructure or shared state | `medium` |
| `new` | approved before the first edit — Claude Code: call EnterPlanMode now, steps 1–3 read-only, ExitPlanMode, wait; Cursor, Codex, Antigravity: the tool's plan mode (`/plan`), or print the plan and wait for `go` | `high` |

A hotfix adds no dependency or migration and stays inside one module (`no-deps,no-migrations,module-scope`); one that
must is a `change`. Confirm the type in one line. An edit before the stop a type requires is a failed run.

## 1. Read what governs the change — before the plan

| The change touches | Read first |
|---|---|
| _(no domain skills yet)_ | — |
| a module's logic | that module's doc (see `scripts/git/doc-map.txt`), and its skill if it has one |
| a component, hook or helper, or any UI | this repo's own UI skill (listed in CLAUDE.md § Skills) and the components it already has |
| a gate, a hook, a commit or a branch name | `docs/GATES.md`; `CLAUDE.md` § Rules |
<!-- repo-routes:start -->
<!-- repo-routes:end -->

If no row matches, say so and add a **proposed skill** to the plan (name, scope, first three
rules); it lands as its own change, never in this task. A `figma.com` URL in the request, or a
screen change, with the Figma MCP connected: `figma:get_design_context` on the node (and
`get_variable_defs` for tokens) goes under Evidence; not connected → `Design: Figma MCP not
connected` and continue.

## 2. Classify and plan — read-only

- **Surfaces** — a view (`src/modules/<Module>/views`), a module store (`store/`), the router,
  the platform slice (`src/{lib,config,store}`), an adapter (`src/packages`), copy (`—`), the build.
- **Ships in** — web.
- **Risk** — the type sets it (`hotfix` low, `change` medium, `new` high); a surface raises it,
  never lowers it: auth, payments, reward redemption, routing infrastructure, shared state → high.

    ## Plan: <n>
    Type: hotfix | change | new · Risk: low | medium | high — <why> · Surfaces: … · Files: …
    Skills read: … · Design: <figma url + tokens> | none
    Steps: 1) … 2) …
    Not changing: <what this plan deliberately leaves alone>
    Evidence: <file:line for each step's claim about the current code>
    Tests: <which to update or add>
    Risks / open questions: … (each with the option you recommend)

## 3. Work

- **UI.** Build with the UI library this repo already uses, as its own UI skill describes; reuse its
  components and theme before writing new ones. Never add the design system or another kit without a
  ticket that says so.
- **Tests.** Something earns a test when its breakage is invisible to typecheck and lint and
  expensive in production (`docs/TESTING.md` when the repo has one); a bug fix adds the regression test that fails before
  the fix. Formatting is automatic at commit (lint-staged runs prettier); never hand-format.
- **Effects and memos** list only the values they really read: never a dependency added to satisfy
  a lint rule, never one rebuilt every render (an object literal, an unmemoised selector result).
  `exhaustive-deps` is off on purpose; check a new memo once with
  `npx eslint --rule '{"react-hooks/exhaustive-deps":"error"}' <file>` and keep what matters.
- **Comments** say why, never what: at most 2 lines; a directive is one line,
  `// eslint-disable-next-line <rule> -- <why>`, never a block or `@ts-ignore`.
- Update the docs `scripts/git/doc-map.txt` maps to the touched code, or give that commit a
  `Docs-skip: <class> — <why>` trailer when none is needed.

## 4. Gate — one command, stop at the first failure

    bash scripts/agent/gates.sh task <low|medium|high>

Low: the code rules on the working tree (untracked files included), typecheck, lint. Medium: plus
the changed files' own tests (each changed source file at —% statements, branches,
functions and lines when the repo measures coverage; `—` means it does not) and the build. High:
plus the full suite — the only place it runs. `⚠` lines from scan-diff are re-render risks to fix or justify. Then one advisory line per
route the diff touches — route, what to look for, `(diff: file:line)` — for a person to try at
desktop 1440 · iPad landscape 1180 · iPad portrait 820 · mobile 390; `/finalize` carries the list forward.

## Standing traps

- **Attribution trailers.** Agents add `Co-authored-by` by default; the commit-msg hook rejects an
  AI one, so keep attribution off in settings instead of fighting the hook.
- **A gate edited in the hook.** The hooks call `scripts/agent/gates.sh`; a gate changes in
  `scripts/agent/agent.conf` and `docs/GATES.md`, or the docs drift.
<!-- repo-traps:start -->
<!-- Repo-specific traps go here. `trs-app agents upgrade` keeps this block on a re-run. -->
<!-- repo-traps:end -->

## Evidence, then stop

End with: commands run and their exit codes, files changed (these are the task-owned paths `/flow`
records), tests added, and what was **not** verified. Never commit, push, or skip hooks
(`--no-verify`): the commit question belongs to `/flow`, and the developer answers it. Never
invoke `/finalize` yourself. A worked plan is in `docs/GATES.md`.

## Related

CLAUDE.md · docs/GATES.md · `flow` (runs this) · `finalize` (the check) · `review` · `scan`
