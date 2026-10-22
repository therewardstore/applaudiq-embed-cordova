# Friday 0.7 — what changed here

Written once by `trs-app agents upgrade`; edit or delete it when the team has read it.

## For every developer

- **Every request is a change.** With `TASK_MODE=auto` the `/flow` skill runs for every message: it decides the work type (`hotfix` — no plan stop · `change` — plan printed · `new` — plan approved first), builds, gates, and then **asks before any commit**. The agent never commits, pushes or skips a hook on its own; it commits only as you, after you answer `commit`, or continues after you commit by hand and reply `done`.
- **Comments: at most 2 lines, ≤100 characters, saying why.** A linter directive is one line: `// eslint-disable-next-line <rule> -- <why>`; blocks, `-line` forms, `@ts-ignore` and `@ts-nocheck` are refused on added lines.
- **The file cap is 2000** changed files; above it the change is split.
- **Pushes are judged on the pushed range** — branch, every commit's header and identity, the secret scan, the code rules, the cap, the docs, then the tree gates — so a `--no-verify` commit is caught at push. An unknown revision or a tool that could not run is a failure, never a pass.
- **One skill text for every tool.** `.claude/skills/<name>/SKILL.md` is the only copy; Cursor (`.cursor/skills`, `.cursor/commands`, `.cursor/rules/skills.mdc`), Codex (`.agents/skills`) and Antigravity (`.agents/workflows`) read it through links. Codex: run `/approvals` once to trust the updated hooks.
- **The QA plan** lives in `.orbit/changes/<KEY>.md` (tracked); `.qa/` stays for private notes.

## Commands

    trs-app agents status      # the effective config, one source per key
    trs-app agents doctor      # which tool is wired to the skills and the guard
    trs-app agents check       # the drift checks
    bash scripts/agent/gates.sh task low|medium|high
    trs-app ship [--dry-run]   # push → PR → Jira comment (posted through the Atlassian MCP), resumable

## Going back

`trs-app agents upgrade --rollback <stamp>` restores the files this run changed from
`.friday-backup/<stamp>/` and the previous manifest. The last resort is the friday release this repo had
before (its version is in `scripts/agent/agent.manifest` in git history):
`npx @therewardstore/create-app@<that version> agents-init`. The repo's own values (caps, comment length,
default branch) were kept by the upgrade; `trs-app agents upgrade --comment-lines 2 --file-cap 2000`
adopts the 0.7 policy when the team is ready.
