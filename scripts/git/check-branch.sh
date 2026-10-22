#!/usr/bin/env bash
# Usage: check-branch.sh [<branch>]
# A branch is <TICKET>[-short-description]. The rule is waived for an identity in
# EXEMPT_IDENTITIES, keyed on the pusher: locally the git identity or `git config
# github.user`, in CI only the GitHub actor (FRIDAY_CI_ACTOR).
set -euo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

branch="${1:-$(git symbolic-ref --quiet --short HEAD || true)}"
pattern="^${TICKET_RE}(-[a-z0-9]+)*$"

if [ -z "$branch" ]; then
  echo "✖ Detached HEAD. Check out a named branch before pushing." >&2
  exit 1
fi

if printf '%s\n' "$branch" | grep -qE "$pattern"; then
  exit 0
fi
if friday_exempt_pusher; then
  echo "⚠ branch \"$branch\" has no ticket; waived for an exempt identity (EXEMPT_IDENTITIES)" >&2
  exit 0
fi
cat >&2 <<MSG
✖ Branch "$branch" can't be pushed.
  Name it <TICKET>[-short-description]:
    ${TICKET_HUMAN} then ${TICKET_DIGITS_HUMAN}, then optional lowercase kebab-case words.
    e.g. $(printf '%s' "$TICKET_PREFIXES" | cut -d'|' -f1)-12587   $(printf '%s' "$TICKET_PREFIXES" | cut -d'|' -f1)-12587-order-export
  Rename it: git branch -m "$branch" <new-name>
  ($DEFAULT_BRANCH changes only by merging a pull request on the server.)
MSG
[ -z "$EXEMPT_IDENTITIES" ] || echo "  (exempt identities: $EXEMPT_IDENTITIES — if that is you, set: git config github.user <login>)" >&2
exit 1
