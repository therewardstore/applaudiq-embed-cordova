#!/usr/bin/env bash
# Runs on every prompt (Claude: UserPromptSubmit; Cursor: beforeSubmitPrompt). One line,
# only when TASK_MODE=auto: it is what makes the skills govern the first message of a new
# chat, not the second. Reads nothing but git and the conf; always exits 0.
#
#   bash scripts/agent/prompt-check.sh           # one line of context
#   bash scripts/agent/prompt-check.sh cursor    # {"additional_context": "…"}
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

if [ "$FLEET" = 1 ]; then
  # A workspace root: nothing is built here. Name the repo, go there, follow its own flow.
  repos="$(find . -maxdepth 4 -name .git -not -path '*/node_modules/*' 2>/dev/null | sed 's#^\./##; s#/\.git$##' | sort | tr '\n' ' ')"
  text="friday (workspace root $(basename "$PWD")): this folder holds repos, it is not one. A request belongs to ONE repo — if the request does not name it, ASK first (one question, the repos as options: ${repos% }); then cd into it and follow THAT repo's .claude/skills/flow/SKILL.md. A branch needs a ticket (<TICKET>-slug): no ticket in the request → ASK before creating one (or propose a Jira ticket from the diff through the Atlassian MCP, with Ticket Size, Is Ad-hoc and every field Jira marks required asked as options, the developer as assignee, and wait for yes). Never commit on your own: after each finished task ASK the commit question; only 'commit' commits, one commit. Never create a branch, commit or edit files at the root; a repo without scripts/agent/agent.conf needs 'trs-app agents init' first."
else
  [ "$TASK_MODE" = auto ] || exit 0
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
  ticket="$(friday_ticket_of "$branch")"
  text="friday: repo $REPO_NAME @ $branch${ticket:+ ($ticket)} · TASK_MODE=auto — every request follows .claude/skills/flow/SKILL.md: decide where and which work type (hotfix | change | new), plan by type, build, gate, then ASK the commit question after EVERY finished task (commit / done / stop) — only 'commit' commits, and only that one commit; a yes to the ticket or the plan is not a yes to commit; never commit, push or skip a hook without the developer's reply. When something the flow needs is missing — the repo, the ticket (a branch is <TICKET>-slug), the work type — ASK one question with options instead of guessing."
fi
if [ "${1:-}" = cursor ]; then
  printf '%s' "$text" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify({additional_context:s})+"\n"))'
else
  printf '%s\n' "$text"
fi
exit 0
