#!/usr/bin/env bash
# Sourced by every script under scripts/agent and scripts/git. Finds the repo
# root, loads scripts/agent/agent.conf, and fills in a default for any key an
# older conf lacks, so a re-run of `trs-app agents upgrade` can add keys safely.
#
#   . "$(dirname "$0")/../agent/lib.sh"; friday_load_conf "$0"
#
# Exit codes every script shares: 1 = a policy failed, 2 = bad input (usage, an
# unknown revision), 3 = git or a tool could not run. Nothing passes by accident.
#
# Precedence, lowest to highest: these defaults → detection at init → agent.conf →
# FRIDAY_<KEY> in the environment (hooks and CI only, each one logged) → a flag.

# Every key, in agent.conf order. `trs-app agents status` and the env overrides read it.
FRIDAY_CONF_KEYS='PM GATE_TYPES GATE_LINT GATE_TEST GATE_BUILD GATE_SIZE GATE_AUDIT TEST_FILES_CMD LINT_STAGED_CMD FILE_CAP FILE_CAP_CMD HOOKS TICKET_PREFIXES DEFAULT_BRANCH ROUTES_FILE ROUTES_FILE_RE ROUTES_HELPER API_FILES API_FILE_RE API_HELPER API_LITERAL_RE API_HELPER_CALL HELPER_STORAGE_FILES HELPER_ENV_FILES HELPER_NAVIGATION_FILES HELPER_API_FILES LINT_MAX_LINES LINT_MAX_LINES_PER_FUNCTION LANG_DIR MODULES_DIR DOCS_MODULES_DIR COVERAGE_MIN REQUIRE_OWN_TEST NOT_MEASURED_RE COMMENT_MAX_LINES COMMENT_MAX_LEN WIDTHS WARNING_CAP FLEET EXEMPT_IDENTITIES AUTOMATION_IDENTITIES ATTRIBUTION_BAN TICKET_DIGITS THEME_RULE THEME_BRIDGE_FILES REPO_NAME REPO_SLUG PRODUCTION_REF CI CI_WORKFLOWS TASK_MODE TASK_PUSH QA_CONFIRM JIRA_PROJECT JIRA_ISSUE_TYPE JIRA_COMMENT COMPONENT_REGISTRY DS_CANDIDATE_MAX_DAYS ORBIT GATES_HOTFIX GATES_CHANGE GATES_NEW HOTFIX_RULES REVIEW_MODEL REVIEW_EFFORT BREAK_GLASS_IDENTITIES BREAK_GLASS_GATES SIZE_DELTA_MAX_PCT DEP_MAX_KB ASSET_MAX_KB GATE_DEADCODE GATE_DUPLICATES GATE_SECRETS GATE_A11Y GATE_SIZE_DELTA PERF_STRICT REVIEW_RULES REVIEW_STATUS BASELINE_EXPIRES CODEOWNERS_TEAM CONTRACT_REPO PROFILE'

