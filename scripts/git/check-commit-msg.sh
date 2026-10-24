#!/usr/bin/env bash
# Usage: check-commit-msg.sh <message-file> [<branch>] [commit|push] [<author "Name <email>">]
# Required: <type>(<TICKET>): <subject>, the branch's ticket, no AI attribution
# (ATTRIBUTION_BAN=all bans every attribution trailer), no bot or AI identity.
# Everything else prints as a suggestion and never fails. An author in
# AUTOMATION_IDENTITIES passes the identity and header rules; one in
# EXEMPT_IDENTITIES passes the header and ticket rules — the code gates still run.
set -euo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

file="$1"
branch="${2:-$(git symbolic-ref --quiet --short HEAD || true)}"
mode="${3:-commit}"
author="${4:-}"
[ -n "$author" ] || author="$(git var GIT_AUTHOR_IDENT 2>/dev/null | sed 's/ [0-9]* [+-][0-9]*$//' || true)"
an="$(friday_ident_name "$author")"; ae="$(friday_ident_email "$author")"

types='feat|fix|refactor|perf|style|docs|test|build|ci|chore|revert'
header_re="^(${types})\\(${TICKET_RE}\\): .+$"
lazy_re='^(wip|fix|fixes|fixed|fixing|update|updates|updated|change|changes|misc|temp|tmp|test|testing|stuff|minor|cleanup|done|final|asdf)$'
trailer_re='^(co-authored-by|generated-by|assisted-by):'
ai_re='claude|copilot|chatgpt|cursor|codeium|gemini|codex|antigravity|openai|anthropic|noreply@anthropic\.com|\[bot\]|(^|[^a-z])ai([^a-z]|$)'
footer_re='generated (with|by) .*(claude|copilot|chatgpt|cursor|codeium|gemini|codex|(^|[^a-z])ai([^a-z]|$))|🤖'

msg="$(sed -e '/^# -\{24\} >8 -\{24\}$/,$d' -e '/^#/d' "$file")"
header="$(printf '%s\n' "$msg" | sed -n '1p')"
errors=()
suggestions=()
automation=0; friday_is_automation "$an" "$ae" && automation=1
exempt=0; friday_exempt_author "$an" "$ae" && exempt=1

# Attribution: an AI never signs a commit; a human co-author is fine unless the repo bans them all.
if [ "$ATTRIBUTION_BAN" = all ]; then
  if printf '%s\n' "$msg" | grep -qiE "$trailer_re|$footer_re"; then
    errors+=("No Co-authored-by or other attribution trailers, and no \"Generated with …\" / 🤖 footers (ATTRIBUTION_BAN=all).")
  fi
else
  if printf '%s\n' "$msg" | grep -iE "$trailer_re" | grep -qiE "$ai_re" || printf '%s\n' "$msg" | grep -qiE "$footer_re"; then
    errors+=("No AI attribution: no Co-authored-by naming an assistant, no \"Generated with …\" / 🤖 footer. Commit as yourself.")
  fi
fi
if [ "$mode" = commit ] && [ "$automation" = 0 ]; then
  for who in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
    if git var "$who" 2>/dev/null | grep -qiE "$BOT_IDENT_RE"; then
      errors+=("$who is a bot or AI identity: $(git var "$who" | sed 's/ [0-9]* [+-][0-9]*$//'). Commit as yourself.")
    fi
  done
fi

if [ "$automation" = 1 ]; then
  echo "▸ $an is automation: identity and header rules waived; the code gates still run" >&2
elif printf '%s\n' "$header" | grep -qE '^(Merge (branch|remote-tracking branch|pull request) |Revert ")'; then
  :
elif printf '%s\n' "$header" | grep -qE '^(fixup|squash|amend)! '; then
  [ "$mode" = push ] && errors+=("\"$header\" is a fixup commit. Squash it before pushing: git rebase -i --autosquash")
elif [ "$exempt" = 1 ] && ! printf '%s\n' "$header" | grep -qE "$header_re"; then
  echo "⚠ header rule waived for $an (EXEMPT_IDENTITIES): \"$header\"" >&2
else
  if ! printf '%s\n' "$header" | grep -qE "$header_re"; then
    errors+=("Header must be: <type>(<TICKET>): <subject>
      types: ${types//|/, }
      e.g.  feat($(printf '%s' "$TICKET_PREFIXES" | cut -d'|' -f1)-12587): add category filter to listing
      (write \"feat: <subject>\" on a ticket branch and the hook fills in the ticket)")
  else
    subject="${header#*: }"
    branch_ticket="$(friday_ticket_of "$branch")"
    msg_ticket="$(printf '%s\n' "$header" | grep -oE "\\(${TICKET_RE}\\)" | tr -d '()')"
    if [ -n "$branch_ticket" ] && [ "$branch_ticket" != "$msg_ticket" ] && [ "$exempt" = 0 ]; then
      errors+=("Ticket $msg_ticket doesn't match the branch's ticket $branch_ticket.")
    fi
    if [ -z "$branch_ticket" ] && [ -n "$branch" ] && [ "$branch" != "$DEFAULT_BRANCH" ] && [ "$branch" != "$PRODUCTION_REF" ] && [ "$exempt" = 0 ]; then
      errors+=("Ticket $msg_ticket is on branch \"$branch\", which has no ticket. Commit on $msg_ticket-<slug>: git branch -m \"$branch\" $msg_ticket-<slug>")
    fi
    [ "${#header}" -le 72 ] || suggestions+=("header is ${#header} characters; 72 reads better in git log")
    printf '%s\n' "$subject" | grep -qE '^[a-z0-9]' || suggestions+=("start the subject lowercase")
    printf '%s\n' "$subject" | grep -qE '[^. ]$' || suggestions+=("drop the trailing period")
    if [ "${#subject}" -lt 10 ] || printf '%s\n' "$subject" | grep -qiE "$lazy_re"; then
      suggestions+=("say what changed: \"add …\", \"fix … when …\" (subject is \"$subject\")")
    fi
  fi
fi

line2="$(printf '%s\n' "$msg" | sed -n '2p')"
[ -z "$line2" ] || suggestions+=("leave a blank line between the header and the body")
long="$(printf '%s\n' "$msg" | sed '1,2d' | grep -vE 'https?://' | awk 'length > 100 { print NR+2 }' | head -3 | tr '\n' ' ' || true)"
[ -z "$long" ] || suggestions+=("wrap the body at 100 characters (lines: $long)")

for s in ${suggestions[@]+"${suggestions[@]}"}; do echo "⚠ suggestion: $s" >&2; done
if [ "${#errors[@]}" -gt 0 ]; then
  echo "✖ Commit message rejected: \"$header\"" >&2
  for e in "${errors[@]}"; do echo "  • $e" >&2; done
  exit 1
fi
# Joined to Orbit but called by husky (a `pnpm install` resets core.hooksPath): Orbit checks the message too.
if [ "$ORBIT" = 1 ] && [ -z "${ORBIT_STAGE:-}" ]; then
  orbit_root="$(git config --get orbit.root 2>/dev/null || true)"
  if [ -n "$orbit_root" ] && [ -f "$orbit_root/bin/orbit.js" ]; then ORBIT_ROOT="$orbit_root" node "$orbit_root/bin/orbit.js" hook commit-msg "$file" || exit $?; fi
fi
