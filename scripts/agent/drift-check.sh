#!/usr/bin/env bash
# Every /scan drift check, as code: /scan runs this and reports its lines; it
# adds no check of its own. Prints one line per mismatch, "<check> → <file:line>",
# then "drift-check: <n> checks, drift none|<n>". Exit 1 on drift.
set -uo pipefail
shopt -s nullglob
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"
drift=()
checks=0
# run <function>: a check echoes one line per mismatch; run collects them.
run() { checks=$((checks + 1)); while IFS= read -r l; do [ -n "$l" ] && drift+=("$l"); done < <("$@"); }
# check_number <label> <actual> <doc> <grep -E pattern whose digits are the documented number>: a doc states a number the source owns.
check_number() {
  local label=$1 actual=$2 doc=$3 re=$4
  grep -nE "$re" "$doc" 2>/dev/null | while IFS=: read -r line rest; do
    n="$(printf '%s' "$rest" | grep -oE "$re" | grep -oE '[0-9]+' | head -1)"
    [ "$n" = "$actual" ] || echo "$label: doc says $n, the source has $actual → $doc:$line"
  done
}
# Every doc under docs/ except dated records (ADRs, and files marked superseded or historical).
docs_live() {
  for f in docs/*.md docs/*/*.md; do
    case "$f" in docs/adr/*|docs/decisions/*) continue ;; esac
    head -10 "$f" | grep -qiE '^(status|state): *(superseded|historical|archived)' && continue
    printf '%s\n' "$f"
  done
}

# 1. The cheap checks, from session-check.sh (its "  - " lines); --no-session when
#    session-check itself called us, so the cheap checks never run twice.
if [ "${1:-}" != --no-session ]; then
  checks=$((checks + 1))
  while IFS= read -r l; do drift+=("$l → scripts/agent/session-check.sh"); done < <(bash scripts/agent/session-check.sh </dev/null | sed -n 's/^  - //p')
fi

# 2. The always-on rows.
check_permissions() {  # every tool's committed allow-list covers the repo scripts and the gate commands
  for f in .claude/settings.json .cursor/permissions.json .cursor/cli.json; do
    [ -f "$f" ] || continue  # a missing file is reported by session-check's install manifest
    grep -q 'scripts/agent' "$f" && grep -q 'scripts/git' "$f" || echo "$f does not allow scripts/agent and scripts/git → $f"
  done
  if [ -d .codex ]; then
    rules=(.codex/rules/*.rules)
    [ "${#rules[@]}" -gt 0 ] || return 0  # a missing rules file is reported by the install manifest
    missing=""
    for s in scripts/agent/*.sh scripts/git/*.sh; do
      case "$s" in scripts/agent/lib.sh) continue ;; esac
      grep -qs "\"$s\"" "${rules[@]}" </dev/null || missing="$missing $(basename "$s")"
    done
    [ -z "$missing" ] || echo "Codex has no prefix_rule for$missing → .codex/rules/"
  fi
}
check_docs_index() {  # every live doc has a row in the docs index
  [ -f docs/README.md ] || { echo "docs/README.md is missing → docs/README.md"; return 0; }
  for f in $(docs_live); do
    case "$f" in docs/README.md|"$DOCS_MODULES_DIR"/*) continue ;; esac
    grep -q "$(basename "$f")" docs/README.md || echo "$f is not listed in docs/README.md → docs/README.md"
  done
}
check_modules() {  # every module has a doc, a doc-map row and an inventory entry
  [ -d "$MODULES_DIR" ] || return 0
  for d in "$MODULES_DIR"/*/; do
    m="$(basename "$d")"
    [ -f "$DOCS_MODULES_DIR/$m.md" ] || echo "module $m has no $DOCS_MODULES_DIR/$m.md → $DOCS_MODULES_DIR/"
    grep -q "$m" scripts/git/doc-map.txt 2>/dev/null || echo "module $m has no doc-map row → scripts/git/doc-map.txt"
    grep -q "$m" docs/MODULES.md 2>/dev/null || echo "module $m is not in the inventory → docs/MODULES.md"
  done
}
check_gates() {  # every gate the conf and the always-on docs name is a script in the manifest
  [ -f package.json ] || return 0
  for cmd in "$GATE_TYPES" "$GATE_LINT" "$GATE_TEST" "$GATE_BUILD" "$GATE_SIZE"; do
    [ -z "$cmd" ] && continue
    case "$cmd" in pnpm*|npm*|yarn*|bun*) ;; *) continue ;; esac
    s="$(friday_script_name "$cmd")"
    grep -q "\"$s\":" package.json || echo "agent.conf names \`$cmd\`, which package.json has no script for → scripts/agent/agent.conf"
  done
  for g in $({ grep -ohE '`pnpm (run )?[a-z:-]+`' CLAUDE.md docs/GATES.md; grep -ohE 'pnpm run [a-z:-]+' CLAUDE.md docs/GATES.md; } 2>/dev/null | tr -d '`' | sed -E 's/^pnpm (run )?//' | sort -u); do
    case "$g" in install|dev|create|dlx|exec|add|remove|update|ci|publish|version) continue ;; esac
    grep -q "\"$g\":" package.json || echo "CLAUDE.md or docs/GATES.md names \`pnpm $g\`, which package.json does not have → package.json"
  done
}
check_package_manager() {  # a pnpm repo stays pnpm: no npm or yarn lockfile, no npm/npx/yarn in its scripts
  [ "$PM" = pnpm ] && [ -f package.json ] || return 0
  for lock in package-lock.json yarn.lock; do
    [ -f "$lock" ] && echo "$lock in a pnpm repo (npm or yarn ran here): delete it, pnpm-lock.yaml is the lockfile → $lock"
  done
  node -e 'const s=require("./package.json").scripts||{};for(const[k,v]of Object.entries(s))if(/(^|[\s;&|(])(npm|npx|yarn)\s/.test(v))console.log(k)' 2>/dev/null \
    | while IFS= read -r k; do echo "package.json script \"$k\" calls npm, npx or yarn: use pnpm run or pnpm exec → package.json"; done
}
check_runner() {  # every workflow job runs on the org runner (CI_RUNNER), never on GitHub's runners
  grep -lsE '^\s*runs-on:.*(ubuntu|windows|macos)-' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null \
    | while IFS= read -r f; do echo "$f runs a job on a GitHub runner: use runs-on: ${CI_RUNNER} (CI_RUNNER) → $f"; done
}
check_eslint_fragment() {  # the generated selectors are actually spread into the lint config
  [ -f scripts/agent/eslint-rules.mjs ] || return 0
  ls eslint.config.* >/dev/null 2>&1 || return 0
  grep -q 'eslint-rules.mjs' eslint.config.* || { echo "eslint.config does not import scripts/agent/eslint-rules.mjs: the lint set is off → eslint.config"; return 0; }
  grep -qE '\boverrides\(' eslint.config.* || echo "eslint.config predates the v12 lint set: spread agent.rules, agent.settings, agent.linterOptions and agent.overrides(yourSelectors) from scripts/agent/eslint-rules.mjs → eslint.config"
}
check_skill_length() {  # the commands stay short enough to read every time (task and finalize shorter still)
  for name in scan task finalize handoff flow review; do
    f=".claude/skills/$name/SKILL.md"
    [ -f "$f" ] || continue
    n="$(wc -l < "$f" | tr -d ' ')"
    cap=200; case "$name" in task|finalize) cap=160 ;; esac
    [ "$n" -le "$cap" ] || echo "$f is $n lines; keep it under $cap → $f"
  done
}
check_components() {  # a DS candidate does not age in the registry; a missing theme bridge file is a stale exception
  if [ -f "$COMPONENT_REGISTRY" ]; then
    grep -E '^\| *[A-Za-z0-9]+ *\| *ds-candidate *\|' "$COMPONENT_REGISTRY" | while IFS='|' read -r _ name _scope since _rest; do
      since="$(printf '%s' "$since" | tr -d ' ')"
      age="$(node -e 'const d=new Date(process.argv[1]);process.stdout.write(isNaN(d)?"0":String(Math.floor((Date.now()-d.getTime())/86400000)))' "$since" 2>/dev/null || echo 0)"
      [ "$age" -le "$DS_CANDIDATE_MAX_DAYS" ] || echo "component $(printf '%s' "$name" | tr -d ' ') has been a DS candidate for $age days (max $DS_CANDIDATE_MAX_DAYS): land it in the design system or mark it project → $COMPONENT_REGISTRY"
    done
  fi
  [ -z "$THEME_BRIDGE_FILES" ] || for f in $(printf '%s' "$THEME_BRIDGE_FILES" | tr ',' ' '); do
    [ -e "$f" ] || echo "THEME_BRIDGE_FILES names $f, which does not exist → scripts/agent/agent.conf"
  done
}
run check_permissions
run check_docs_index
run check_modules
run check_gates
run check_package_manager
run check_runner
run check_eslint_fragment
run check_skill_length
run check_components
check_skill_links() {  # every tool reads each skill through a working relative link
  for d in .claude/skills/*/; do
    name="$(basename "$d")"
    [ -L ".cursor/skills/$name" ] && [ -e ".cursor/skills/$name" ] || echo ".cursor/skills/$name is not a working link to .claude/skills/$name: re-run trs-app agents upgrade → .cursor/skills/$name"
    [ -L ".agents/skills/$name/SKILL.md" ] && [ -e ".agents/skills/$name/SKILL.md" ] || echo ".agents/skills/$name/SKILL.md is not a working link to .claude/skills/$name/SKILL.md: re-run trs-app agents upgrade → .agents/skills/$name/SKILL.md"
    case "$name" in scan|task|finalize|handoff|flow|review)
      link=".agents/workflows/$name.md"
      [ -L "$link" ] && [ -e "$link" ] || echo "$link is not a working link to .claude/skills/$name/SKILL.md: re-run trs-app agents upgrade → $link" ;;
    esac
  done
}
run check_skill_links

# 3. Repo-specific checks, one function each; the block between the markers survives a re-run of agents-init.
# repo-checks:start
modules="$(ls -d "$MODULES_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')"
check_module_count() {  # no doc states a stale module count
  for doc in $(docs_live) CLAUDE.md; do check_number "module count" "$modules" "$doc" '[0-9]+ (host-owned |source )?modules'; done
}
run check_module_count
check_remotes() {  # module-federation repos: every remote in the config has a row in the contract doc, and no doc states a stale remote count
  [ -f module-federation.config.ts ] || return 0
  remotes="$(grep -oE '^ +[a-zA-Z]+: *`?[a-zA-Z]+@' module-federation.config.ts | sed -E 's/^ +([a-zA-Z]+):.*/\1/' | sort -u)"
  for r in $remotes; do grep -q "$r" FEDERATION.md 2>/dev/null || echo "remote $r has no row in FEDERATION.md → FEDERATION.md"; done
  n="$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l | tr -d ' ')"
  for doc in $(docs_live) FEDERATION.md CLAUDE.md; do check_number "remote count" "$n" "$doc" '[0-9]+ remotes'; done
}
run check_remotes
# repo-checks:end

printf 'drift-check: %s checks, drift %s\n' "$checks" "$([ "${#drift[@]}" -eq 0 ] && echo none || echo "${#drift[@]}")"
for d in ${drift[@]+"${drift[@]}"}; do printf '  - %s\n' "$d"; done
[ "${#drift[@]}" -eq 0 ]