friday_load_conf() {
  local here
  here="$(cd "$(dirname "$1")" && pwd)"
  FRIDAY_ROOT="$(cd "$here/../.." && pwd)"
  cd "$FRIDAY_ROOT" || return 1
  if [ -f scripts/agent/agent.conf ]; then
    # shellcheck disable=SC1091
    . scripts/agent/agent.conf
  fi
  # `${VAR=default}` without the colon: an EMPTY value in the conf is a stage
  # this repo does not have and must survive; only an unset key gets a default.
  : "${FRIDAY_AGENTS_VERSION=0}"
  : "${PM=pnpm}"
  : "${GATE_TYPES=pnpm typecheck}"
  : "${GATE_LINT=pnpm lint}"
  : "${GATE_TEST=pnpm test}"
  : "${GATE_BUILD=pnpm build}"
  : "${GATE_SIZE=}"
  : "${GATE_AUDIT=}"
  : "${TEST_FILES_CMD=pnpm exec vitest run}"
  : "${LINT_STAGED_CMD=}"
  : "${FILE_CAP=2000}"
  : "${FILE_CAP_CMD=bash scripts/git/check-file-cap.sh}"
  : "${HOOKS=husky}"
  : "${TICKET_PREFIXES=TRS|AIQ|INF}"
  : "${DEFAULT_BRANCH=master}"
  : "${ROUTES_FILE=src/routes/appPaths.ts}"
  : "${ROUTES_FILE_RE=src/routes/appPaths\.ts$}"
  : "${ROUTES_HELPER=appPaths}"
  : "${API_FILES=src/routes/apiRoutes.ts}"
  : "${API_FILE_RE=src/routes/apiRoutes\.ts$}"
  : "${API_HELPER=apiRoutes}"
  : "${API_LITERAL_RE=internal|origin/burn|api}"
  : "${API_HELPER_CALL=}"
  : "${HELPER_STORAGE_FILES=src/lib/storage.ts}"
  : "${HELPER_ENV_FILES=src/config/env.ts}"
  : "${HELPER_NAVIGATION_FILES=src/lib/navigation.ts}"
  : "${HELPER_API_FILES=**/store/**,src/routes/**}"
  : "${LINT_MAX_LINES=400}"
  : "${LINT_MAX_LINES_PER_FUNCTION=150}"
  : "${LANG_DIR=}"
  : "${MODULES_DIR=src/modules}"
  : "${DOCS_MODULES_DIR=docs/modules}"
  : "${COVERAGE_MIN=90}"
  : "${REQUIRE_OWN_TEST=1}"
  : "${NOT_MEASURED_RE=(__mocks__/|\.d\.ts$|\.types\.ts$|/index\.ts$|^src/(main|bootstrap|App)\.tsx$|^src/test/|^src/types/)}"
  : "${COMMENT_MAX_LINES=2}"
  : "${COMMENT_MAX_LEN=100}"
  : "${WIDTHS=desktop 1440 · iPad landscape 1180 · iPad portrait 820 · mobile 390}"
  : "${WARNING_CAP=}"
  : "${FLEET=0}"
  : "${EXEMPT_IDENTITIES=}"
  : "${AUTOMATION_IDENTITIES=dependabot[bot],renovate[bot],github-actions[bot]}"
  : "${ATTRIBUTION_BAN=ai}"
  : "${TICKET_DIGITS=4,7}"
  : "${THEME_RULE=1}"
  : "${THEME_BRIDGE_FILES=}"
  : "${REPO_NAME=}"
  : "${REPO_SLUG=}"
  : "${PRODUCTION_REF=}"
  : "${CI=}"
  : "${CI_WORKFLOWS=}"
  : "${TASK_MODE=auto}"
  : "${TASK_PUSH=auto}"
  : "${QA_CONFIRM=advisory}"
  : "${JIRA_PROJECT=}"
  : "${JIRA_ISSUE_TYPE=Task}"
  : "${JIRA_COMMENT=1}"
  : "${COMPONENT_REGISTRY=docs/COMPONENTS.md}"
  : "${DS_CANDIDATE_MAX_DAYS=60}"
  : "${ORBIT=0}"
  : "${GATES_HOTFIX=low}"
  : "${GATES_CHANGE=medium}"
  : "${GATES_NEW=high}"
  : "${HOTFIX_RULES=no-deps,no-migrations,module-scope}"
  : "${REVIEW_MODEL=claude-haiku-5-5}"
  : "${REVIEW_EFFORT=low}"
  : "${BREAK_GLASS_IDENTITIES=}"
  : "${BREAK_GLASS_GATES=all-but:secrets,bot-identity}"
  : "${SIZE_DELTA_MAX_PCT=5}"
  : "${DEP_MAX_KB=50}"
  : "${ASSET_MAX_KB=200}"
  : "${GATE_DEADCODE=}"
  : "${GATE_DUPLICATES=}"
  : "${GATE_SECRETS=}"
  : "${GATE_A11Y=}"
  : "${GATE_SIZE_DELTA=}"
  : "${PERF_STRICT=0}"
  : "${REVIEW_RULES=advisory}"
  : "${REVIEW_STATUS=0}"
  : "${BASELINE_EXPIRES=90}"
  : "${CODEOWNERS_TEAM=FE-Arch-Review}"
  : "${CONTRACT_REPO=}"
  : "${PROFILE=app}"
  friday_apply_env_overrides
  [ -n "$PRODUCTION_REF" ] || PRODUCTION_REF="$DEFAULT_BRANCH"
  [ -n "$REPO_NAME" ] || REPO_NAME="$(basename "$FRIDAY_ROOT")"
  TICKET_RE="(${TICKET_PREFIXES})-[0-9]{${TICKET_DIGITS}}"
  TICKET_HUMAN="$(printf '%s' "$TICKET_PREFIXES" | sed 's/|/-, /g')-"
  TICKET_DIGITS_HUMAN="$(printf '%s' "$TICKET_DIGITS" | sed 's/,/–/') digits"
  # One copy of the bot/AI identity rule. Names are anchored before ` <` so a person
  # called Claude or Gemini passes; the addresses and app names never do.
  BOT_IDENT_RE='\[bot\]|noreply@anthropic\.com|@cursor\.com|cursoragent|github-actions|dependabot|renovate|^(claude( code)?|(openai )?codex( cli)?|gemini( cli)?|antigravity|(github )?copilot) <'
  export FRIDAY_ROOT TICKET_RE TICKET_HUMAN TICKET_DIGITS_HUMAN BOT_IDENT_RE REPO_NAME PRODUCTION_REF
}

