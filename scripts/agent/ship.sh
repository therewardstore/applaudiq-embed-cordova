#!/usr/bin/env bash
# Ships the current branch after the developer's commit reply: push → pull request (reused
# when one exists) → the Jira comment, printed for the Atlassian MCP → done. Resumable: every step is
# recorded in scripts/agent/state/<KEY>.md and skipped on a re-run. Never force-pushes,
# never rebases, never commits: those are printed for the developer. TASK_PUSH=manual
# prints every command instead of running it.
#
#   bash scripts/agent/ship.sh [--dry-run] [--resume] [--title "<header>"]
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

dry=0; title=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --resume) ;;
    --title) title="${2:-}"; shift ;;
    *) echo "usage: ship.sh [--dry-run] [--resume] [--title <header>]" >&2; exit 2 ;;
  esac
  shift
done
[ "$TASK_PUSH" = manual ] && dry=1

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$branch" ] || { echo "✖ detached HEAD: check out the ticket branch first" >&2; exit 1; }
key="$(friday_ticket_of "$branch")"; [ -n "$key" ] || key="$(printf '%s' "$branch" | tr '/' '-')"
[ "$branch" != "$DEFAULT_BRANCH" ] || { echo "✖ on $DEFAULT_BRANCH: nothing ships from the default branch" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "✖ uncommitted changes: answer the commit question first (or stash your unrelated work)" >&2; exit 1; }
state="scripts/agent/state/$key.md"
mkdir -p scripts/agent/state
touch "$state"
step_done() { grep -q "^ship: $1" "$state"; }
record() { printf 'ship: %s\n' "$1" >> "$state"; friday_audit "ship $key $1"; }
run() {
  if [ "$dry" = 1 ]; then printf '    %s\n' "$*"; return 0; fi
  "$@"
}
recorded="$(sed -n 's/^fingerprint: //p' "$state" | tail -1)"
if [ -n "$recorded" ]; then
  fingerprint="$(printf '%s\n' "$recorded" | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -c1-12)"
else
  fingerprint="$(bash scripts/agent/fingerprint.sh --short 2>/dev/null || echo none)"
fi
base="$DEFAULT_BRANCH"
# PR title `<KEY>: <Summary>` from --title, else the Orbit record (the Jira summary), else the first
# commit. pr-title.sh owns the format; PR quality gates' pr-title job applies it to UI-made PRs.
if [ -z "$title" ]; then
  orbit_root="${ORBIT_ROOT:-$(git config --get orbit.root 2>/dev/null || true)}"
  [ -z "$orbit_root" ] || [ ! -f "$orbit_root/.orbit/changes/$key.md" ] \
    || title="$(sed -n "1s/^# $key — //p" "$orbit_root/.orbit/changes/$key.md")"
fi
[ -n "$title" ] || title="$(git log --reverse --format=%s "$(bash scripts/agent/gates.sh range 2>/dev/null || echo "origin/$base..HEAD")" 2>/dev/null | head -1)"
[ -n "$title" ] || title="$(git log -1 --format=%s)"
title="$(bash scripts/git/pr-title.sh "$branch" "$title")"
echo "ship: $key on $branch → $base$([ "$dry" = 1 ] && echo ' (printing the commands; nothing runs)')"
echo "  title: $title"

# 1. push (upstream set once; a rejected push is the hook's or the server's verdict: no retry)
if step_done pushed; then
  echo "▸ pushed (recorded)"
else
  echo "▸ push"
  if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    run git push || { echo "✖ push rejected — fix what the gate or the server reported, then: bash scripts/agent/ship.sh --resume" >&2; exit 1; }
  else
    run git push -u origin "$branch" || { echo "✖ push rejected — fix what the gate or the server reported, then: bash scripts/agent/ship.sh --resume" >&2; exit 1; }
  fi
  [ "$dry" = 1 ] || record pushed
fi

# 2. pull request: reuse the open one for this branch
pr_url=""
if step_done 'pr:'; then
  pr_url="$(sed -n 's/^ship: pr:[0-9]* //p' "$state" | tail -1)"
  echo "▸ pull request (recorded): $pr_url"
elif ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "▸ gh is not available or not logged in: open the pull request by hand, titled: $title"
  encoded="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$title" 2>/dev/null || true)"
  pr_url="https://github.com/${REPO_SLUG:-<owner>/<repo>}/compare/$base...$branch?expand=1${encoded:+&title=$encoded}"
