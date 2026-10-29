#!/usr/bin/env bash
# The body of every git hook. Each stage reads scripts/agent/agent.conf, so a
# gate changes there (and in docs/GATES.md), never inside .husky/.
#
#   bash scripts/agent/gates.sh pre-commit
#   bash scripts/agent/gates.sh pre-push                 # reads the ref lines git pipes to the hook
#   bash scripts/agent/gates.sh task [low|medium|high]   # /task step 4 on the working tree, at the plan's risk
#   bash scripts/agent/gates.sh finalize [<base>..<tip> | <tip> | --proposed <list>]
#   bash scripts/agent/gates.sh range                    # the <base>..<tip> every range gate would use
#   bash scripts/agent/gates.sh ci                       # the full policy on a CI checkout (FRIDAY_CI_* env)
#
# Exit: 0 every gate passed, 1 a gate failed, 2 bad input, 3 a gate could not run.
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

# The stage comes from the argument, or from ORBIT_STAGE when Orbit's hook shim calls with none.
stage="${1:-${ORBIT_STAGE:-}}"
[ $# -gt 0 ] || set -- "$stage"
# One exit trap: cleanup registered by a stage, then the machine-readable verdict Orbit reads.
FRIDAY_CLEANUP=":"
verdict_line() {
  local rc=$1
  # `range` prints a value, not a verdict.
  [ -n "$stage" ] && [ "$stage" != range ] || return 0
  if [ "$rc" -eq 0 ]; then echo "::friday::verdict status=pass stage=$stage"; else echo "::friday::verdict status=fail stage=$stage exit=$rc"; fi
}
trap 'rc=$?; eval "$FRIDAY_CLEANUP"; verdict_line $rc' EXIT
# A FRIDAY_<KEY> override counts only under a break-glass by a listed developer (below), never in CI or by hand.
case "$stage" in
  pre-commit|pre-push|ci) export FRIDAY_ENV_OVERRIDES=1; friday_load_conf "$0" ;;
esac

# Break-glass: FRIDAY_BREAK_GLASS="<KEY> <reason>" typed by a listed developer skips the gates
# BREAK_GLASS_GATES names (default: everything but the secrets scan and the bot-identity ban),
# says so on every skipped gate, and leaves an audit line. CI runs the full policy regardless.
break_glass=""
if [ -n "${FRIDAY_BREAK_GLASS:-}" ]; then
  case "$stage" in
    pre-commit|pre-push)
      ident="$(git var GIT_AUTHOR_IDENT 2>/dev/null || true)"
      if friday_is_listed "$EXEMPT_IDENTITIES,$BREAK_GLASS_IDENTITIES" "$(friday_ident_name "$ident")" "$(friday_ident_email "$ident")" "$(git config github.user 2>/dev/null || true)"; then
        break_glass="$FRIDAY_BREAK_GLASS"
        key="${break_glass%% *}"
        echo "▸ BREAK-GLASS by $(friday_ident_name "$ident") for $key: ${break_glass#* } — gates in BREAK_GLASS_GATES are skipped; CI re-checks everything, fix within 24 h" >&2
        mkdir -p scripts/agent/state
        line="break-glass: $(friday_ident_name "$ident") $key ${break_glass#* } $(git rev-parse --short HEAD 2>/dev/null || echo none) stage=$stage"
        printf '%s\n' "$line" >> scripts/agent/state/break-glass.log
        friday_audit "$line"
        [ ! -f "docs/qa/$key.md" ] || printf '%s\n' "$line" >> "docs/qa/$key.md"
      else
        echo "✖ FRIDAY_BREAK_GLASS is set, but $(friday_ident_name "$ident") is not in EXEMPT_IDENTITIES or BREAK_GLASS_IDENTITIES: the gates run" >&2
      fi
      ;;
  esac
fi
# A FRIDAY_<KEY> override counts only inside a break-glass by a listed developer; the conf was loaded before
# that was known, so the overrides apply now, and every script this run starts sees the same decision.
if [ -n "$break_glass" ]; then
  export FRIDAY_BREAK_GLASS_OK=1
  friday_apply_env_overrides
fi
# never_skipped <label>: the gates break-glass can never remove.
never_skipped() {
  case "$BREAK_GLASS_GATES" in
    all-but:*) printf '%s\n' "${BREAK_GLASS_GATES#all-but:}" | tr ',' '\n' | grep -qx "$1" ;;
    *) printf '%s\n' "$BREAK_GLASS_GATES" | tr ',' '\n' | grep -qx "$1" && return 1 || return 0 ;;
  esac
}

