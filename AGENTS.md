<!-- friday:agents:start -->
# AGENTS.md

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


This repo's always-on doc is `CLAUDE.md`. Read it and follow it. Where it and a skill in
`.claude/skills/` disagree, the skill wins. Nothing from `CLAUDE.md` is copied here.

- If your context has no line starting with `scan-check:`, run
  `bash scripts/agent/session-check.sh` before your first action, and report any drift it prints.
- Every skill in `.claude/skills/` is linked as `.agents/skills/<name>/SKILL.md` (Codex: `$flow`, `$task`…)
  and the six commands under `.agents/workflows/` (Antigravity: `/flow`…): the same files, in full.
  `flow` runs for every request when `TASK_MODE=auto`; the others only when the user asks for them.

## Read first

- `CLAUDE.md` (the rules, the skills table, the gates)
- `docs/README.md` (the docs index) → `docs/GATES.md`, `docs/TOOLS.md`
- the skills in `.claude/skills/` the change touches, in full

## Commits and branches

- Branches: `TRS-`, `AIQ-` or `INF-`, then 4–7 digits, then optional lowercase kebab-case
  words, e.g. `TRS-12587`, `TRS-12587-order-export`. Other branch names can't be pushed;
  `master` changes only by merging a pull request.
- Commit header: `<type>(<TICKET>): <subject>`, with the branch's ticket as the scope, e.g.
  `feat(TRS-12587): add category filter to listing`. Types: feat fix refactor perf style docs
  test build ci chore revert. Subject: non-empty; lowercase, imperative, no period and 72 characters
  or fewer are suggested, not enforced. Write `feat: <subject>` and the hook fills in the ticket.
- Body optional: if present, a blank line after the header, then why, wrapped at 100 characters.
  No footer.
- Never add an AI `Co-authored-by`, `Generated-by` or "Generated with …" line, or 🤖; a human co-author is fine. Never commit as a bot or AI identity; an agent commits only as the developer,
  after the developer answered the commit question.
- Never pass `--no-verify`. If a hook rejects a commit, fix the message instead.
- The full rules, and the scripts that enforce them: `scripts/git/check-commit-msg.sh` (it prints the rule a message breaks).
<!-- friday:agents:end -->