else
  existing="$(gh pr view "$branch" --json number,url -q '"\(.number) \(.url)"' 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    pr_url="${existing#* }"
    echo "▸ pull request exists: $pr_url"
    current="$(gh pr view "$branch" --json title -q .title 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "$title" ]; then
      echo "▸ retitle: $current → $title"
      run gh pr edit "${existing%% *}" --title "$title" || echo "  ✖ gh pr edit failed: retitle it by hand" >&2
    fi
    [ "$dry" = 1 ] || record "pr:${existing%% *} $pr_url"
  else
    body="$(mktemp)"
    {
      echo "## $title"
      echo
      echo "Ticket: $key · fingerprint \`$fingerprint\`"
      echo
      echo "### What changed"
      git log --reverse --format='- %s' "$(bash scripts/agent/gates.sh range 2>/dev/null || echo "origin/$base..HEAD")" 2>/dev/null
      echo
      # In an Orbit workspace the record holds Impact, QA and Rollback (/handoff writes QA there); orbit ship then
      # adds the 📋 record block. Elsewhere the QA plan is docs/qa/<KEY>.md.
      record_md="${ORBIT_ROOT:-$(git config --get orbit.root 2>/dev/null || true)}/.orbit/changes/$key.md"
      if [ "$ORBIT" = 1 ] && [ -f "$record_md" ]; then
        for part in "Impact:Impact / contracts" "QA:QA plan" "Rollback:Rollback"; do
          echo "### ${part#*:}"
          text="$(awk -v h="## ${part%%:*}" '$0 == h {on=1; next} /^## / {on=0} on' "$record_md" | sed '/<!--/,/-->/d' | sed '/^[[:space:]]*$/d')"
          if [ -n "$text" ]; then echo "$text"; elif [ "${part%%:*}" = QA ]; then echo "No QA plan yet (/handoff)."; else echo "_none_"; fi
          echo
        done
      else
        echo "### QA"
        if [ -f "docs/qa/$key.md" ]; then echo "See \`docs/qa/$key.md\`."; else echo "No QA plan yet (/handoff)."; fi
      fi
    } > "$body"
    echo "▸ open the pull request"
    if [ "$dry" = 1 ]; then
      printf '    gh pr create --base %s --head %s --title %q --body-file %s\n' "$base" "$branch" "$title" "$body"
      pr_url="<pr url>"
    else
      created="$(gh pr create --base "$base" --head "$branch" --title "$title" --body-file "$body" 2>&1)" || { echo "✖ gh pr create failed: $created" >&2; rm -f "$body"; exit 1; }
      pr_url="$(printf '%s\n' "$created" | grep -oE 'https://github.com/[^ ]+' | tail -1)"
      number="$(gh pr view "$branch" --json number -q .number 2>/dev/null || echo 0)"
      record "pr:$number $pr_url"
      echo "  $pr_url"
    fi
    rm -f "$body"
  fi
fi

# 3. Jira comment: printed for the agent to post through the Atlassian MCP (addCommentToJiraIssue).
#    The marker carries the fingerprint, so a ticket that already has it gets no second comment.
marker="[friday handoff $fingerprint]"
# In an Orbit workspace check 5 of the PR checks posts and keeps the ticket comment once the checks pass.
if [ "$ORBIT" = 1 ] && [ "$FRIDAY_CONF_CI" = github ]; then
  echo "▸ Jira: check 5 (Jira update) comments on $key once the PR checks pass; nothing to post by hand"
elif [ "$JIRA_COMMENT" = 1 ] && printf '%s' "$key" | grep -qE "^${TICKET_RE}$"; then
  if step_done 'jira-comment:'; then
    echo "▸ Jira comment (recorded)"
  else
    comment="$marker PR: $pr_url — $title$([ -f "docs/qa/$key.md" ] && echo " · QA plan: docs/qa/$key.md")"
    echo "▸ Jira comment for $key — post it with the Atlassian MCP (addCommentToJiraIssue), unless a comment with $marker is already there:"
    echo "    $comment"
    [ "$dry" = 1 ] || record "jira-comment:mcp"
  fi
fi
[ "$dry" = 1 ] || record done

echo
echo "Next"
echo "  review the pull request: $pr_url"
echo "  merge → the deploy follows ($([ "$FRIDAY_CONF_CI" = github ] && echo 'the PR checks must be green' || echo 'no CI contract here')); rollback = redeploy the previous build or a revert PR"
[ "$dry" = 0 ] || echo "  run the commands above by hand (TASK_PUSH=$TASK_PUSH$([ "$dry" = 1 ] && [ "$TASK_PUSH" = auto ] && echo ', --dry-run'))"
