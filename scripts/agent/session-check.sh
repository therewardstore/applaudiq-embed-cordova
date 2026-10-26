#!/usr/bin/env bash
# The cheap part of /scan. Runs at session start in every tool, reads nothing
# but git and grep, and always exits 0. One line when nothing has drifted.
#
#   bash scripts/agent/session-check.sh               # the cheap checks (resume, compaction)
#   bash scripts/agent/session-check.sh full          # a new session: the drift check folded in too
#   bash scripts/agent/session-check.sh cursor full   # {"additional_context": "…"} for Cursor's hook
set -uo pipefail
shopt -s nullglob
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"
# Args: "cursor" wraps the output as JSON; "full" (a new session) also runs drift-check.sh.
format=text; full=0
for a in "$@"; do case "$a" in cursor) format=cursor ;; full) full=1 ;; esac; done

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
sha="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
drift=()
warn=()

# Being on the default branch is the user's call (a warning); a branch the pre-push hook rejects is drift.
if [ "$branch" = "$DEFAULT_BRANCH" ]; then
  warn+=("on $DEFAULT_BRANCH: work on a ticket branch (${TICKET_HUMAN} plus ${TICKET_DIGITS_HUMAN}); $DEFAULT_BRANCH is pushed only when the remote does not have it yet")
elif ! bash scripts/git/check-branch.sh "$branch" >/dev/null 2>&1; then
  drift+=("branch \"$branch\" can't be pushed: it needs ${TICKET_HUMAN} plus ${TICKET_DIGITS_HUMAN}")
fi

hooks_path="$(git config core.hooksPath 2>/dev/null || true)"
case "$HOOKS" in
  orbit)
    # Orbit's shim owns the hook path and runs this repo's gates once, with stdin, from .orbit-hooks.
    case "$hooks_path" in .orbit-hooks|*/.orbit-hooks) ;; *) drift+=("HOOKS=orbit but core.hooksPath is '${hooks_path:-unset}': run orbit hooks install") ;; esac
    grep -qs 'gates.sh' "${hooks_path:-.orbit-hooks}/pre-push" 2>/dev/null || drift+=("${hooks_path:-.orbit-hooks}/pre-push doesn't run this repo's gates.sh")
    ;;
  chain:*)
    # The repo's own hook folder stays; its pre-push and pre-commit must end in friday's gates call.
    chain="${HOOKS#chain:}"
    [ -n "$hooks_path" ] || drift+=("HOOKS=$HOOKS but core.hooksPath is unset: git config core.hooksPath $chain")
    for hook in pre-commit pre-push; do
      [ -f "$chain/$hook" ] || { drift+=("$chain/$hook is missing: it must run bash scripts/agent/gates.sh $hook"); continue; }
      grep -q "gates.sh $hook" "$chain/$hook" || drift+=("$chain/$hook doesn't run scripts/agent/gates.sh $hook")
      [ -x "$chain/$hook" ] || drift+=("$chain/$hook isn't executable, so git skips it: chmod +x $chain/$hook")
    done
    ;;
esac
if [ "$HOOKS" = husky ]; then
  [ -n "$hooks_path" ] ||
    drift+=("git hooks aren't installed in this clone: run $PM install")
  grep -q check-commit-msg .husky/commit-msg 2>/dev/null ||
    drift+=(".husky/commit-msg doesn't call check-commit-msg.sh")
  grep -q 'gates.sh pre-commit' .husky/pre-commit 2>/dev/null ||
    drift+=(".husky/pre-commit doesn't run scripts/agent/gates.sh pre-commit")
  grep -q 'gates.sh pre-push' .husky/pre-push 2>/dev/null ||
    drift+=(".husky/pre-push doesn't run scripts/agent/gates.sh pre-push")
  grep -q prepare-commit-msg .husky/prepare-commit-msg 2>/dev/null ||
    drift+=(".husky/prepare-commit-msg doesn't call prepare-commit-msg.sh: editor commits get no ticket")
  # The gates call must be the hook's last command, so its exit code is the hook's.
  for hook in pre-commit pre-push; do
    [ ! -f ".husky/$hook" ] || [ "$(grep -v '^[[:space:]]*#' ".husky/$hook" | grep -v '^[[:space:]]*$' | tail -1)" = "bash scripts/agent/gates.sh $hook" ] ||
      drift+=(".husky/$hook doesn't end in \`bash scripts/agent/gates.sh $hook\`: a failed gate may not fail the hook")
  done
  # husky 9 runs the files through its own shim (core.hooksPath=.husky/_); a direct hooksPath needs them executable.
  case "$(git config core.hooksPath 2>/dev/null)" in
    */_|'') ;;
    *) for hook in .husky/commit-msg .husky/pre-commit .husky/pre-push .husky/prepare-commit-msg; do
         [ ! -f "$hook" ] || [ -x "$hook" ] || drift+=("$hook isn't executable, so git skips it: chmod +x $hook")
       done ;;
  esac