# FRIDAY_<KEY> overrides a conf key — only when gates.sh exported FRIDAY_ENV_OVERRIDES=1
# (a hook or CI run), and each override is said out loud once per run.
friday_apply_env_overrides() {
  [ "${FRIDAY_ENV_OVERRIDES:-}" = 1 ] || return 0
  local key val
  for key in $FRIDAY_CONF_KEYS; do
    eval "val=\${FRIDAY_${key}-__unset__}"
    [ "$val" = __unset__ ] && continue
    eval "$key=\$val"
    [ "${FRIDAY_QUIET_OVERRIDES:-}" = 1 ] || echo "▸ $key overridden by FRIDAY_$key for this run" >&2
  done
  export FRIDAY_QUIET_OVERRIDES=1
}

# friday_audit <line>: one line to the repo's audit log, and to the workspace's when ORBIT_ROOT is set.
friday_audit() {
  local line="$(date -u +%Y-%m-%dT%H:%M:%SZ) $REPO_NAME $*"
  mkdir -p scripts/agent/state 2>/dev/null && printf '%s\n' "$line" >> scripts/agent/state/audit.log
  if [ -n "${ORBIT_ROOT:-}" ] && [ -d "$ORBIT_ROOT" ]; then
    mkdir -p "$ORBIT_ROOT/.orbit/log" 2>/dev/null && printf '%s\n' "$line" >> "$ORBIT_ROOT/.orbit/log/friday.log"
  fi
}

# `pnpm run x` / `pnpm x` → x, so a gate can be checked against package.json.
friday_script_name() {
  printf '%s\n' "$1" | sed -E 's/^(pnpm|npm|yarn|bun)( run)? //; s/ .*$//'
}

# ── identities ───────────────────────────────────────────────────────────────
friday_ident_name() { printf '%s\n' "$1" | sed -E 's/ <.*$//'; }
friday_ident_email() { printf '%s\n' "$1" | sed -nE 's/^.*<([^>]*)>.*$/\1/p'; }
# The GitHub login a verified noreply address carries (<id>+<login>@users.noreply.github.com), or nothing.
friday_login_of() {
  case "$1" in *@users.noreply.github.com) printf '%s\n' "${1%@*}" | sed 's/^[0-9]*+//' ;; esac
}
# friday_is_listed <csv> <name> <email> [login]: an exact, case-insensitive match on any of them.
friday_is_listed() {
  local list="$1" name="$2" email="$3" login="${4:-}" item candidate
  [ -n "$list" ] || return 1
  [ -n "$login" ] || login="$(friday_login_of "$email")"
  for candidate in "$name" "$email" "$login"; do
    [ -n "$candidate" ] || continue
    while IFS= read -r item; do
      item="$(printf '%s' "$item" | sed 's/^ *//;s/ *$//')"
      [ -n "$item" ] || continue
      [ "$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')" ] && return 0
    done < <(printf '%s\n' "$list" | tr ',' '\n')
  done
  return 1
}
# The branch-name exemption is keyed on the PUSHER: in CI only the GitHub actor counts;
# locally the git identity and `git config github.user`.
friday_exempt_pusher() {
  [ -n "$EXEMPT_IDENTITIES" ] || return 1
  if [ -n "${FRIDAY_CI_EVENT:-}" ]; then
    friday_is_listed "$EXEMPT_IDENTITIES" "" "" "${FRIDAY_CI_ACTOR:-}"
    return
  fi
  local ident; ident="$(git var GIT_AUTHOR_IDENT 2>/dev/null || true)"
  friday_is_listed "$EXEMPT_IDENTITIES" "$(friday_ident_name "$ident")" "$(friday_ident_email "$ident")" "$(git config github.user 2>/dev/null || true)"
}
# The header/ticket exemption is keyed on EACH COMMIT'S AUTHOR: in CI only a verified
# noreply login is trusted (a forged local name passes locally, fails in CI).
friday_exempt_author() {
  [ -n "$EXEMPT_IDENTITIES" ] || return 1
  if [ -n "${FRIDAY_CI_EVENT:-}" ]; then
    friday_is_listed "$EXEMPT_IDENTITIES" "" "" "$(friday_login_of "$2")"
    return
  fi
  friday_is_listed "$EXEMPT_IDENTITIES" "$1" "$2" "$(git config github.user 2>/dev/null || true)"
}
friday_is_automation() { friday_is_listed "$AUTOMATION_IDENTITIES" "$1" "$2"; }

