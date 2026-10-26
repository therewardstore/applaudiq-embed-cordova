#!/usr/bin/env bash
# Usage: check-commit-range.sh <branch> <base>..<tip>
# Every commit in the range is checked again, which is what catches a commit
# made with `git commit --no-verify`. An unknown revision is exit 2, never a pass.
set -euo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

branch="${1:-}"
range="${2:-}"
[ -n "$branch" ] && [ -n "$range" ] || { echo "usage: check-commit-range.sh <branch> <base>..<tip>" >&2; exit 2; }
commits="$(friday_commits "$range")" || exit $?
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
failed=0
checked=0

for sha in $commits; do
  checked=$((checked + 1))
  short="$(git rev-parse --short "$sha")"
  an="$(git log -1 --format='%an' "$sha")"; ae="$(git log -1 --format='%ae' "$sha")"
  cn="$(git log -1 --format='%cn' "$sha")"; ce="$(git log -1 --format='%ce' "$sha")"
  if ! friday_is_automation "$an" "$ae"; then
    for role in author committer; do
      [ "$role" = author ] && who="$an <$ae>" || who="$cn <$ce>"
      if printf '%s\n' "$who" | grep -qiE "$BOT_IDENT_RE"; then
        echo "✖ $short: the $role is a bot or AI identity ($who)" >&2
        failed=1
      fi
    done
  fi
  # Under break-glass only the identity half runs (FRIDAY_IDENTITY_ONLY=1).
  [ "${FRIDAY_IDENTITY_ONLY:-}" = 1 ] && continue
  git log -1 --format='%B' "$sha" > "$tmp"
  if ! out="$(bash scripts/git/check-commit-msg.sh "$tmp" "$branch" push "$an <$ae>" 2>&1)"; then
    printf '%s\n' "$out" | sed "s/^/[$short] /" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "Fix the commits above (git rebase -i, reword or squash), then push again." >&2
  exit 1
fi
echo "check-commit-range: $checked commit(s) in $range ok"
