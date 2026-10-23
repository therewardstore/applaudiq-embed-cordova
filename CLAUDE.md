<!-- friday:preamble:start -->
**friday · applaudiq-embed-cordova** — default branch `master` · Orbit workspace. Every request here is a change and follows
`.claude/skills/flow/SKILL.md` automatically (`TASK_MODE=auto`: no `/task` needed):
decide where (root or repo) and the work type (hotfix | change | new), plan by type, build, gate
(`bash scripts/agent/gates.sh task <risk>`), then **ask before any commit** — never commit, push
or skip a hook without the developer's reply. Missing repo, ticket or type → **ask one question with
options**, never guess (a branch is `<TICKET>-slug`). On every line you add:
comments at most 2 lines and ≤100 characters, saying why; a linter directive is one line,
`// eslint-disable-next-line <rule> -- <why>`, never a block or `@ts-ignore` (`scripts/agent/scan-diff.sh` enforces all of it). No `scan-check:` line in your
context → run `bash scripts/agent/session-check.sh` first. Rules: CLAUDE.md § Rules · gates: docs/GATES.md.
Orbit workspace: repos live beside `orbit/`; every commit runs friday's gates, then Orbit's (branch,
header, change record at push). Work spanning repos starts at the workspace root with `./orbit work`.
<!-- friday:preamble:end -->

<!-- friday:agents:start -->
## The life of a change (`/flow`)

Every request is a change: `/flow` runs without being typed (`TASK_MODE=auto`; a prompt hook says so on every message). It decides where the work belongs and which type it is — `hotfix` (no plan stop, gates `low`),
`change` (plan printed, gates `medium`), `new` (plan approved first, gates `high`) —
settles the ticket (proposed from the real diff, created only after a yes) and the branch, runs
`/task` (reads the skills, plans by type, builds, `bash scripts/agent/gates.sh task <risk>`), then
`/finalize` on the proposed commit and **asks before any commit, after every finished task**: `commit`
(the agent commits as you, that one commit only), `done` (you committed) or `stop`. After the commit: `/finalize <sha>`, `/handoff` (the QA
plan into `.orbit/changes/<KEY>.md`, tracked) and `scripts/agent/ship.sh`
(push and PR as you, then the Jira comment through the Atlassian MCP), ending with
`Next` for you. `/scan` once per session reports what governs this repo and where this file
drifted; `/review` reads a range or PR like a reviewer. A session-start hook prints a
`scan-check:` line; `trs-app agents doctor` shows which tools are wired.

## Read first

- `CLAUDE.md` (the rules, the skills table, the gates)
- `docs/README.md` (the docs index) → `docs/GATES.md`, `docs/TOOLS.md`
- the skills in `.claude/skills/` the change touches, in full

## Skills

| Load it when | Skill |
|---|---|
| Landing in this repo or starting a session (`/scan`) | `scan` |
| Planning or shipping any change end to end (`/task`) | `task` |
| Checking a finished change before pushing (`/finalize`) | `finalize` |
| Writing the QA test plan for a finished change (`/handoff`) | `handoff` |
| Any request in this repo, start to finish: ticket, branch, /task, commit question, /handoff, ship (`/flow`, automatic when TASK_MODE=auto) | `flow` |
| Reviewing a diff or a pull request line by line against the house rules (`/review`) | `review` |

Where this file or a doc disagrees with a skill, the skill wins.

Maintenance rules:
- A new or changed skill lives ONLY in `.claude/skills/<name>/SKILL.md`. Every other tool reads
  that file through a relative link (`.cursor/skills/<name>`, `.agents/skills/<name>/SKILL.md`; the
  commands also `.cursor/commands/` and `.agents/workflows/`), so an edit reaches Cursor, Codex and Antigravity
  at once. A NEW skill needs its links and its row above: run `trs-app agents upgrade` (it links
  and lists it) — never copy a skill into another tool's folder.
- A new gate is a change to `scripts/agent/agent.conf` and `docs/GATES.md` in the same change;
  the hooks read the conf.
