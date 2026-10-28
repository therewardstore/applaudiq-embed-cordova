#!/usr/bin/env bash
# `trs-app agents doctor` / `bash scripts/agent/doctor.sh`: is every tool wired so the skills
# govern the FIRST message of a chat? One ✓/✖ line per tool and per net, then Next. Exit 1
# when anything is ✖. Reads only; fixes go through `trs-app agents upgrade`.
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

bad=0
ok() { echo "✓ $1"; }
ko() { echo "✖ $1"; bad=1; }
has() { [ -f "$1" ] && grep -q "$2" "$1"; }

echo "friday doctor — $REPO_NAME"
echo "Claude Code"
has .claude/settings.json 'session-check.sh' && ok "  SessionStart runs session-check.sh" || ko "  SessionStart does not run session-check.sh (.claude/settings.json)"
has .claude/settings.json 'prompt-check.sh' && ok "  UserPromptSubmit runs prompt-check.sh (skills govern the first message)" || ko "  UserPromptSubmit does not run prompt-check.sh"
has .claude/settings.json 'guard-shell.sh' && ok "  PreToolUse runs guard-shell.sh" || ko "  PreToolUse does not run guard-shell.sh"
[ -f .claude/skills/flow/SKILL.md ] && ok "  flow skill present" || ko "  .claude/skills/flow/SKILL.md missing"
echo "Cursor"
has .cursor/hooks.json 'session-check.sh' && ok "  sessionStart runs session-check.sh" || ko "  sessionStart does not run session-check.sh (.cursor/hooks.json)"
has .cursor/hooks.json 'prompt-check.sh' && ok "  beforeSubmitPrompt runs prompt-check.sh" || ko "  beforeSubmitPrompt does not run prompt-check.sh"
has .cursor/hooks.json 'guard-shell.sh' && ok "  beforeShellExecution runs guard-shell.sh" || ko "  beforeShellExecution does not run guard-shell.sh"
[ -L .cursor/skills/flow ] && ok "  skills linked (.cursor/skills)" || ko "  .cursor/skills/flow link missing"
echo "Codex"
has .codex/hooks.json 'session-check.sh' && ok "  SessionStart runs session-check.sh" || ko "  SessionStart does not run session-check.sh (.codex/hooks.json)"
has .codex/hooks.json 'guard-shell.sh' && ok "  PreToolUse runs guard-shell.sh" || ko "  PreToolUse does not run guard-shell.sh"
has .codex/config.toml 'codex_hooks = true' && ok "  hooks feature on (needs trust after each change: codex → /approvals)" || ko "  .codex/config.toml lacks codex_hooks = true"
[ -L .agents/skills/flow/SKILL.md ] && [ -e .agents/skills/flow/SKILL.md ] && ok "  skills linked in full (.agents/skills)" || ko "  .agents/skills/flow/SKILL.md link missing"
echo "Antigravity (unverified: no hook API; the rules file carries the preamble)"
[ -f .agents/rules/project.md ] && ok "  .agents/rules/project.md present" || ko "  .agents/rules/project.md missing"
[ -L .agents/workflows/flow.md ] && [ -e .agents/workflows/flow.md ] && ok "  workflows linked to the skills in full" || ko "  .agents/workflows/flow.md link missing"
echo "Nets"
hooks_path="$(git config core.hooksPath 2>/dev/null || true)"
case "$HOOKS" in
  husky) [ -n "$hooks_path" ] && ok "  git hooks wired ($hooks_path)" || ko "  git hooks not wired in this clone: run $PM install" ;;
  orbit) case "$hooks_path" in .orbit-hooks|*/.orbit-hooks) ok "  Orbit hook shim wired ($hooks_path)" ;; *) ko "  HOOKS=orbit but core.hooksPath is '${hooks_path:-unset}'" ;; esac ;;
  chain:*) [ -n "$hooks_path" ] && ok "  chained hooks at $hooks_path (${HOOKS#chain:})" || ko "  HOOKS=$HOOKS but core.hooksPath is unset" ;;
  *) ok "  no git hooks by policy (HOOKS=$HOOKS); pre-push and CI are the nets" ;;
esac
if [ "$FRIDAY_CONF_CI" != off ]; then
  grep -lsE '^\s*runs-on:.*(ubuntu|windows|macos)-' .github/workflows/*.yml >/dev/null 2>&1 \
    && ko "  a workflow runs on GitHub's runners — every job must use runs-on: ${CI_RUNNER}" \
    || ok "  CI runner: ${CI_RUNNER}${CI_SWITCH:+, on only while the variable $CI_SWITCH is 'on'}"
fi
if [ "$FRIDAY_CONF_CI" = github ]; then
  grep -qs 'gates.sh ci' .github/workflows/*.yml 2>/dev/null && ok "  CI runs gates.sh ci" || ko "  no workflow runs \`bash scripts/agent/gates.sh ci\` — copy scripts/agent/ci/pr-quality-gates.yml over .github/workflows/pr-quality-gates.yml through /task"
elif [ "$FRIDAY_CONF_CI" = off ]; then
  ls .github/workflows/*.yml >/dev/null 2>&1 && ko "  CI=off but .github/workflows/ still holds workflows — remove them (a public repo runs no CI)" || ok "  CI off: no workflows (public repo); checks run at commit and push"
else
  ok "  CI contract not enabled (CI='')"
fi
if [ -f scripts/agent/env-check.sh ]; then
  if out="$(bash scripts/agent/env-check.sh 2>&1)"; then ok "  env: $out"; else ko "  env: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
fi
if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 && ok "  gh authenticated (ship.sh can open PRs)" || ko "  gh is installed but not logged in: gh auth login"
else
  ko "  gh not installed: ship.sh will print the PR link instead of opening it"
fi
[ -z "$EXEMPT_IDENTITIES" ] || { [ -n "$(git config github.user 2>/dev/null)" ] && ok "  github.user set (exemptions resolve locally)" || echo "▸ EXEMPT_IDENTITIES is set; for a local exemption: git config github.user <login>"; }

echo
echo "Next"
if [ "$bad" = 1 ]; then
  echo "  trs-app agents upgrade        # rewires every ✖ above"
  echo "  trs-app agents doctor         # run again"
else
  echo "  /flow <your request>          # or just type the request: TASK_MODE=$TASK_MODE"
fi
exit "$bad"
