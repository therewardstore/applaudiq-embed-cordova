#!/usr/bin/env bash
# A touched module must update its doc in the same change (scripts/git/doc-map.txt).
# A `Docs-skip: <class> — <why>` trailer waives that for the modules THE COMMIT THAT
# CARRIES IT touches, never for the rest of the range.
#
#   check-docs-moved.sh <base>..<tip>   # every commit in the range
#   check-docs-moved.sh --cached        # the index as one unwaived commit (GIT_INDEX_FILE honoured)
set -uo pipefail
. "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"

map="scripts/git/doc-map.txt"
module_root="^${MODULES_DIR}/[^/]+/"
skip_re='^Docs-skip: (rename|cleanup|refactor|perf|format|tests-only) .{5,}'

mode="${1:-}"
# required: files whose docs must move; all: every file in the range (a doc updated anywhere counts)
required=""; all=""; waived_note=""
case "$mode" in
  --cached)
    all="$(git diff --cached --name-only | sed '/^$/d' | sort -u)" || { echo "✖ git diff --cached failed" >&2; exit 3; }
    required="$all"
    ;;
  *..*)
    commits="$(friday_commits "$mode")" || exit $?
    [ -z "$commits" ] && { echo "check-docs-moved: no commits in $mode"; exit 0; }
    for sha in $commits; do
      files="$(git show --name-only --format= "$sha" | sed '/^$/d')" || { echo "✖ git show $sha failed" >&2; exit 3; }
      all="$all"$'\n'"$files"
      if git show -s --format=%B "$sha" | grep -qE "$skip_re"; then
        waived_note="$waived_note"$'\n'"  $(git rev-parse --short "$sha"): $(git show -s --format=%B "$sha" | grep -m1 -E '^Docs-skip:' | cut -c1-80)"
      else
        required="$required"$'\n'"$files"
      fi
    done
    ;;
  *) echo "usage: check-docs-moved.sh <base>..<tip> | --cached" >&2; exit 2 ;;
esac
all="$(printf '%s\n' "$all" | sed '/^$/d' | sort -u)"
required="$(printf '%s\n' "$required" | sed '/^$/d' | sort -u)"
[ -n "$waived_note" ] && echo "check-docs-moved: waived by a Docs-skip trailer, for those commits only:$waived_note" >&2
[ -z "$required" ] && { echo "check-docs-moved: every touched module is covered by a Docs-skip trailer"; exit 0; }

failed=0
matched=""
if [ -f "$map" ]; then
  while IFS='|' read -r code_re docs; do
    case "$code_re" in ''|'#'*) continue ;; esac
    hits="$(printf '%s\n' "$required" | grep -E "$code_re" || true)"
    [ -z "$hits" ] && continue
    matched="$matched"$'\n'"$hits"
    for doc in $docs; do
      if ! printf '%s\n' "$all" | grep -qF "$doc"; then
        echo "✖ code under $(printf '%s' "$code_re" | sed 's/^\^//') changed, but $doc didn't" >&2
        failed=1
      fi
    done
  done < "$map"
fi

mapped="$(printf '%s\n' "$matched" | sed '/^$/d' | sort -u)"
for mod in $(printf '%s\n' "$required" | grep -E "$module_root" | while read -r f; do
    printf '%s\n' "$mapped" | grep -qxF "$f" || printf '%s\n' "$f" | grep -oE "$module_root"
  done | sort -u); do
  echo "✖ module $mod has no line in $map: add its doc under ${DOCS_MODULES_DIR}/ and a map line" >&2
  failed=1
done

if [ "$failed" -ne 0 ]; then
  echo "Update the module doc in the same change. If a commit really needs none," >&2
  echo "give THAT commit a trailer: Docs-skip: <rename|cleanup|refactor|perf|format|tests-only> — <why>" >&2
  exit 1
fi
echo "check-docs-moved: ok"
