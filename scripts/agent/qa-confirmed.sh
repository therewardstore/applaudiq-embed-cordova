#!/usr/bin/env bash
# CI's `qa-confirmed` check (QA_CONFIRM=required): the change record carries one
# `confirmed: <case> @ <sha>` line per QA case, written by /handoff's follow-up commit, and
# each sha is still current — no later commit outside docs/qa/ and .orbit/changes/ exists.
#
#   qa-confirmed.sh <tip> [<record>]
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

tip="$(friday_resolve "${1:-HEAD}")" || exit 2
branch="${FRIDAY_CI_BRANCH:-$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')}"
key="$(friday_ticket_of "$branch")"
record="${2:-}"
if [ -z "$record" ]; then
  if [ "$ORBIT" = 1 ] && [ -n "$key" ] && [ -f ".orbit/changes/$key.md" ]; then record=".orbit/changes/$key.md"
  elif [ -n "$key" ]; then record="docs/qa/$key.md"
  fi
fi
[ "$QA_CONFIRM" = required ] || { echo "qa-confirmed: advisory (QA_CONFIRM=$QA_CONFIRM); nothing required"; exit 0; }
[ -n "$record" ] && [ -f "$record" ] || { echo "✖ no QA record for $branch (${record:-no ticket in the branch name}): run /handoff" >&2; exit 1; }

lines="$(grep -E '^confirmed: .+ @ [0-9a-f]{7,40}$' "$record" || true)"
[ -n "$lines" ] || { echo "✖ $record has no 'confirmed: <case> @ <sha>' line" >&2; exit 1; }
failed=0
while IFS= read -r line; do
  sha="${line##* @ }"
  case="${line#confirmed: }"; case="${case% @ *}"
  if ! git merge-base --is-ancestor "$sha" "$tip" 2>/dev/null; then
    echo "✖ \"$case\" was confirmed at $sha, which is not in this branch" >&2; failed=1; continue
  fi
  later="$(git rev-list "$sha..$tip" -- . ':!docs/qa' ':!.orbit/changes' | wc -l | tr -d ' ')"
  if [ "$later" != 0 ]; then
    echo "✖ \"$case\" was confirmed at $(git rev-parse --short "$sha"); $later later commit(s) changed the code — confirm it again" >&2; failed=1
  else
    echo "✓ $case @ $(git rev-parse --short "$sha")"
  fi
done <<< "$lines"
[ "$failed" = 0 ] && echo "qa-confirmed: ok" || exit 1