fi
# A directory-only pattern (`.qa/`) matches nothing that does not exist yet, so
# probe a path inside it and fall back to the pattern itself.
git check-ignore -q .qa/plan.md 2>/dev/null || git check-ignore -q .qa 2>/dev/null || grep -qsE '^\.qa/?$' .gitignore ||
  drift+=(".qa/ is not git-ignored: /handoff would write a committable file")
if grep -q 'enable-pre-post-scripts=true' .npmrc 2>/dev/null && grep -qE '"(precommit|postcommit|prepush)"' package.json 2>/dev/null; then
  drift+=("package.json has a pre/post commit script that $PM runs around the commit command: the gates run twice")
fi
# lint-staged: prettier --write first, then eslint with the lint script's cap (never 0 on
# staged files) and --no-warn-ignored (ESLint 9 warns on a staged file its config ignores).
# The lint-staged CONFIG, not the dependency line: a repo that only installs it has nothing to check.
if [ -f package.json ] && node -e 'process.exit(require("./package.json")["lint-staged"] ? 0 : 1)' 2>/dev/null; then
  if staged="$(node -e 'const v=Object.values(require("./package.json")["lint-staged"]||{}).flat();process.stdout.write([v.some(s=>/^(npx )?prettier\b.*--write/.test(s))?"1":"0",v.find(s=>/^(npx )?eslint\b/.test(s))||""].join("\n"))' 2>/dev/null)"; then
    fmt="${staged%%$'\n'*}"; eslint_entry="${staged#*$'\n'}"
    [ "$fmt" = 1 ] || drift+=("lint-staged doesn't run prettier --write: commits aren't formatted")
  else
    eslint_entry="$(grep -oE '"(npx )?eslint[^"]*"' package.json | head -1 | tr -d '"')"
  fi
  # No eslint entry at all is the same failure as one without the flag: the commit gate is not the lint gate.
  case "$eslint_entry" in *--no-warn-ignored*) ;; *) drift+=("lint-staged's eslint lacks --no-warn-ignored: staging an ignored file (a test) fails the commit") ;; esac
  if [ -n "$eslint_entry" ]; then
    cap="$(grep -oE '"lint": *"[^"]*--max-warnings[= ]+[0-9]+' package.json | grep -oE '[0-9]+$')"
    scap="$(printf '%s' "$eslint_entry" | grep -oE -- '--max-warnings[= ]+[0-9]+' | grep -oE '[0-9]+$')"
    [ -z "$cap" ] || [ "$scap" = "$cap" ] || drift+=("lint-staged's cap (${scap:-none}) differs from the lint script's ($cap): one cap, in package.json")
  fi
fi
[ -f scripts/agent/agent.conf ] ||
  drift+=("scripts/agent/agent.conf is missing: every gate is running on defaults (re-run trs-app agents-init)")
# The install manifest: a playbook-owned file that went missing means the install is
# behind (or damaged); a re-run of agents-init puts it back.
if [ -f scripts/agent/agent.manifest ]; then
  missing=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -e "$f" ] || [ -L "$f" ] || missing="$missing ${f#scripts/agent/}"
  done < <(sed -n '/^# owned$/,/^# marked$/p' scripts/agent/agent.manifest | grep -v '^#')
  [ -f scripts/agent/playbook-version ] || missing="$missing playbook-version"
  [ -z "$missing" ] ||
    drift+=("install is older than the playbook, missing:$missing — re-run trs-app agents-init")
