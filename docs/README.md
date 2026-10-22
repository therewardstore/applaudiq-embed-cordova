# Docs

<!-- friday:agents:start -->
## Agent workflow

| When you are about to… | Read |
|---|---|
| Land in this repo, or start a session (`/scan`) | [`scan` skill](../.claude/skills/scan/SKILL.md) |
| Start any feature, fix or refactor (`/task`) | [`task` skill](../.claude/skills/task/SKILL.md) |
| Check the house rules and what enforces each one | [CLAUDE.md](../CLAUDE.md) |
| Understand the git hooks, the gates and CI | [GATES.md](GATES.md) |
| Check a finished change before pushing (`/finalize`) | [`finalize` skill](../.claude/skills/finalize/SKILL.md) |
| Hand a finished change to QA (`/handoff`) | [`handoff` skill](../.claude/skills/handoff/SKILL.md) — one test plan per change, in a tester's words, into the tracked change record |
| Run a request end to end, or review a range (`/flow`, `/review`) | [`flow` skill](../.claude/skills/flow/SKILL.md) · [`review` skill](../.claude/skills/review/SKILL.md) |
| See what changed on day one of friday 0.7 | [MIGRATION-0.7.md](MIGRATION-0.7.md) — the new defaults, the commit question, the links every tool reads, and the rollback |
| Check which AI tool is wired to the skills and the guard | [TOOLS.md](TOOLS.md) — the support matrix; `trs-app agents doctor` is the live check |

The canonical copy of each skill is `.claude/skills/<name>/SKILL.md`. Cursor reads the same
files through `.cursor/skills/`; Codex and Antigravity through shims under `.agents/`.
<!-- friday:agents:end -->
