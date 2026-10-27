#!/usr/bin/env bash
# The test gate the pre-push hook, /task and /finalize share. TEST_SCOPE=own runs the changed
# files' own tests; TEST_SCOPE=related (Vitest) also runs every test importing them (`vitest related`),
# for repos whose CI runs no tests (CI_TESTS=0). Never the full suite.
# A changed source file the coverage config measures fails without a test and is
# held to COVERAGE_MIN per file; REQUIRE_OWN_TEST=0 / COVERAGE_MIN='' turn that off.
# TEST_FILES_CMD names the runner; an empty GATE_TEST means this repo has no test
# stage and every caller skips this script with a notice.
#
#   test-changed.sh                 # the working tree against HEAD
#   test-changed.sh --cached        # the staged files
#   test-changed.sh <base>..<tip>   # a commit range
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

if [ -z "$GATE_TEST" ] || [ -z "$TEST_FILES_CMD" ]; then
  echo "▸ tests: disabled (GATE_TEST is empty in scripts/agent/agent.conf)"
  exit 0
fi

mode="${1:-HEAD}"
case "$mode" in
  HEAD)
    changed="$( { git diff HEAD --name-only --diff-filter=ACMR && git ls-files --others --exclude-standard; } )" || { echo "✖ git diff HEAD failed" >&2; exit 3; } ;;
  --cached)
    changed="$(git diff --cached --name-only --diff-filter=ACMR)" || { echo "✖ git diff --cached failed" >&2; exit 3; } ;;
  *..*)
    friday_check_range "$mode" || exit 2
    changed="$(git diff --name-only --diff-filter=ACMR "$mode")" || { echo "✖ git diff $mode failed" >&2; exit 3; } ;;
  *) echo "usage: test-changed.sh [HEAD | --cached | <base>..<tip>]" >&2; exit 2 ;;
esac

src="$(printf '%s\n' "$changed" | sed '/^$/d' | sort -u | grep -E '^src/.*\.tsx?$' | while read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)"
is_test='(__tests__/|\.(test|spec)\.tsx?$)'
tests="$(printf '%s\n' "$src" | grep -E "$is_test" || true)"
measured="$(printf '%s\n' "$src" | grep -vE "$is_test" | grep -vE "$NOT_MEASURED_RE" || true)"

if [ -z "$src" ]; then
  echo "test-changed: no src/ TypeScript files changed; nothing to test"
  exit 0
fi

missing=()
for f in $measured; do
  dir="$(dirname "$f")"; name="$(basename "$f")"; name="${name%.*}"
  own="$(ls "$dir/__tests__/$name".test.ts "$dir/__tests__/$name".test.tsx "$dir/__tests__/$name".*.test.ts "$dir/__tests__/$name".*.test.tsx \
           "$dir/$name".test.ts "$dir/$name".test.tsx "$dir/$name".spec.ts "$dir/$name".spec.tsx 2>/dev/null || true)"
  if [ -z "$own" ]; then
    [ "$REQUIRE_OWN_TEST" = 1 ] && missing+=("$f")
    continue
  fi
  tests="$tests"$'\n'"$own"
done
if [ "${#missing[@]}" -gt 0 ]; then
  for f in "${missing[@]}"; do
    echo "✖ no test for $f — expected $(dirname "$f")/__tests__/$(basename "${f%.*}").test.${f##*.} (or $(basename "${f%.*}").test.${f##*.} beside it)"
  done
  exit 1
fi
tests="$(printf '%s\n' "$tests" | sed '/^$/d' | sort -u)"
count() { printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '; }
# related: Vitest walks the import graph from every changed file, so a changed file without a test
# of its own still runs the tests of the files that use it; the own-test rule above still applies.
if [ "${TEST_SCOPE:-own}" = related ]; then
  case "$TEST_FILES_CMD" in
    *"vitest run"*)
      cmd="${TEST_FILES_CMD/vitest run/vitest related --run --passWithNoTests}"
      echo "test-changed: tests of $(count "$src") changed file(s) and of every file importing them (vitest related)"
      if [ -n "$COVERAGE_MIN" ] && [ -n "$measured" ]; then
        args=()
        for f in $measured; do args+=(--coverage.include="$f"); done
        # shellcheck disable=SC2086
        exec $cmd $src --coverage --coverage.reporter=text --coverage.thresholds.perFile \
          --coverage.thresholds.statements="$COVERAGE_MIN" --coverage.thresholds.branches="$COVERAGE_MIN" \
          --coverage.thresholds.functions="$COVERAGE_MIN" --coverage.thresholds.lines="$COVERAGE_MIN" "${args[@]}"
      fi
      # shellcheck disable=SC2086
      exec $cmd $src ;;
    *) echo "▸ TEST_SCOPE=related needs a vitest TEST_FILES_CMD; running the changed files' own tests" ;;
  esac
fi
if [ -z "$tests" ]; then
  echo "test-changed: the changed files are not measured and no test changed; nothing to test"
  exit 0
fi

# Coverage flags are vitest's; another runner gets the test files only.
vitest=0; case "$TEST_FILES_CMD" in *vitest*) vitest=1 ;; esac
if [ -z "$COVERAGE_MIN" ] || [ -z "$measured" ] || [ "$vitest" = 0 ]; then
  echo "test-changed: $(count "$tests") test file(s) for $(count "$src") changed file(s)"
  # shellcheck disable=SC2086
  exec $TEST_FILES_CMD $tests
fi
echo "test-changed: $(count "$tests") test file(s) for $(count "$src") changed file(s); $(count "$measured") held to ${COVERAGE_MIN}% coverage"
args=()
for f in $measured; do args+=(--coverage.include="$f"); done
# One --coverage.include per file, thresholds applied per file: a comma-joined
# include list silently matches nothing, and an aggregate lets one weak file hide.
# shellcheck disable=SC2086
exec $TEST_FILES_CMD $tests --coverage --coverage.reporter=text --coverage.thresholds.perFile \
  --coverage.thresholds.statements="$COVERAGE_MIN" --coverage.thresholds.branches="$COVERAGE_MIN" \
  --coverage.thresholds.functions="$COVERAGE_MIN" --coverage.thresholds.lines="$COVERAGE_MIN" "${args[@]}"
