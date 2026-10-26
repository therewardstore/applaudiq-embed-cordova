#!/usr/bin/env bash
# Turns "type: subject" into "type(<TICKET>): subject" from the branch name. Runs
# once per commit even when two hooks call it: a header that already carries a
# scope is left alone for check-commit-msg.sh to judge.
set -euo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

file="$1"
source="${2:-}"
case "$source" in merge|squash|commit) exit 0 ;; esac

branch="$(git symbolic-ref --quiet --short HEAD || true)"
ticket="$(friday_ticket_of "$branch")"
[ -z "$ticket" ] && exit 0

first="$(sed -n '1p' "$file")"
case "$first" in
  Merge\ *|Revert\ *|fixup!\ *|squash!\ *|amend!\ *) exit 0 ;;
esac
# Only a bare "type: subject" gets the ticket; any scope (a ticket or not) stays as written.
header="$(printf '%s\n' "$first" | sed -E "s/^([a-z]+): /\1($ticket): /")"
[ "$header" = "$first" ] && exit 0

tmp="$(mktemp)"
awk -v h="$header" 'NR == 1 { print h; next } { print }' "$file" > "$tmp"
cat "$tmp" > "$file"
rm -f "$tmp"
