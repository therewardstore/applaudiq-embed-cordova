#!/usr/bin/env bash
# The repo's state as one JSON object, for `orbit status --json`, `orbit doctor` and any
# dashboard: what session-check knows, plus the install, the last finalize fingerprint and
# verdict, the ship state and the env check. Reads only; always exits 0.
#
#   bash scripts/agent/status.sh --json
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

[ "${1:-}" = --json ] || { echo "usage: status.sh --json (the text form is session-check.sh)" >&2; exit 2; }
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
sha="$(git rev-parse HEAD 2>/dev/null || echo none)"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
key="$(friday_ticket_of "$branch")"; [ -n "$key" ] || key="$(printf '%s' "$branch" | tr '/' '-')"
state="scripts/agent/state/$key.md"
version="$(sed -n 's/^# version: //p' scripts/agent/agent.manifest 2>/dev/null | head -1)"
playbook="$(cat scripts/agent/playbook-version 2>/dev/null)"
hooks_path="$(git config core.hooksPath 2>/dev/null || true)"
drift="$(bash scripts/agent/session-check.sh </dev/null 2>/dev/null | grep -c '^  - ' || true)"
fingerprint="$(sed -n 's/^fingerprint: //p' "$state" 2>/dev/null | tail -1)"
short=""
[ -z "$fingerprint" ] || short="$(printf '%s\n' "$fingerprint" | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -c1-12)"
verdict="$(sed -n 's/^verdict: //p' "$state" 2>/dev/null | tail -1)"
ship="$(sed -n 's/^ship: //p' "$state" 2>/dev/null | tail -1)"
env_state=unknown
if [ -f scripts/agent/env-check.sh ]; then
  if bash scripts/agent/env-check.sh --quiet </dev/null >/dev/null 2>&1; then env_state=ok; else env_state=drift; fi
fi
node -e '
const [repo, branch, sha, dirty, key, version, playbook, hooks, hooksPath, drift, short, verdict, ship, env, profile, orbit, taskMode, defaultBranch, productionRef] = process.argv.slice(1);
process.stdout.write(JSON.stringify({
  repo, branch, sha, dirty: Number(dirty), key,
  friday: { version, playbook, profile, orbit: orbit === "1", taskMode },
  branches: { default: defaultBranch, production: productionRef },
  hooks: { mode: hooks, path: hooksPath || null },
  drift: Number(drift),
  finalize: { fingerprint: short || null, verdict: verdict || null },
  ship: ship || null,
  env: env,
}) + "\n");' \
  "$REPO_NAME" "$branch" "$sha" "$dirty" "$key" "$version" "$playbook" "$HOOKS" "$hooks_path" "$drift" "$short" "$verdict" "$ship" "$env_state" "$PROFILE" "$ORBIT" "$TASK_MODE" "$DEFAULT_BRANCH" "$PRODUCTION_REF"
exit 0