# ── ranges ───────────────────────────────────────────────────────────────────
# friday_resolve <rev>: the commit sha, or exit 2 with the name of what is unknown.
friday_resolve() {
  local sha
  if ! sha="$(git rev-parse -q --verify "$1^{commit}" 2>/dev/null)"; then
    echo "✖ unknown revision: $1" >&2
    return 2
  fi
  printf '%s\n' "$sha"
}

# friday_target [<tip>] [<pushed-to>]: the ref the change is compared against —
# in CI the base the event names, else origin/DEFAULT_BRANCH, else the sha the
# push goes to, else the upstream, else the local default branch. Exit 1, with
# the fix, when there is nothing at all: a silent pass is never an answer.
friday_target() {
  local tip="${1:-HEAD}" pushed="${2:-}" ref
  if [ -n "${FRIDAY_CI_BASE_SHA:-}" ] && git rev-parse -q --verify "${FRIDAY_CI_BASE_SHA}^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "$FRIDAY_CI_BASE_SHA"
    return 0
  fi
  for ref in "origin/$DEFAULT_BRANCH" "$pushed" "$tip@{u}" "$DEFAULT_BRANCH"; do
    [ -n "$ref" ] || continue
    if git rev-parse -q --verify "${ref}^{commit}" >/dev/null 2>&1; then
      printf '%s\n' "$ref"
      return 0
    fi
  done
  echo "✖ nothing to compare $tip against: no origin/$DEFAULT_BRANCH, no upstream, no local $DEFAULT_BRANCH — run: git fetch origin $DEFAULT_BRANCH, or fix DEFAULT_BRANCH in scripts/agent/agent.conf" >&2
  return 1
}

# friday_range [<tip>] [<pushed-to>]: `<merge-base>..<tip>`, the commits the tip
# adds over the target. One computation for every consumer.
friday_range() {
  local tip="${1:-HEAD}" ref base
  ref="$(friday_target "$tip" "${2:-}")" || return 1
  if ! base="$(git merge-base "$ref" "$tip" 2>/dev/null)"; then
    echo "✖ $ref and $tip share no history" >&2
    return 1
  fi
  printf '%s..%s\n' "$base" "$tip"
}

# friday_check_range <a>..<b>: both ends must resolve; anything else is exit 2.
friday_check_range() {
  case "$1" in
    *..*) ;;
    *) echo "✖ bad range '$1' (want <base>..<tip>, e.g. $(friday_range 2>/dev/null || echo 'origin/master..HEAD'))" >&2; return 2 ;;
  esac
  friday_resolve "${1%%..*}" >/dev/null || return 2
  friday_resolve "${1##*..}" >/dev/null || return 2
}

# friday_commits <a>..<b>: the commits subject to the message and identity rules. At pre-push
# (FRIDAY_UNPUSHED_ONLY=1) a commit already on a remote branch was judged when it went there.
friday_commits() {
  friday_check_range "$1" || return 2
  if [ "${FRIDAY_UNPUSHED_ONLY:-}" = 1 ]; then
    git rev-list --reverse --no-merges "$1" --not --remotes || { echo "✖ git rev-list $1 failed" >&2; return 3; }
  else
    git rev-list --reverse --no-merges "$1" || { echo "✖ git rev-list $1 failed" >&2; return 3; }
  fi
}

# friday_ticket_of <branch>: the ticket at the start of a branch name, or nothing.
friday_ticket_of() {
  printf '%s\n' "$1" | grep -oE "^${TICKET_RE}" || true
}
