#!/usr/bin/env bash
# Fails when a change touches more than FILE_CAP files, counted since the branch
# left its target: committed, staged, unstaged and untracked alike. A pull
# request that size cannot be reviewed; split it.
#
#   check-file-cap.sh                 # the branch plus the working tree
#   check-file-cap.sh <base>..<tip>   # a committed range only
#   check-file-cap.sh --cached        # the index (GIT_INDEX_FILE honoured: stage 1 of /finalize)
set -uo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

case "$FILE_CAP" in ''|*[!0-9]*) echo "✖ FILE_CAP='$FILE_CAP' in scripts/agent/agent.conf is not a number" >&2; exit 2 ;; esac

mode="${1:-}"
case "$mode" in
  --cached)
    files="$(git diff --cached --name-only | sed '/^$/d' | sort -u)" || { echo "✖ git diff --cached failed" >&2; exit 3; }
    what="in the proposed commit"
    ;;
  *..*)
    friday_check_range "$mode" || exit 2
    files="$(git diff --name-only "$mode" | sed '/^$/d' | sort -u)" || { echo "✖ git diff $mode failed" >&2; exit 3; }
    what="in $mode"
    ;;
  '')
    range="$(friday_range)" || exit 1
    files="$( {
      git diff --name-only "$range"
      git diff --name-only HEAD
      git ls-files --others --exclude-standard
    } | sed '/^$/d' | sort -u)" || { echo "✖ git diff failed" >&2; exit 3; }
    what="on this branch"
    ;;
  *) echo "usage: check-file-cap.sh [<base>..<tip> | --cached]" >&2; exit 2 ;;
esac
count="$(printf '%s\n' "$files" | sed '/^$/d' | wc -l | tr -d ' ')"

if [ "$count" -gt "$FILE_CAP" ]; then
  echo "✖ $count files changed $what; the cap is $FILE_CAP. Split the change." >&2
  exit 1
fi
echo "check-file-cap: $count files changed $what (cap $FILE_CAP)"