# gate <label> <command…>: an empty command is a stage this repo does not have. A
# friday script that exits 2 or 3 did not judge anything: that is never a pass.
# gate_role <label>: who owns the gate, for the record Orbit keeps (pd · dev · qa · sec · ops).
gate_role() {
  case "$1" in
    *secret*) echo sec ;;
    *docs*|*file\ cap*) echo pd ;;
    *test*) echo qa ;;
    *size*|*audit*|*env*) echo ops ;;
    *) echo dev ;;
  esac
}
gate_line() { printf '::friday::gate name="%s" status=%s role=%s ms=%s\n' "$1" "$2" "$(gate_role "$1")" "$3"; }
gate() {
  local label="$1"; shift
  local cmd="$*" rc t0
  [ -z "$cmd" ] && { gate_line "$label" skip 0; return 0; }
  if [ -n "$break_glass" ]; then
    local tag=""
    case "$label" in *secret*) tag=secrets ;; *commits*) tag=bot-identity ;; esac
    if [ -z "$tag" ] || ! never_skipped "$tag"; then
      echo "▸ $label: skipped (break-glass ${break_glass%% *})"
      gate_line "$label" skip 0
      return 0
    fi
    # The commit check keeps only its identity half under break-glass.
    [ "$tag" != bot-identity ] || cmd="FRIDAY_IDENTITY_ONLY=1 $cmd"
  fi
  echo "▸ $label"
  t0=$(date +%s)
  (eval "$cmd") </dev/null; rc=$?
  if [ "$rc" -eq 0 ]; then gate_line "$label" pass $(( ($(date +%s) - t0) * 1000 )); return 0; fi
  gate_line "$label" fail $(( ($(date +%s) - t0) * 1000 ))
  case "$cmd" in
    *bash\ scripts/*) if [ "$rc" -ne 1 ]; then echo "✖ $label could not run (exit $rc): $cmd" >&2; exit "$rc"; fi ;;
  esac
  echo "✖ $label failed: $cmd" >&2
  exit 1
}

# Joined to Orbit but called by husky, not by Orbit's shim (which sets ORBIT_STAGE): a `pnpm install` runs
# husky's prepare and resets core.hooksPath to .husky/_, so Orbit's gates run from here too and never drop out.
orbit_chain() {
  [ "$ORBIT" = 1 ] && [ -z "${ORBIT_STAGE:-}" ] || return 0
  local root; root="$(git config --get orbit.root 2>/dev/null || true)"
  [ -n "$root" ] && [ -f "$root/bin/orbit.js" ] || return 0
  echo "▸ Orbit gates (core.hooksPath is not Orbit's; re-wire with: orbit hooks install)"
  if [ "$1" = pre-push ]; then ORBIT_ROOT="$root" node "$root/bin/orbit.js" hook pre-push --refs "$2" || exit $?
  else ORBIT_ROOT="$root" node "$root/bin/orbit.js" hook "$1" || exit $?; fi
}

# The push receipt: a note on each pushed tip in refs/notes/friday-gates, pushed beside the branch. CI no longer
# runs lint, typecheck or tests, so it reads this note to know they ran here; a push with hooks off leaves none.
push_receipt() {
  local remote="${FRIDAY_PUSH_REMOTE:-origin}" who tip ref=refs/notes/friday-gates
  who="$(git config user.email 2>/dev/null || echo unknown)"
  git fetch -q "$remote" "+$ref:refs/notes/friday-gates-remote" 2>/dev/null || true
  if git rev-parse -q --verify refs/notes/friday-gates-remote >/dev/null; then
    git notes --ref=friday-gates merge -q -s cat_sort_uniq refs/notes/friday-gates-remote 2>/dev/null || true
  fi
  while read -r _l tip _r _s; do
    [ -n "$tip" ] && ! printf '%s\n' "$tip" | grep -qE '^0+$' || continue
    git notes --ref=friday-gates add -f -m "${1:-pass} $tip lint typecheck tests build audit $(date -u +%Y-%m-%dT%H:%MZ) $who" "$tip"
  done < "$2"
  FRIDAY_NOTES_PUSH=1 git push -q "$remote" "$ref" 2>/dev/null \
    && echo "▸ push receipt: recorded for CI" \
    || echo "▸ push receipt: could not push $ref; CI will ask for a re-push" >&2
}

# The whole-tree gates every push-shaped stage ends with, in one order.
tree_gates() {
  gate "lint" "$GATE_LINT"
  gate "typecheck" "$GATE_TYPES"
}
release_gates() {
  gate "build" "$GATE_BUILD"
  # What ships is public: an .env value or a key the bundler inlined fails here (build-scan.sh, SOURCE_MAPS).
  if [ -n "$GATE_BUILD" ] && [ "$BUILD_SCAN" = block ] && [ "$FRIDAY_CONF_CI" != off ]; then
    gate "secrets in the build" "bash scripts/agent/build-scan.sh"
  fi
  gate "size budgets" "$GATE_SIZE"
  gate "dependency audit" "$GATE_AUDIT"
  # Any severity counts; an ignored advisory must be an unfixed, dated exception (audit-check.sh).
  [ -z "$GATE_AUDIT" ] || gate "audit exceptions" "bash scripts/agent/audit-check.sh"
}
full_tests() {
  if [ -z "$GATE_TEST" ]; then echo "▸ tests: disabled (GATE_TEST is empty in scripts/agent/agent.conf)"; return 0; fi
  gate "full test suite" "$GATE_TEST"
}
# The secret scan over a whole range (a secret added and removed inside it still counts) or
# the staged snapshot. GATE_SECRETS names the command; else gitleaks when installed; else a
# notice — CI runs it regardless.
secrets_gate() {
  local range="$1"
  if [ -n "$GATE_SECRETS" ]; then
    gate "secret scan" "$GATE_SECRETS"
  elif command -v gitleaks >/dev/null 2>&1; then
    if [ "$range" = --staged ]; then
      gate "secret scan" "gitleaks git --no-banner --pre-commit --staged"
    else
      export FRIDAY_GATE_RANGE="$range"
      gate "secret scan" 'gitleaks git --no-banner --log-opts="$FRIDAY_GATE_RANGE"'
    fi
  else
    echo "▸ secret scan: gitleaks not installed — CI is the net (brew install gitleaks)"
  fi
}
# The policy gates on one committed range, in the pre-push order. The branch and the range reach each gate
# through the environment, expanded by the gate itself: a branch name is never part of a shell string.
range_gates() {
  export FRIDAY_GATE_BRANCH="$1" FRIDAY_GATE_RANGE="$2"
  gate "branch name" 'bash scripts/git/check-branch.sh "$FRIDAY_GATE_BRANCH"'
  gate "commits being pushed" 'bash scripts/git/check-commit-range.sh "$FRIDAY_GATE_BRANCH" "$FRIDAY_GATE_RANGE"'
  secrets_gate "$2"
  gate "code rules on the range" 'bash scripts/agent/scan-diff.sh "$FRIDAY_GATE_RANGE"'
  gate "file cap" 'bash scripts/git/check-file-cap.sh "$FRIDAY_GATE_RANGE"'
  gate "docs moved with the code" 'bash scripts/git/check-docs-moved.sh "$FRIDAY_GATE_RANGE"'
  # A package new to the lockfile is judged before any advisory exists for it (deps-check.mjs).
  if [ "$DEPS_CHECK" = block ] && [ "$PM" = pnpm ] && [ "$FRIDAY_CONF_CI" != off ] && [ -f pnpm-lock.yaml ]; then
    export DEPS_LICENSES DEPS_EXCEPTIONS AUDIT_EXCEPTION_MAX_DAYS
    gate "new dependencies" 'node scripts/agent/deps-check.mjs "$FRIDAY_GATE_RANGE"'
  fi
}

case "$stage" in
  pre-commit)
    # Staged files only, then the whole tree's types. The tree-wide lint cap,
    # the changed files' tests and the build run at pre-push.
    gate "lint-staged" "$LINT_STAGED_CMD"
    secrets_gate --staged
    gate "code rules on the staged lines" "bash scripts/agent/scan-diff.sh --cached"
    gate "file cap" "$FILE_CAP_CMD"
    gate "typecheck" "$GATE_TYPES"
    orbit_chain pre-commit
    ;;
  pre-push)
    # The receipt's own push (push_receipt): nothing to check, and no gates to run again.
    [ -z "${FRIDAY_NOTES_PUSH:-}" ] || exit 0
    # The ref lines arrive on stdin, or in FRIDAY_PUSH_REFS when a chained hook
    # read stdin first. Each ref gets its own range: the commits it adds over the
    # target, so history already on the default branch is never judged again.
    refs="$(mktemp)"; FRIDAY_CLEANUP="rm -f '$refs'"
    if [ -n "${FRIDAY_PUSH_REFS:-}" ] && [ -f "$FRIDAY_PUSH_REFS" ]; then
      cat "$FRIDAY_PUSH_REFS" > "$refs"
    elif [ ! -t 0 ]; then
      cat > "$refs"
    fi
    zero='^0+$'
    ranges=""
    while read -r _local_ref local_sha remote_ref remote_sha; do
      [ -n "$local_sha" ] || continue
      if printf '%s\n' "$local_sha" | grep -qE "$zero"; then
        echo "▸ deleting $remote_ref: nothing to check"
        continue
      fi
      case "$remote_ref" in refs/heads/*) ;; *) continue ;; esac
      branch="${remote_ref#refs/heads/}"
      pushed=""
      if ! printf '%s\n' "$remote_sha" | grep -qE "$zero"; then
        # The remote tip may not be fetched yet: fetch it, so the range is what the remote will see.
        git cat-file -e "$remote_sha^{commit}" 2>/dev/null || git fetch -q "${FRIDAY_PUSH_REMOTE:-origin}" "$remote_sha" 2>/dev/null || true
        git cat-file -e "$remote_sha^{commit}" 2>/dev/null && pushed="$remote_sha"
      fi
      if printf '%s\n' "$remote_sha" | grep -qE "$zero" && [ "$branch" = "$DEFAULT_BRANCH" ]; then
        # The one push allowed to the default branch: the one that creates it on the remote (its sha is all
        # zeros). It carries the scaffold commit, which has no ticket. A tip that merely was not fetched is not that.
        echo "▸ creating $branch on the remote: branch and commit checks skipped this once"
        continue
      fi
      if [ -n "$pushed" ] && ! git merge-base --is-ancestor "$pushed" "$local_sha"; then
        echo "▸ force push to $branch: the policy runs on the new history"
      fi
      range="$(friday_range "$local_sha" "$pushed")" || exit 1
      echo "▸ $branch: $range"
      # Commits already merged into the remote integration or production branch were judged by their PR; every
      # other commit in the range is checked, including one that reached a temp branch without the hooks.
      export FRIDAY_UNPUSHED_ONLY=1
      range_gates "$branch" "$range"
      unset FRIDAY_UNPUSHED_ONLY
      ranges="$ranges"$'\n'"$range"
    done < "$refs"
    tree_gates
    # TEST_SCOPE=full: the whole suite once per push (CI runs no tests, so this is where all of them run);
    # own/related: only the tests of what each pushed range changed.
    if [ "${TEST_SCOPE:-full}" = full ]; then
      full_tests
    else
      while read -r range; do
        [ -z "$range" ] && continue
        export FRIDAY_GATE_RANGE="$range"
        gate "$( [ "$TEST_SCOPE" = related ] && echo "changed files' tests (own + related)" || echo "changed files' own tests")" 'bash scripts/agent/test-changed.sh "$FRIDAY_GATE_RANGE"'
      done <<< "$ranges"
    fi
    release_gates
    orbit_chain pre-push "$refs"
    # Last, once every gate passed: a push stopped by a later gate leaves no receipt. Under Orbit's shim (ORBIT_STAGE)
    # Orbit's gates run after this script, so Orbit writes the receipt there.
    [ -n "${ORBIT_STAGE:-}" ] || push_receipt "$( [ -n "$break_glass" ] && echo "break-glass-${break_glass%% *}" || echo pass)" "$refs"
    ;;
  task)
    # The /task gates on the working tree, cheapest first; the plan's risk adds
    # the changed files' tests and the build (medium) and the suite (high).
    risk="${2:-low}"
    case "$risk" in
      low|medium|high) ;;
      *) echo "usage: gates.sh task [low|medium|high]" >&2; exit 2 ;;
    esac
    gate "code rules on the working tree" "bash scripts/agent/scan-diff.sh HEAD"
    gate "typecheck" "$GATE_TYPES"
    gate "lint" "$GATE_LINT"
    if [ "$risk" != low ]; then
      gate "changed files' own tests" "bash scripts/agent/test-changed.sh HEAD"
      gate "build" "$GATE_BUILD"
    fi
    if [ "$risk" = high ]; then full_tests; fi
    ;;
  finalize)
    # The /finalize hard checks. Stage 1 judges the proposed commit (the index
    # plus the listed new files); stage 2 judges the committed range. A missing
    # target is a failure, never "skipped".
    shift
    mode="${1:-}"
    branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"
    key="$(friday_ticket_of "$branch")"; [ -n "$key" ] || key="$(printf '%s' "${branch:-detached}" | tr '/' '-')"
    state="scripts/agent/state/$key.md"
    if [ "$mode" = --proposed ]; then
      # Stage 1. <list> is the approved file set: every path /task owns plus what the
      # developer named. The snapshot is a temp index = the index + those paths, judged
      # in a detached worktree, so an unstaged fix can never validate broken staged content.
      list="${2:-}"
      [ -n "$list" ] && [ -f "$list" ] || { echo "usage: gates.sh finalize --proposed <file listing the approved paths>" >&2; exit 2; }
      approved="$(sed '/^$/d' "$list" | sort -u)"
      staged="$(git diff --cached --name-only | sort -u)"
      foreign="$(comm -23 <(printf '%s\n' "$staged") <(printf '%s\n' "$approved") | sed '/^$/d')"
      if [ -n "$foreign" ]; then
        echo "✖ the index holds paths outside the approved set:" >&2
        printf '%s\n' "$foreign" | sed 's/^/    /' >&2
        echo "  include: add them to the list and run again · unstage: git restore --staged -- <path>" >&2
        exit 1
      fi
      snapshot="$(mktemp -d)"
      FRIDAY_CLEANUP="rm -rf '$snapshot'; [ -z \"\${wt:-}\" ] || git worktree remove --force \"\$wt\" >/dev/null 2>&1"
      cp "$(git rev-parse --git-path index)" "$snapshot/index"
      export GIT_INDEX_FILE="$snapshot/index"
      # What is staged is the proposal as it stands; only an approved path NOT yet in the
      # index is taken from the working tree (a new file, or one /task edited and never staged).
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        printf '%s\n' "$staged" | grep -qxF -- "$f" && continue
        if [ -e "$f" ] || git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
          git add -A -- "$f" || { echo "✖ git add $f failed" >&2; exit 3; }
        else
          echo "✖ approved path does not exist: $f" >&2; exit 2
        fi
      done <<< "$approved"
      [ -n "$(git diff --cached --name-only)" ] || { echo "✖ nothing to finalize: the approved set changes nothing" >&2; exit 1; }
      fp="$(bash scripts/agent/fingerprint.sh)" || exit 3
      short="$(bash scripts/agent/fingerprint.sh --short)"
      echo "▸ proposed commit: $(git diff --cached --name-only | wc -l | tr -d ' ') files · fingerprint $short"
      export FRIDAY_GATE_BRANCH="$branch"
      gate "branch name" 'bash scripts/git/check-branch.sh "$FRIDAY_GATE_BRANCH"'
      gate "code rules on the proposed commit" "bash scripts/agent/scan-diff.sh --cached"
      gate "file cap" "bash scripts/git/check-file-cap.sh --cached"
      gate "docs moved with the code" "bash scripts/git/check-docs-moved.sh --cached"
      tree="$(git write-tree)" || exit 3
      unset GIT_INDEX_FILE
      wt="$(mktemp -d)"
      git worktree add --detach --quiet "$wt" HEAD || { echo "✖ git worktree add failed" >&2; exit 3; }
      (cd "$wt" && git read-tree -m -u "$tree") || { echo "✖ could not materialise the snapshot" >&2; exit 3; }
      [ ! -e node_modules ] || ln -s "$FRIDAY_ROOT/node_modules" "$wt/node_modules"
      for env in .env .env.local; do [ ! -f "$env" ] || cp "$env" "$wt/$env"; done
      echo "▸ snapshot checked out at $wt"
      (
        cd "$wt" || exit 3
        . scripts/agent/lib.sh; friday_load_conf scripts/agent/gates.sh
        tree_gates
        gate "changed files' own tests" "bash scripts/agent/test-changed.sh --cached"
        release_gates
      ) || exit $?
      mkdir -p "$(dirname "$state")"
      { [ ! -f "$state" ] || grep -v '^fingerprint: ' "$state"; printf 'fingerprint: %s\n' "$fp"; } > "$state.tmp" && mv "$state.tmp" "$state"
      { grep -v '^verdict: ' "$state"; printf 'verdict: stage1 pass %s %s\n' "$short" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$state.tmp" && mv "$state.tmp" "$state"
      friday_audit "finalize stage1 pass $key $short"
      echo "finalize: stage 1 passed · fingerprint $short recorded in $state"
      exit 0
    fi
    [ $# -le 1 ] || { echo "usage: gates.sh finalize [<base>..<tip> | <tip> | --proposed <list>]" >&2; exit 2; }
    case "$mode" in
      '') range="$(friday_range)" || exit 1 ;;
      *..*) friday_check_range "$mode" || exit 2; range="$mode" ;;
      *)
        # Stage 2: the committed sha against the stage-1 fingerprint, then every gate again.
        sha="$(friday_resolve "$mode")" || exit 2
        range="$(friday_range "$sha")" || exit 1
        recorded="$([ -f "$state" ] && sed -n 's/^fingerprint: //p' "$state" | tail -1 || true)"
        if [ -n "$recorded" ]; then
          now="$(bash scripts/agent/fingerprint.sh --tree "$sha^" "$sha")" || exit 3
          pick() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }
          if [ "$(pick "$recorded" tip)" = "$(git rev-parse "$sha^")" ] &&
             [ "$(pick "$recorded" content)" = "$(pick "$now" content)" ] &&
             [ "$(pick "$recorded" policy)" = "$(pick "$now" policy)" ]; then
            echo "▸ $(git rev-parse --short "$sha") matches the stage-1 fingerprint; the code rules run on the committed range anyway"
          else
            echo "✖ content changed since the stage-1 check (a hook rewrote a file, or the commit differs): every gate runs again" >&2
          fi
        else
          echo "▸ no stage-1 fingerprint in $state: every gate runs on the committed range"
        fi
        ;;
    esac
    echo "▸ range: $range"
    range_gates "$branch" "$range"
    tree_gates
    gate "changed files' own tests" "bash scripts/agent/test-changed.sh $range"
    release_gates
    if [ -f "$state" ]; then
      { grep -v '^verdict: ' "$state"; printf 'verdict: stage2 pass %s %s\n' "$(git rev-parse --short "${range##*..}" 2>/dev/null || echo HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$state.tmp" && mv "$state.tmp" "$state"
    fi
    friday_audit "finalize stage2 pass $key $range"
    ;;
  range)
    friday_range "${2:-HEAD}" || exit 1
    ;;
  ci)
    # One run on a CI checkout: the range the event names (FRIDAY_CI_BASE_SHA ..
    # FRIDAY_CI_HEAD_SHA) or the branch's range, then every whole-tree gate.
    tip="${FRIDAY_CI_HEAD_SHA:-HEAD}"
    friday_resolve "$tip" >/dev/null || exit 2
    branch="${FRIDAY_CI_BRANCH:-$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')}"
    if [ -n "${FRIDAY_CI_BASE_SHA:-}" ] && ! printf '%s\n' "$FRIDAY_CI_BASE_SHA" | grep -qE '^0+$'; then
      friday_resolve "$FRIDAY_CI_BASE_SHA" >/dev/null || exit 2
      range="$(git merge-base "$FRIDAY_CI_BASE_SHA" "$tip")..$tip"
    else
      range="$(friday_range "$tip")" || exit 1
    fi
    echo "▸ range: $range"
    [ ! -f scripts/agent/env-check.sh ] || gate "env example parity" "bash scripts/agent/env-check.sh --example-only"
    if [ "$branch" = "$DEFAULT_BRANCH" ] || [ -z "$branch" ]; then
      echo "▸ on $DEFAULT_BRANCH: branch and commit checks do not apply"
      secrets_gate "$range"
      gate "code rules on the range" "bash scripts/agent/scan-diff.sh $range"
    else
      range_gates "$branch" "$range"
    fi
    # The runner is too small for them; they run at push time, and CI checks the push receipt instead.
    echo "▸ lint, typecheck: run at push time (pre-push), not in CI"
    # CI_TESTS=0: the tests ran at push time (the whole suite with TEST_SCOPE=full), not here.
    if [ "${CI_TESTS:-1}" = 1 ]; then full_tests; else echo "▸ tests: run at push time (pre-push, TEST_SCOPE=${TEST_SCOPE:-full}), not in CI"; fi
    release_gates
    ;;
  *)
    echo "usage: gates.sh pre-commit | pre-push | task [low|medium|high] | finalize [<base>..<tip> | <tip> | --proposed <list>] | range | ci   (or ORBIT_STAGE=<stage> with no argument)" >&2
    exit 2
    ;;
esac