- A new drift check is a function in `scripts/agent/drift-check.sh` (and in `session-check.sh`
  too if it is cheap), landed with the doc fix that makes it pass.
- A trap discovered while fixing a bug goes into `/task`'s standing traps in the same change.
- A new feature area — or an old area that keeps turning up in plans with no skill — gets its own
  skill: `/task` proposes it, a person approves, and it lands as its own change with its row,
  symlink and shims. The doc map never requires a skill.
- If `/scan`'s step 4 is ever stripped, delete `/scan`.

Cursor, Codex and Antigravity read this file through `.cursor/rules/project.mdc`, `AGENTS.md`
and `.agents/rules/project.md`; don't copy it into any of them.

## Rules

| # | Rule | Enforced by |
|---|---|---|
| 1 | Branches are `TRS-`, `AIQ-` or `INF-` plus 4–7 digits; commits are `<type>(<TICKET>): <subject>` with no bot or AI identity or attribution | the commit-msg and pre-push hooks (`scripts/git/`) |
| 2 | Comments at most 2 lines; a linter directive is one line with `-- <why>`; no secret, no new render hazard on added lines | `scripts/agent/scan-diff.sh` at pre-commit, pre-push, in /task and /finalize (gates-only profile: no app rules) |
| 3 | A touched module updates its doc (`scripts/git/doc-map.txt`) in the same change, or one commit carries a `Docs-skip:` trailer | `scripts/git/check-docs-moved.sh` at pre-push |

## Quality gates

`pnpm typecheck` · `pnpm build` · `pnpm run audit:deps`. Pre-commit runs the code rules on the staged lines → the file cap → typecheck; pre-push runs branch name → commits being pushed → docs moved → typecheck → build → dependency audit → audit exceptions. The full table, and
what each gate proves: `docs/GATES.md`.
<!-- friday:agents:end -->

## Releasing (master only changes through a pull request)

`.release-it.json` tags, pushes and publishes nothing by default, so a bare `pnpm release` is always safe.

1. On the ticket branch `./orbit work` made (it tracks `origin/master`, which release-it requires): move
   `## [Unreleased]` in CHANGELOG.md under the new version and commit it (release-it wants a clean tree), then
   `pnpm release` bumps `package.json`, builds and commits `chore: release x.y.z`; the commit hook adds the
   branch's ticket. Push the branch and open the PR.
2. After the PR merges, on `master` after `git pull`, while `git log -1` is still the commit that PR landed as (if
   another PR merged since, stop: the tag would land on a later commit): `pnpm release --no-increment --no-git.commit
   --git.tag --npm.publish --git.requireBranch=master` tags `vx.y.z` on it and publishes to npm, then
   `git push origin vx.y.z` pushes the tag.

## Dependency audit exceptions

`pnpm run audit:deps` runs at pre-push. Every advisory here is in a devDependency (release, build or
type-check tooling); the package has no runtime `dependencies`, so nothing reaches consumers.
`pnpm.overrides` in `package.json` pins the patched versions of the fixable ones, and
`pnpm.auditConfig.ignoreGhsas` is empty: every known advisory is fixed. Add an exception there only for an
advisory with no fix anywhere, say why here, and drop an override or an exception as soon as an upgrade
of its parent (`release-it`, `tsup`) makes it unnecessary.
`release-it` stays on 20.x: 21.x needs Node ^22.21 and `.nvmrc` pins 22.14.0 (move both together).
`undici` is lifted within 7.x to ^7.29.1 (release-it 20.2.1 pins 7.28.0; 21.x ships 7.29.1).
Two overrides cross a line on purpose, because no release in the old line is fixed: `basic-ftp` 5 → 6
(every 5.x is in GHSA-c475-qrg2-pj4r; it is only `release-it`'s proxy agent) and `esbuild` 0.27 → 0.28
(GHSA-g7r4-m6w7-qqqr is fixed only in 0.28.1; `tsup` 8 asks for ^0.27, and its build output is
byte-identical on 0.28).
