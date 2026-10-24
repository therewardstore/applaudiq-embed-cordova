#!/usr/bin/env bash
# Usage: pr-title.sh <branch> <title>
# Prints the house pull request title, `<TICKET>: <Summary>`, for the branch's ticket. ship.sh and
# the pr-title job of .github/workflows/pr-quality-gates.yml both call it, so a PR opened in GitHub's UI ends up the same.
# A branch with no ticket (a bot's) keeps its title.
set -euo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

[ $# -eq 2 ] || { echo "usage: pr-title.sh <branch> <title>" >&2; exit 2; }
branch="$1"; title="$2"
key="$(friday_ticket_of "$branch")"
if [ -z "$key" ]; then
  printf '%s\n' "$title"
  exit 0
fi

# The ticket in any form a title starts with: TRS-123, TRS 123 (GitHub's title from a branch), TRS_123.
ticket="${key%%-*}[-_ ]?${key#*-}"
rest="$title"
shopt -s nocasematch
while :; do
  rest="${rest#"${rest%%[![:space:]]*}"}"
  if [[ $rest =~ ^[a-z]+\ ?\(${ticket}\)!?:(.*)$ ]] || [[ $rest =~ ^\[${ticket}\](.*)$ ]] \
    || [[ $rest =~ ^${ticket}([[:space:]:-].*)?$ ]]; then
    rest="${BASH_REMATCH[1]}"
    rest="${rest#"${rest%%[![:space:]:-]*}"}"
  else
    break
  fi
done
shopt -u nocasematch
rest="${rest%"${rest##*[![:space:]]}"}"
if [ -z "$rest" ]; then
  rest="${branch#"$key"}"; rest="${rest#-}"; rest="${rest//-/ }"
fi
[ -n "$rest" ] || rest="$key"
first="$(printf '%s' "${rest:0:1}" | tr '[:lower:]' '[:upper:]')"
printf '%s: %s\n' "$key" "$first${rest:1}"
