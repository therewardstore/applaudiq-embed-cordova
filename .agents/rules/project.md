---
trigger: always_on
---

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

Read first, in full:
- `CLAUDE.md` (the rules, the skills table, the gates)
- `docs/README.md` (the docs index) → `docs/GATES.md`, `docs/TOOLS.md`
- the skills in `.claude/skills/` the change touches, in full
- `CLAUDE.md` at the repo root is the always-on doc for this repo. Read it and follow it.
  Where it and a skill in `.claude/skills/` disagree, the skill wins.
- If your context has no line starting with `scan-check:`, run
  `bash scripts/agent/session-check.sh` before your first action in this conversation, and
  report any drift it prints.
- `/flow`, `/scan`, `/task`, `/finalize`, `/handoff` and `/review` in `.agents/workflows/` ARE the skills
  (relative links to `.claude/skills/<name>/SKILL.md`, read in full). `/flow` governs every request when
  `TASK_MODE=auto`; run the others when the user asks.
- Terminal allow list (Settings → Agent → Terminal Command Auto Execution → Request Review): add
  `command(bash)` for `scripts/agent/` and `scripts/git/`, and `pnpm typecheck` · `pnpm build` · `pnpm run audit:deps`, so `/scan` and `/finalize` run without a prompt.
- Commits and branches follow `.agents/rules/commits-and-branches.md`.