else
  # No manifest: an install from the playbook itself, so its fixed list of owned files is the manifest.
  missing=""
  for f in scripts/agent/session-check.sh scripts/agent/drift-check.sh scripts/agent/scan-diff.sh \
    scripts/agent/test-changed.sh scripts/agent/fingerprint.sh scripts/agent/playbook-version \
    scripts/git/check-branch.sh scripts/git/check-commit-msg.sh scripts/git/check-commit-range.sh \
    scripts/git/prepare-commit-msg.sh scripts/git/check-docs-moved.sh .claude/settings.json \
    .cursor/hooks.json .cursor/permissions.json .cursor/cli.json .codex/hooks.json .codex/config.toml; do
    [ -e "$f" ] || missing="$missing ${f#scripts/agent/}"
  done
  rules=(.codex/rules/*.rules)
  [ "${#rules[@]}" -gt 0 ] || missing="$missing .codex/rules/*.rules"
  [ -z "$missing" ] ||
    drift+=("install is older than the playbook, missing:$missing — run the upgrade prompt (playbook section 4b) or re-run trs-app agents-init")
fi

for dir in .claude/skills/*/; do
  name="$(basename "$dir")"
  grep -q "\`$name\`" CLAUDE.md 2>/dev/null || drift+=("skill $name has no row in CLAUDE.md")
  [ -e ".cursor/skills/$name" ] || drift+=("skill $name isn't visible to Cursor: .cursor/skills/$name is missing")
  if grep -q 'disable-model-invocation: true' "$dir/SKILL.md" 2>/dev/null; then
    [ -f ".cursor/commands/$name.md" ] || drift+=("slash-only skill $name has no .cursor/commands/$name.md")
    [ ! -d .agents/skills ] || [ -f ".agents/skills/$name/SKILL.md" ] ||
      drift+=("skill $name isn't visible to Codex: .agents/skills/$name/SKILL.md is missing")
    [ ! -d .agents/workflows ] || [ -f ".agents/workflows/$name.md" ] ||
      drift+=("skill $name has no Antigravity workflow: .agents/workflows/$name.md is missing")
  fi
done
for link in .cursor/skills/* .agents/skills/*/SKILL.md .agents/workflows/*.md .cursor/commands/*.md; do
  if [ ! -L "$link" ] || [ ! -e "$link" ]; then
    drift+=("$link isn't a working symlink")
  elif [ "$(readlink "$link" | cut -c1)" = / ]; then
    drift+=("$link is an absolute symlink; make it relative")
  fi
done

for shim in .cursor/commands/*.md .agents/workflows/*.md .agents/skills/*/ .cursor/skills/*; do
  name="$(basename "$shim" .md)"
  [ -d ".claude/skills/$name" ] || warn+=("skill $name was removed, but $shim still points at it")
done
for name in $(grep -oE '^\|.*\| *`[a-z0-9-]+` *\|$' CLAUDE.md 2>/dev/null | grep -oE '`[a-z0-9-]+` *\|$' | tr -d '` |'); do
  [ -d ".claude/skills/$name" ] || warn+=("CLAUDE.md lists skill $name, but .claude/skills/$name doesn't exist")
done
for f in $(git status --porcelain -- .claude/skills 2>/dev/null | awk '$1 ~ /D/ && $2 ~ /SKILL\.md$/ { print $2 }'); do
  warn+=("skill $(basename "$(dirname "$f")") is being deleted in your working tree: remove its CLAUDE.md row and shims too, or restore it")
done
upstream_range="$(git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 && echo '@{u}..HEAD' || echo 'HEAD --not --remotes')"
for f in $(git log --diff-filter=D --name-only --format= $upstream_range -- '.claude/skills/*/SKILL.md' 2>/dev/null); do
  warn+=("skill $(basename "$(dirname "$f")") is deleted in an unpushed commit: make sure that's deliberate")
done

# .env out of step with .env.example or env.ts: a boot-time throw waiting to happen.
if [ -f scripts/agent/env-check.sh ] && [ -f .env.example ]; then
  bash scripts/agent/env-check.sh --quiet </dev/null >/dev/null 2>&1 || drift+=(".env, .env.example and src/config/env.ts disagree: bash scripts/agent/env-check.sh (trs-app env init --force rebuilds .env)")
fi

# Repo-specific drift checks go here (milliseconds, git and grep only); the block survives a re-run of agents-init.
# repo-checks:start
# repo-checks:end

# A new session also runs the full drift check; resume and compaction skip it.
if [ "$full" = 1 ] && [ -f scripts/agent/drift-check.sh ]; then
  while IFS= read -r l; do drift+=("$l"); done < <(bash scripts/agent/drift-check.sh --no-session </dev/null | sed -n 's/^  - //p')
fi

# The shell twin of the CLAUDE.md preamble: the first line any tool sees, so the skills govern the first message.
text="friday: repo $REPO_NAME @ $branch · TASK_MODE=$TASK_MODE → .claude/skills/flow/SKILL.md governs every request (where + type → plan → build → gate → ASK before any commit)"$'\n'
text+="scan-check: $(basename "$PWD") @ $branch ($sha, $dirty dirty) · drift: "
if [ "${#drift[@]}" -eq 0 ]; then text+="none"; else text+="${#drift[@]}"; fi
[ "${#warn[@]}" -eq 0 ] || text+=" · warnings: ${#warn[@]}"
for d in ${drift[@]+"${drift[@]}"}; do text+=$'\n'"  - $d"; done
for w in ${warn[@]+"${warn[@]}"}; do text+=$'\n'"  ⚠ $w"; done
if [ "${#drift[@]}" -gt 0 ] || [ "${#warn[@]}" -gt 0 ]; then
  text+=$'\n'"Report these to the user before starting work. /scan runs drift-check.sh for the full picture; fixes go through /task."
fi

if [ "$format" = cursor ]; then
  printf '%s' "$text" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify({additional_context:s})+"\n"))'
else
  printf '%s\n' "$text"
fi
exit 0
