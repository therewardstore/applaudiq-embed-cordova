#!/usr/bin/env bash
# The /finalize fingerprint: what a verdict is bound to. One JSON line with the
# base, the tip, the policy (conf + rules + script hashes), the proposed file set
# and a content hash over the index diff, deletions and renames included. Editing
# a staged file again, or the policy, changes it; the working tree outside the
# index does not. GIT_INDEX_FILE is honoured, so a temp index is a snapshot.
#
#   fingerprint.sh                       # the JSON line for the index
#   fingerprint.sh --short               # the first 12 hex of its sha256
#   fingerprint.sh --tree <base> <tip>   # the same, over a committed range (stage 2)
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

short=0
case "${1:-}" in --short) short=1; shift ;; esac

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -c1-64; else shasum -a 256 | cut -c1-64; fi; }

policy="$( { cat scripts/agent/agent.conf 2>/dev/null; cat scripts/agent/eslint-rules.mjs 2>/dev/null; sed -n '/^# hashes$/,$p' scripts/agent/agent.manifest 2>/dev/null; } | sha256)"

if [ "${1:-}" = --tree ]; then
  from="${2:-}"; to="${3:-}"
  [ -n "$from" ] && [ -n "$to" ] || { echo "usage: fingerprint.sh [--short] --tree <base> <tip>" >&2; exit 2; }
  base_sha="$(friday_resolve "$from")" || exit 2
  tip="$(friday_resolve "$to")" || exit 2
  files="$(git diff --name-status "$base_sha" "$tip" | sort)" || { echo "✖ git diff failed" >&2; exit 3; }
  content="$( { git diff --binary "$base_sha" "$tip"; printf '%s\n' "$files"; } | sha256)"
else
  [ $# -eq 0 ] || { echo "usage: fingerprint.sh [--short] [--tree <base> <tip>]" >&2; exit 2; }
  tip="$(git rev-parse HEAD 2>/dev/null || echo none)"
  base_sha="$(friday_target HEAD 2>/dev/null | xargs -I{} git rev-parse {} 2>/dev/null || echo none)"
  [ -n "$base_sha" ] || base_sha=none
  files="$(git diff --cached --name-status | sort)" || { echo "✖ git diff --cached failed" >&2; exit 3; }
  content="$( { git diff --cached --binary; printf '%s\n' "$files"; } | sha256)"
fi

json="$(printf '{"base":"%s","tip":"%s","policy":"%s","content":"%s","files":[%s]}' \
  "$base_sha" "$tip" "$policy" "$content" \
  "$(printf '%s\n' "$files" | sed '/^$/d' | awk -F'\t' '{ printf "%s\"%s %s\"", (NR>1?",":""), $1, $NF }')")"
if [ "$short" = 1 ]; then
  printf '%s\n' "$json" | sha256 | cut -c1-12
else
  printf '%s\n' "$json"
fi
