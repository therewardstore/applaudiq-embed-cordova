#!/usr/bin/env bash
# The zero-advisory rule: no dependency carries an advisory of any severity. The one way past it is
# a pnpm.auditConfig.ignoreGhsas entry that AUDIT_EXCEPTIONS lists with a reason and an end date at
# most AUDIT_EXCEPTION_MAX_DAYS away, for an advisory no release fixes yet. An entry whose fix has
# shipped, whose date has passed, that is not listed, or that left the tree fails like an advisory.
#
# An override that crosses a breaking line (or names no vulnerable range) needs a dated row too.
#
#   audit-check.sh                   # the gate: pre-push, /finalize, CI and the weekly Dependency audit
#   audit-check.sh --report <file>   # also writes the findings as Markdown (the weekly issue's body)
#   audit-check.sh --overrides [--report <file>]   # weekly: which overrides the tree no longer needs
#
# Exit: 0 clean, 1 an advisory, a bad exception or (--overrides) a removable override, 2 bad
# arguments, 3 the audit could not run.
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

report=""; overrides=0
[ "${1:-}" != --overrides ] || { overrides=1; shift; }
case "$#:${1:-}" in
  0:) ;;
  2:--report) report="$2" ;;
  *) echo "usage: audit-check.sh [--overrides] [--report <file>]" >&2; exit 2 ;;
esac

if [ "$PM" != pnpm ]; then
  echo "audit-check: a $PM repo; the exception rules read pnpm.auditConfig, so GATE_AUDIT alone judges it"
  exit 0
