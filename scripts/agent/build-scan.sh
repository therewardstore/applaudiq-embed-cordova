#!/usr/bin/env bash
# The build-output gate, after the build: gitleaks over what ships (an .env value or a key the bundler inlined),
# source maps included, with the repo's .gitleaks.toml; then where source maps sit in it (SOURCE_MAPS).
#   bash scripts/agent/build-scan.sh   # pre-push and CI (check 2), through gates.sh
# BUILD_DIRS names the folders (comma-separated); empty = every one of dist, dist-*, build, out, .next/static.
# Exit 0 pass, 1 a finding, 3 gitleaks missing in CI.
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"
shopt -s nullglob

dirs=()
if [ -n "$BUILD_DIRS" ]; then
  IFS=',' read -r -a dirs <<< "$BUILD_DIRS"
else
  for d in dist dist-* build out .next/static; do [ -d "$d" ] && dirs+=("$d"); done
fi
if [ "${#dirs[@]}" -eq 0 ]; then
  echo "▸ build scan: no build output (dist, build, out, .next/static); set BUILD_DIRS if it lives elsewhere"
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  # CI installs gitleaks before this runs: a missing binary there is a broken job, never a pass.
  if [ -n "${CI:-}" ]; then echo "✖ build scan: gitleaks is not installed" >&2; exit 3; fi
  echo "▸ build scan: gitleaks not installed — CI is the net (brew install gitleaks)"
  exit 0
fi
config=()
[ ! -f .gitleaks.toml ] || config=(--config .gitleaks.toml)

rc=0
for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "✖ build scan: $d is not a folder (BUILD_DIRS)" >&2; rc=1; continue; }
  gitleaks dir "$d" "${config[@]}" --no-banner --redact --log-level warn || rc=1
done
[ "$rc" -eq 0 ] || { echo "✖ build scan: a secret is in the build output above; a browser bundle is public" >&2; exit 1; }

maps=0
for d in "${dirs[@]}"; do maps=$(( maps + $(find "$d" -name '*.map' -type f | wc -l) )); done
if [ "$maps" -gt 0 ]; then
  case "$SOURCE_MAPS" in
    allow) ;;
    block) echo "✖ build scan: $maps source map(s) in the build output; deployed, they publish the source" >&2; exit 1 ;;
    *) echo "⚠ build scan: $maps source map(s) in the build output; deployed, they publish the source (SOURCE_MAPS=warn)" ;;
  esac
fi
echo "▸ build scan: ${dirs[*]} clean"
