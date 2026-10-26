#!/usr/bin/env bash
# Env parity: every key src/config/env.ts reads is in .env.example; every key .env.example
# lists is in .env (with a value when env.ts requires it); nothing in the example that the
# code no longer reads; remote ports agree with orbit.json when there is one; no design
# system linked. `trs-app env check` and `agents doctor` run it; CI runs --example-only.
#
#   env-check.sh                 # .env.example and .env against src/config/env.ts
#   env-check.sh --example-only  # CI: the committed files only
#   env-check.sh --quiet         # one line, exit code only (session-check)
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

example_only=0; quiet=0
for a in "$@"; do case "$a" in --example-only) example_only=1 ;; --quiet) quiet=1 ;; esac; done
say() { [ "$quiet" = 1 ] || echo "$1"; }
envts="$(ls src/config/env.ts src/config/env.js 2>/dev/null | head -1)"
[ -n "$envts" ] && [ -f .env.example ] || { say "env-check: no src/config/env.ts or .env.example; nothing to check"; exit 0; }
# Every file allowed to read process.env (HELPER_ENV_FILES): env.ts, remotes.ts, Main.tsx…
helpers="$(printf '%s\n' "$HELPER_ENV_FILES" | tr ',' '\n' | while read -r f; do [ -n "$f" ] && [ -f "$f" ] && printf '%s\n' "$f"; done)"
printf '%s\n' "$helpers" | grep -qx "$envts" || helpers="$envts"$'\n'"$helpers"

failed=0
problem() { echo "✖ $1" >&2; failed=1; }
# RAW mapping lines: `NAME: process.env.APP_NAME,` → NAME<TAB>APP_NAME
mapping="$(grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]*:[[:space:]]*process\.env\.[A-Z][A-Z0-9_]*' "$envts" | sed -E 's/^[[:space:]]*([A-Z0-9_]+):[[:space:]]*process\.env\.([A-Z0-9_]+)/\1\t\2/')"
# shellcheck disable=SC2086
# Comment lines are skipped: env.ts's own doc comment names process.env.APP_FOO as an example.
code_keys="$( { printf '%s\n' "$mapping" | cut -f2; cat $helpers | grep -vE '^[[:space:]]*(//|\*|/\*)' | grep -oE 'process\.env\.[A-Z][A-Z0-9_]*' | sed 's/process\.env\.//'; } | sed '/^$/d' | sort -u)"
# NODE_ENV is the bundler's, never a .env key.
code_keys="$(printf '%s\n' "$code_keys" | grep -vx NODE_ENV || true)"
# A key only the build config reads (a dev proxy target, a deploy marker) is still a real example key.
build_keys="$(cat rspack.config.* vite.config.* next.config.* app.config.* 2>/dev/null | grep -vE '^[[:space:]]*(//|\*|/\*)' | grep -oE 'process\.env\.[A-Z][A-Z0-9_]*' | sed 's/process\.env\.//' | sort -u)"
required_names="$(grep -oE "required\('[A-Z][A-Z0-9_]*'\)" "$envts" | sed -E "s/required\('([A-Z0-9_]+)'\)/\1/" | sort -u)"
# A remote origin read `as string` in remotes.ts is required too: the build throws without it.
required_keys="$( { for n in $required_names; do printf '%s\n' "$mapping" | awk -F'\t' -v n="$n" '$1 == n { print $2 }'; done
  [ ! -f src/config/remotes.ts ] || grep -oE 'process\.env\.[A-Z][A-Z0-9_]* as string' src/config/remotes.ts | sed -E 's/process\.env\.([A-Z0-9_]+) as string/\1/'; } | sed '/^$/d' | sort -u)"
keys_of() { grep -oE '^#? ?[A-Z][A-Z0-9_]*=' "$1" | tr -d '# =' | sort -u; }
example_keys="$(keys_of .env.example)"

for k in $code_keys; do
  printf '%s\n' "$example_keys" | grep -qx "$k" || problem "$k is read by $envts but missing from .env.example"
done
for k in $example_keys; do
  printf '%s\n' "$code_keys" "$build_keys" | grep -qx "$k" || problem "$k is in .env.example but no env helper reads it ($(printf '%s' "$helpers" | tr '\n' ' ')): remove it, or read it"
done

if [ "$example_only" = 0 ]; then
  if [ ! -f .env ]; then
    problem ".env is missing: run trs-app env init"
  else
    env_keys="$(keys_of .env)"
    for k in $example_keys; do
      printf '%s\n' "$env_keys" | grep -qx "$k" || problem "$k is in .env.example but not in .env (trs-app env init --force, or add it)"
    done
    for k in $required_keys; do
      v="$(grep -E "^$k=" .env | tail -1 | cut -d= -f2-)"
      [ -n "$v" ] || problem "$k is required by $envts but empty or unset in .env"
    done
  fi
  # Remote ports agree with the workspace when there is one.
  if [ -f ../orbit.json ] && [ -f .env ]; then
    while IFS=$'\t' read -r key port; do
      [ -n "$key" ] || continue
      actual="$(grep -E "^$key=" .env | tail -1 | grep -oE ':[0-9]+' | tr -d ':' | tail -1)"
      [ -z "$actual" ] || [ "$actual" = "$port" ] || problem "$key points at port $actual; orbit.json says $port"
    done < <(node -e '
      const fs=require("fs"); const o=JSON.parse(fs.readFileSync("../orbit.json","utf8"));
      const env=fs.readFileSync(".env","utf8");
      for (const r of o.repos||[]) { if (!r.port) continue;
        const re=new RegExp("^([A-Z0-9_]*_"+String(r.remoteEnvPrefix||r.name).toUpperCase().replace(/[^A-Z0-9]/g,"_")+"_URL)=","m");
        const m=re.exec(env); if (m) process.stdout.write(m[1]+"\t"+r.port+"\n"); }' 2>/dev/null)
  fi
  if [ -f scripts/ds-link.mjs ]; then
    ds="$(node scripts/ds-link.mjs status 2>/dev/null || true)"
    if printf '%s' "$ds" | grep -qiE '\blinked\b' && ! printf '%s' "$ds" | grep -qiE 'not linked|unlinked'; then
      say "▸ a design system is linked from a local checkout (pnpm ds:link); it must not reach a commit or CI"
    fi
  fi
fi

if [ "$failed" = 0 ]; then
  say "env-check: ok ($(printf '%s\n' "$example_keys" | sed '/^$/d' | wc -l | tr -d ' ') keys, $(printf '%s\n' "$required_keys" | sed '/^$/d' | wc -l | tr -d ' ') required)"
  exit 0
fi
exit 1