fi
[ -f pnpm-lock.yaml ] || { echo "✖ audit-check: no pnpm-lock.yaml to audit" >&2; exit 3; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Every severity and the dev tree, whatever NODE_ENV, an audit-level or production setting narrows.
audit_json() { env -u NODE_ENV -u npm_config_production -u npm_config_audit_level pnpm audit --audit-level=low --json; }
# A scratch copy of the dependency files; package.json comes from the node one-liner that follows.
scratch_copy() {
  mkdir -p "$1"
  for f in pnpm-lock.yaml .npmrc; do [ ! -f "$f" ] || cp "$f" "$1/"; done
  # pnpm-workspace.yaml may hold its own auditConfig: the copy drops that block.
  [ ! -f pnpm-workspace.yaml ] || awk '/^auditConfig:/ { skip = 1; next } skip && /^[^[:space:]]/ { skip = 0 } !skip' \
    pnpm-workspace.yaml > "$1/pnpm-workspace.yaml"
  # An override to a package inside the repo (`file:./vendor/x`) must come along, or re-resolving fails.
  node -e 'const o = (require("./package.json").pnpm || {}).overrides || {};
    for (const v of Object.values(o)) { const m = String(v).match(/^(?:file|link):(\.\/[^]+)$/);
      if (m && !m[1].split("/").includes("..")) console.log(m[1]); }' |
    while IFS= read -r dir; do
      [ -d "$dir" ] || continue
      mkdir -p "$1/$(dirname "$dir")" && cp -R "$dir" "$1/$dir"
    done
}

# Each override is dropped in a scratch copy, the lockfile re-resolved and the tree re-audited: an
# override the tree no longer needs (its parents moved on) is reported so it can be deleted.
if [ "$overrides" = 1 ]; then
  # Exact-version pins are policy, not fixes: removing one is never suggested.
  keys="$(node -e 'const o = (require("./package.json").pnpm || {}).overrides || {}; process.stdout.write(Object.keys(o).filter((k) => !/^\d+\.\d+\.\d+$/.test(String(o[k]))).join("\n"))')"
  removable=(); needed=0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    rm -rf "$work/try"; scratch_copy "$work/try"
    node -e 'const p = require("./package.json"); delete p.pnpm.overrides[process.argv[1]]; process.stdout.write(JSON.stringify(p, null, 2))' \
      "$key" > "$work/try/package.json"
    if ! (cd "$work/try" && pnpm install --lockfile-only --ignore-scripts --reporter=silent >/dev/null 2>&1); then
      echo "✖ audit-check: could not re-resolve without the override $key" >&2; exit 3
    fi
    (cd "$work/try" && audit_json > "$work/try.json" 2>/dev/null)
    left="$(node -e 'try { const a = require(process.argv[1]); if (!a.metadata) throw 0; console.log(Object.keys(a.advisories || {}).length) } catch { console.log("x") }' "$work/try.json")"
    [ "$left" != x ] || { echo "✖ audit-check: pnpm audit returned no report (network, registry or token)" >&2; exit 3; }
    if [ "$left" = 0 ]; then removable+=("$key"); echo "⚠ override $key is no longer needed: delete it"
    else needed=$((needed + 1)); fi
  done <<< "$keys"
  summary="${#removable[@]} removable override(s), $needed still needed"
  echo "audit-check: $summary"
  if [ -n "$report" ]; then
    { echo "Dependency overrides: $summary"; echo; for key in "${removable[@]}"; do echo "- \`$key\`"; done; } > "$report"
  fi
  [ "${#removable[@]}" -eq 0 ]; exit
fi
audit_json > "$work/audit.json" 2> "$work/audit.err"

# A second audit with no ignore list at all: each ignored advisory is judged on it (still in the
# tree, still unfixed?), and anything hidden by a setting outside package.json shows up.
scratch_copy "$work/raw"
node -e 'const p = require("./package.json"); delete (p.pnpm || {}).auditConfig; process.stdout.write(JSON.stringify(p))' \
  > "$work/raw/package.json"
(cd "$work/raw" && audit_json > "$work/raw.json" 2> "$work/raw.err")
raw="$work/raw.json"

node -e '
const fs = require("fs");
const [auditPath, rawPath, excPath, maxDays, reportPath] = process.argv.slice(1);
const read = (p) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return null; } };
const audit = read(auditPath);
const raw = rawPath ? read(rawPath) : null;
if (!audit || !audit.metadata || (rawPath && (!raw || !raw.metadata))) {
  console.error("✖ audit-check: pnpm audit returned no report (network, registry or token): nothing was judged");
  process.exit(3);
}
const cfg = (require(process.cwd() + "/package.json").pnpm || {}).auditConfig || {};
const ignored = cfg.ignoreGhsas || [];
const today = process.env.FRIDAY_TODAY || new Date().toISOString().slice(0, 10);
const day = (d) => Math.round(Date.parse(d + "T00:00:00Z") / 86400000);
// A real calendar date only: 2026-02-30 or 2026-99-99 would never expire.
const realDate = (d) => /^\d{4}-\d{2}-\d{2}$/.test(d) && Number.isFinite(day(d)) && new Date(d + "T00:00:00Z").toISOString().slice(0, 10) === d;
const rows = new Map();
const overrideRows = new Map();
for (const line of (fs.existsSync(excPath) ? fs.readFileSync(excPath, "utf8") : "").split("\n")) {
  const m = line.match(/^\|\s*(GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4})\s*\|([^|]*)\|\s*([0-9-]*)\s*\|([^|]*)\|/);
  if (m) rows.set(m[1], { until: m[3], why: m[4].trim() });
  const o = line.match(/^\|\s*`([^`]+)`\s*\|\s*([0-9-]*)\s*\|([^|]*)\|\s*$/);
  if (o) overrideRows.set(o[1], { until: o[2], why: o[3].trim() });
}
const fixedIn = (a) => (a.patched_versions === "<0.0.0" ? "no release" : a.patched_versions);
const problems = [];
const add = (id, severity, pkg, fixed, problem) => problems.push({ id, severity, pkg, fixed, problem });
for (const a of Object.values(audit.advisories || {})) {
  const pkg = a.module_name + "@" + [...new Set((a.findings || []).map((f) => f.version))].join(",");
  add(a.github_advisory_id, a.severity, pkg, fixedIn(a), a.title);
}
const rawById = new Map(Object.values((raw && raw.advisories) || {}).map((a) => [a.github_advisory_id, a]));
// An advisory the ignore-free audit sees that is neither reported nor ignored in package.json was
// hidden elsewhere (pnpm-workspace.yaml auditConfig, a filter): it counts like any other.
const seen = new Set(Object.values(audit.advisories || {}).map((a) => a.github_advisory_id));
for (const a of rawById.values()) {
  if (seen.has(a.github_advisory_id) || ignored.includes(a.github_advisory_id)) continue;
  add(a.github_advisory_id, a.severity, a.module_name, fixedIn(a), a.title + " (hidden from the audit outside package.json)");
}
for (const id of ignored) {
  const a = rawById.get(id);
  const row = rows.get(id);
  const sev = a ? a.severity : "-", pkg = a ? a.module_name : "-", fixed = a ? fixedIn(a) : "-";
  if (!a) add(id, sev, pkg, fixed, "ignored but no longer in the tree: drop it from ignoreGhsas and " + excPath);
  else if (a.patched_versions !== "<0.0.0") add(id, sev, pkg, fixed, "ignored, but a fixed release exists: upgrade the parent or add a pnpm.overrides entry, then drop the ignore");
  else if (!row) add(id, sev, pkg, fixed, "ignored without a row in " + excPath + " (reason and end date)");
  else if (!realDate(row.until) || !row.why) add(id, sev, pkg, fixed, "its row in " + excPath + " needs an end date (YYYY-MM-DD) and a reason");
  else if (day(row.until) < day(today)) add(id, sev, pkg, fixed, "its exception ended on " + row.until + ": remove the dependency or review and re-date it");
  else if (day(row.until) - day(today) > Number(maxDays)) add(id, sev, pkg, fixed, "its exception ends " + row.until + ", more than " + maxDays + " days ahead (AUDIT_EXCEPTION_MAX_DAYS)");
}
// The breaking line of a version: the major, or 0.minor below 1.0.
const lineOf = (v) => { const m = String(v).match(/(\d+)(?:\.(\d+))?/); return m ? (m[1] === "0" ? "0." + (m[2] || "0") : m[1]) : null; };
const dated = (row, what, fail) => {
  if (!realDate(row.until) || !row.why) return fail("its row in " + excPath + " needs a review date (YYYY-MM-DD) and a reason");
  if (day(row.until) < day(today)) return fail(what + " was due for review on " + row.until + ": drop it, or review and re-date it");
  if (day(row.until) - day(today) > Number(maxDays)) fail(what + " is dated " + row.until + ", more than " + maxDays + " days ahead (AUDIT_EXCEPTION_MAX_DAYS)");
};
const overrides = (require(process.cwd() + "/package.json").pnpm || {}).overrides || {};
for (const [key, target] of Object.entries(overrides)) {
  // An exact version (react: 19.1.1) is a policy pin, e.g. one copy of a federated singleton: not a fix.
  if (/^\d+\.\d+\.\d+$/.test(String(target))) continue;
  // `parent>child` names a chain; the `>` of a `>=` range never follows a name character.
  const parts = key.split(/(?<=[\w.)-])>(?=[@a-z])/i);
  const selector = parts.pop();
  const at = selector.lastIndexOf("@");
  const from = at > 0 ? (selector.slice(at + 1).match(/>=?\s*v?(\d+\.\d+)/) || [])[1] : undefined;
  if (from && !parts.length && lineOf(from) === lineOf(target)) continue;
  const row = overrideRows.get(key);
  const o = (problem) => add(key, "-", "override", String(target), problem);
  if (!row) o("an override that crosses a breaking line or names no vulnerable range needs a row `| `" + key + "` | review date | why |` in " + excPath);
  else dated(row, "the override", o);
}
for (const key of overrideRows.keys()) if (!(key in overrides)) console.log("⚠ override " + key + " is listed in " + excPath + " but not in pnpm.overrides: delete its row");
for (const id of (cfg.ignoreCves || [])) add(id, "-", "-", "-", "ignoreCves is not read here: list the advisory by its GHSA id in ignoreGhsas");
const stale = [...rows.keys()].filter((id) => !ignored.includes(id));
for (const p of problems) console.log("✖ " + p.id + " (" + p.severity + ") " + p.pkg + " — fixed in: " + p.fixed + "\n      " + p.problem);
for (const id of stale) console.log("⚠ " + id + " is listed in " + excPath + " but not ignored: delete its row");
const summary = problems.length
  ? problems.length + " problem(s): every advisory is fixed, or is an unfixed, dated exception"
  : "clean (" + ignored.length + " dated exception(s), none with a fix)";
console.log("audit-check: " + summary);
if (reportPath) {
  const esc = (s) => String(s).replace(/\|/g, "\\|");
  const lines = ["Dependency audit: " + summary, "", "| Advisory | Severity | Package | Fixed in | Problem |", "|---|---|---|---|---|"];
  for (const p of problems) lines.push("| " + [p.id, p.severity, p.pkg, p.fixed, p.problem].map(esc).join(" | ") + " |");
  fs.writeFileSync(reportPath, lines.join("\n") + "\n");
}
process.exit(problems.length ? 1 : 0);
' "$work/audit.json" "$raw" "$AUDIT_EXCEPTIONS" "$AUDIT_EXCEPTION_MAX_DAYS" "$report"
