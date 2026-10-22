#!/usr/bin/env bash
# The shell guard: refuses the commands that would skip the gates before the tool runs
# them. Claude Code and Codex call it from PreToolUse (JSON on stdin, exit 2 = blocked,
# stderr goes to the agent); Cursor from beforeShellExecution (`cursor` argument: a JSON
# permission on stdout). Enforcement never depends on it — the hooks and CI are the
# guarantee — it only saves a round trip. Reads nothing but the conf; never writes.
#
#   echo '{"tool_input":{"command":"git commit --no-verify"}}' | bash scripts/agent/guard-shell.sh
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

format="${1:-}"
input="$(cat)"
command="$(printf '%s' "$input" | node -e '
let s = "";
process.stdin.on("data", (d) => (s += d)).on("end", () => {
  try {
    const j = JSON.parse(s);
    const c = j.tool_input?.command ?? j.command ?? j.input?.command ?? "";
    process.stdout.write(String(c));
  } catch { process.stdout.write(""); }
});' 2>/dev/null)"
[ -n "$command" ] || exit 0

reason=""
check() { [ -n "$reason" ] || ! printf '%s\n' "$command" | grep -qE -e "$1" || reason="$2"; }
check '--no-verify|--no-gpg-sign.*--no-verify' "'--no-verify' skips the gates; fix what the hook reports instead."
check 'git[[:space:]]+commit[^|;&]*[[:space:]]-[a-zA-Z]*n' "'git commit -n' is --no-verify; fix what the hook reports instead."
check '(^|[;&|][[:space:]]*)HUSKY=0[[:space:]]' "'HUSKY=0' disables the hooks; the gates are the contract."
check 'core\.hooksPath' "changing core.hooksPath disables the hooks; \`${PM} install\` wires them."
check 'git[[:space:]]+push[^|;&]*(--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$))' "a plain force push rewrites shared history; the developer runs 'git push --force-with-lease' by hand if ever."
check 'FRIDAY_BREAK_GLASS=' "break-glass is the developer's call, typed by hand, never by an agent."
if [ "${ORBIT:-0}" != 1 ]; then
  check 'ORBIT_BYPASS=' "ORBIT_BYPASS has no meaning outside an Orbit workspace."
fi

if [ -z "$reason" ]; then
  [ "$format" = cursor ] && printf '{"permission":"allow"}\n'
  exit 0
fi
if [ "$format" = cursor ]; then
  printf '%s' "$reason" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify({permission:"deny",user_message:"friday blocked: "+s,agent_message:"friday blocked this command: "+s})+"\n"))'
  exit 0
fi
echo "friday blocked this command: $reason" >&2
exit 2
