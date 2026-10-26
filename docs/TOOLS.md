# Tools

How each AI tool reaches the same rules. One canonical copy of every skill lives in
`.claude/skills/<name>/SKILL.md`; everything else points at it. `bash scripts/agent/doctor.sh`
(`trs-app agents doctor`) checks the wiring in this clone. Enforcement never depends on a tool:
the git hooks and CI are the guarantee; the tool hooks only save a round trip.

| Mechanism | Claude Code | Cursor | Codex | Antigravity |
|---|---|---|---|---|
| Always-on rules | `CLAUDE.md` (preamble first) — verified | `.cursor/rules/project.mdc` — verified | `AGENTS.md` — verified | `.agents/rules/project.md` — unverified |
| Skills | `.claude/skills/` — verified | `.cursor/skills/<name>` relative symlinks to the same folders, plus `.cursor/rules/skills.mdc` inlining the commands and docs with `@` references — verified | `.agents/skills/<name>/SKILL.md` relative symlinks to the same files (`$flow`) — verified | `.agents/workflows/<name>.md` relative symlinks to the command SKILL.md (`/flow`; the frontmatter is the skill's own) — unverified |
| Docs | the "Read first" list in CLAUDE.md | the same list, and the docs inlined by `skills.mdc` | the same list in `AGENTS.md` | the same list in `.agents/rules/project.md` |
| Session start (`scan-check:`) | `SessionStart` → `session-check.sh` — verified | `sessionStart` → `session-check.sh cursor` — verified | `SessionStart` → `session-check.sh` (needs `codex_hooks = true` and trust after each change) — verified | none: the rules file carries the preamble |
| Every prompt (`TASK_MODE=auto`) | `UserPromptSubmit` → `prompt-check.sh` — verified | `beforeSubmitPrompt` → `prompt-check.sh cursor` — unverified | `UserPromptSubmit` → `prompt-check.sh` — unverified | none |
| Shell guard (`--no-verify`, `HUSKY=0`, `core.hooksPath`, force push, break-glass) | `PreToolUse` → `guard-shell.sh` (exit 2 blocks) — verified | `beforeShellExecution` → `guard-shell.sh cursor` (`failClosed`) — unverified | `PreToolUse` → `guard-shell.sh` — unverified | none: the hooks and CI catch it |
| Permissions | `.claude/settings.json` allow list | `.cursor/permissions.json`, `.cursor/cli.json` | `.codex/rules/house.rules` | Settings → Terminal allow list (manual) |

"Verified" means a test in friday exercises the file's content and a person ran the tool against
it; "unverified" means the file is generated to the tool's documented schema and nobody has yet
watched the tool honour it. Report a cell that behaves differently through `/task`.

Codex forgets trust for `.codex/hooks.json` whenever the file changes: run `codex`, then
`/approvals`, after every `trs-app agents upgrade`.
