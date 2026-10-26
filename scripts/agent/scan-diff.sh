#!/usr/bin/env bash
# The code rules, checked on the lines a change ADDS, so old code never blocks
# new work. `/task` runs it before handing off; `/finalize`, the pre-commit and
# the pre-push hooks run it as a gate. Patterns come from scripts/agent/agent.conf.
#
#   scan-diff.sh                     # the working tree against HEAD, new files included
#   scan-diff.sh --cached            # the staged lines (GIT_INDEX_FILE honoured: a temp index is a snapshot)
#   scan-diff.sh <base>..<tip>       # a commit range; `bash scripts/agent/gates.sh range` prints it
#
# Exit: 0 clean (or a valid empty diff), 1 a rule failed, 2 bad arguments or an
# unknown revision, 3 git could not produce the diff.
set -uo pipefail
. "$(dirname "$0")/lib.sh"; friday_load_conf "$0"

mode="${1:-HEAD}"
case "$mode" in
  --cached) [ $# -le 1 ] || { echo "usage: scan-diff.sh --cached" >&2; exit 2; } ;;
  HEAD) [ $# -le 1 ] || { echo "usage: scan-diff.sh [HEAD | --cached | <base>..<tip>]" >&2; exit 2; } ;;
  *..*) [ $# -le 1 ] || { echo "usage: scan-diff.sh <base>..<tip>" >&2; exit 2; }; friday_check_range "$mode" || exit 2 ;;
  *) echo "✖ scan-diff.sh: '$mode' is not a mode or a <base>..<tip> range" >&2; exit 2 ;;
esac

exempt='(/(__mocks__|mocks|__tests__)/|\.(test|spec|stories)\.[jt]sx?$|\.d\.ts$)'
# A copy catalog is prose, never code: any locales/lang/i18n folder, plus LANG_DIR when the conf names one.
lang_re='/(locales?|lang|i18n)/'
comment_re='^[[:space:]]*(//|/?\*|\{/\*)'
# A leading closed comment hides nothing: `/* x */ navigate('/a')` is judged on the code after it.
leading_comment='^[[:space:]]*(\{/\*.*\*/\}|/\*.*\*/)[[:space:]]*'

errors=0
warnings=0
progress_tty=""
report() {
  local level="$1" file="$2" line="$3" rule="$4" text="$5"
  [ -z "$progress_tty" ] || printf '\r\033[K' >&2
  printf '%s %s:%s  %s\n      %s\n' "$level" "$file" "$line" "$rule" "$(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-110)"
  if [ "$level" = "✖" ]; then errors=$((errors + 1)); else warnings=$((warnings + 1)); fi
}

diff_opts=(-U0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/)
patch="$(mktemp)"
trap 'rm -f "$patch"' EXIT

# Every git call fails loudly: a diff that could not be produced is never "clean".
case "$mode" in
  --cached) git diff "${diff_opts[@]}" --cached -- > "$patch" || { echo "✖ git diff --cached failed" >&2; exit 3; } ;;
  HEAD)
    git diff "${diff_opts[@]}" HEAD -- > "$patch" || { echo "✖ git diff HEAD failed" >&2; exit 3; }
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      # --no-index exits 1 whenever the file has content; that is not a failure here.
      git diff "${diff_opts[@]}" --no-index -- /dev/null "$f" >> "$patch" || true
    done < <(git ls-files --others --exclude-standard)
    ;;
  *) git diff "${diff_opts[@]}" "$mode" -- > "$patch" || { echo "✖ git diff $mode failed" >&2; exit 3; } ;;
esac

if [ ! -s "$patch" ]; then
  echo "::friday::empty-diff"
  echo "scan-diff: clean (nothing added)"
  exit 0
fi

# A new component, hook or helper is listed in the registry first: `ds-candidate` (anything another
# project could use belongs in the design system — components, hooks and utils packages) or `project`.
if [ -n "$COMPONENT_REGISTRY" ] && [ "$PROFILE" != gates-only ]; then
  while IFS= read -r f; do
    printf '%s\n' "$f" | grep -qE "$exempt" && continue
    kind=""
    case "$f" in
      */components/*.tsx|*/components/*.jsx) kind=component ;;
      */hooks/use*.ts|*/hooks/use*.tsx|*/hooks/*/use*.ts|*/hooks/*/use*.tsx) kind=hook ;;
      */lib/*.ts|*/utils/*.ts|*/helpers/*.ts) kind=helper ;;
      *) continue ;;
    esac
    name="$(basename "${f%.*}")"
    case "$kind" in
      component) printf '%s\n' "$name" | grep -qE '^[A-Z][A-Za-z0-9]*$' || continue ;;
      *) printf '%s\n' "$name" | grep -qE '^(index|types|constants)$' && continue ;;
    esac
    if ! grep -qE "^\| *$name *\|" "$COMPONENT_REGISTRY" 2>/dev/null; then
      report ✖ "$f" 1 "new $kind $name is not in $COMPONENT_REGISTRY: reusable across projects → build it in the design system and add \`| $name | ds-candidate | $(date +%Y-%m-%d) | <why> |\`; only this app → \`| $name | project | … |\`" "$f"
    fi
  done < <(awk '/^--- \/dev\/null/ { nf = 1; next } /^\+\+\+ b\// { if (nf) print substr($0, 7); nf = 0; next } { nf = 0 }' "$patch")
fi

# Themes live in the design system. Added app code may not define one; THEME_BRIDGE_FILES are
# the reviewed exceptions and are exempt from every theme rule.
theme_bridge_re='^$'
if [ -n "$THEME_BRIDGE_FILES" ]; then
  theme_bridge_re="^($(printf '%s' "$THEME_BRIDGE_FILES" | sed 's/[.[\*^$()+?{}|]/\\&/g; s/,/|/g'))$"
fi
colour_fn='\b(rgba?|hsla?|oklch|oklab|lab|lch|color-mix|color)\('
hex='#[0-9a-fA-F]{3,8}\b'
theme_msg="theme or colour defined in app code: use the design system's tokens (var(--…) / DS props); a reviewed exception goes in THEME_BRIDGE_FILES"
check_theme() {
  local file="$1" line="$2" text="$3" is_style="$4" code
  [ "$THEME_RULE" = 1 ] && [ "$PROFILE" != gates-only ] || return 0
  printf '%s\n' "$file" | grep -qE "$theme_bridge_re" && return 0
  code="$(printf '%s' "$text" | sed -E 's#/\*.*\*/##g; s#//.*$##')"
  if [ "$is_style" = 1 ]; then
    if printf '%s\n' "$code" | grep -qE '^[[:space:]]*@theme\b'; then
      report ✖ "$file" "$line" "$theme_msg (@theme block)" "$text"
    elif printf '%s\n' "$code" | grep -qE '(^|[{;[:space:]])--[a-z0-9-]*(colou?r|brand|primary|secondary|accent|surface|background|bg|foreground|text|border)[a-z0-9-]*[[:space:]]*:'; then
      report ✖ "$file" "$line" "$theme_msg (colour custom property)" "$text"
    elif printf '%s\n' "$code" | grep -qE "$hex|$colour_fn"; then
      report ✖ "$file" "$line" "$theme_msg (raw colour value)" "$text"
    fi
    return 0
  fi
  if printf '%s\n' "$code" | grep -qE '\b(registerBrand|defineBrand|createTheme|defineTheme|extendTheme)\b'; then
    report ✖ "$file" "$line" "$theme_msg (theme or brand registration)" "$text"
  elif printf '%s\n' "$code" | grep -qE "^[[:space:]]*import .* from [\"'][^\"']*(theme|themes|palette|colou?rs|brand)[^\"']*[\"']" && ! printf '%s\n' "$code" | grep -qE "from [\"']@therewardstore/"; then
    report ✖ "$file" "$line" "$theme_msg (theme module import outside the design system)" "$text"
  elif printf '%s\n' "$code" | grep -qE "\\b(bg|text|border|fill|stroke|ring|from|via|to|outline|shadow|accent|caret|decoration|divide|placeholder)-\\[(#|rgba?\\(|hsla?\\(|oklch\\()"; then
    report ✖ "$file" "$line" "$theme_msg (Tailwind arbitrary colour)" "$text"
  elif printf '%s\n' "$code" | grep -qE "\\b(fill|stroke)=[\"'](#|rgb|hsl|[a-z]+[\"'])" && ! printf '%s\n' "$code" | grep -qE "\\b(fill|stroke)=[\"'](currentColor|none|inherit)[\"']"; then
    report ✖ "$file" "$line" "$theme_msg (SVG colour literal; use currentColor)" "$text"
  elif printf '%s\n' "$code" | grep -qE "[\"'\`]${hex}|$colour_fn"; then
    report ✖ "$file" "$line" "$theme_msg (colour literal)" "$text"
  fi
}
# A directive is one line and says why: `// eslint-disable-next-line <rule> -- <why>`.
q="'"; bt='`'
strip_strings="s/\"[^\"]*\"//g; s/${q}[^${q}]*${q}//g; s/${bt}[^${bt}]*${bt}//g"
directive_in_comment="(//|/\\*).*(eslint-disable|@ts-(ignore|nocheck|expect-error)|biome-ignore|prettier-ignore)"
directive_ok='^[[:space:]]*// (eslint-disable-next-line [@A-Za-z0-9/_,: -]+|@ts-expect-error) -- .{10,}$'

# The file-level answers (scanned? style? routes file? API file?) are computed once per file,
# not once per added line: a large diff has thousands of lines and a grep per check per line
# is what made a big commit wait a minute at the hook.
last_file=""; file_kind=skip; in_routes=0; in_api=0
classify_file() {
  local f="$1"
  file_kind=skip; in_routes=0; in_api=0
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx) file_kind=code ;;
    *.css|*.scss|*.sass|*.less) file_kind=style ;;
    *) return ;;
  esac
  printf '%s\n' "$f" | grep -qE '(^|/)src/' || { file_kind=skip; return; }
  printf '%s\n' "$f" | grep -qE "$exempt" && { file_kind=skip; return; }
  printf '%s\n' "$f" | grep -qE "$lang_re" && { file_kind=skip; return; }
  [ -n "$LANG_DIR" ] && printf '%s\n' "$f" | grep -qE "^${LANG_DIR}/" && { file_kind=skip; return; }
  [ "$file_kind" = code ] || return
  printf '%s\n' "$f" | grep -qE "$ROUTES_FILE_RE" && in_routes=1
  printf '%s\n' "$f" | grep -qE "$API_FILE_RE" && in_api=1
}
# A diff of thousands of added lines takes minutes here, so it says how far it has got (stderr): in
# place on a terminal, a line per 10% in CI. SCAN_PROGRESS_MIN is the size that turns it on.
total_lines="$(awk '/^\+\+\+ / { next } /^\+/ { n++ } END { print n + 0 }' "$patch")"
progress_every=0; scanned=0; SECONDS=0
if [ "$total_lines" -ge "${SCAN_PROGRESS_MIN:-2000}" ]; then
  if [ -t 2 ]; then progress_tty=1; progress_every=100; else progress_every=$(( (total_lines + 9) / 10 )); fi
fi
progress() {
  local left="" rest start="" end=$'\n'
  [ -z "$progress_tty" ] || { start=$'\r\033[K'; end=""; }
  if [ "$scanned" -lt "$total_lines" ] && [ "$SECONDS" -gt 0 ]; then
    rest=$(( SECONDS * (total_lines - scanned) / scanned ))
    if [ "$rest" -ge 60 ]; then left=", ~$(( rest / 60 ))m left"; else left=", ~${rest}s left"; fi
  fi
  printf '%s  code rules: %d/%d added lines (%d%%), %dm%02ds%s%s' "$start" "$scanned" "$total_lines" \
    $(( scanned * 100 / total_lines )) $(( SECONDS / 60 )) $(( SECONDS % 60 )) "$left" "$end" >&2
}
while IFS=$'\t' read -r file line run text; do
  scanned=$((scanned + 1))
  [ "$progress_every" -eq 0 ] || [ $(( scanned % progress_every )) -ne 0 ] || progress
  if [ "$file" != "$last_file" ]; then classify_file "$file"; last_file="$file"; fi
  [ "$file_kind" != skip ] || continue
  if [ "$file_kind" = style ]; then
    check_theme "$file" "$line" "$text" 1
    continue
  fi

  if [ "$run" -gt "$COMMENT_MAX_LINES" ]; then
    report ✖ "$file" "$line" "comment is $run lines; keep it to $COMMENT_MAX_LINES and say why, not what" "$text"
  fi
  if printf '%s\n' "$text" | grep -qE "$comment_re" && [ "${#text}" -gt "$COMMENT_MAX_LEN" ]; then
    report ✖ "$file" "$line" "comment line is over $COMMENT_MAX_LEN characters" "$text"
  fi
  # A directive lives in a comment (leading or trailing); the same words inside a string literal
  # (a generator, a test fixture) are prose, so the string literals are blanked before looking.
  if printf '%s\n' "$text" | sed -E "$strip_strings" | grep -qE "$directive_in_comment"; then
    if ! printf '%s\n' "$text" | grep -qE "$directive_ok"; then
      report ✖ "$file" "$line" "linter directive must be one line with a reason: // eslint-disable-next-line <rule> -- <why> (or // @ts-expect-error -- <why>); never a block, -line form, @ts-ignore or @ts-nocheck" "$text"
    fi
  fi
  check_theme "$file" "$line" "$text" 0
  # The rules below judge code: strip a leading closed comment, skip a whole-line comment.
  code="$(printf '%s' "$text" | sed -E "s#${leading_comment}##")"
  if [ -z "$code" ] || printf '%s\n' "$code" | grep -qE "$comment_re"; then continue; fi
  text="$code"

  # gates-only (DS, libs, CLIs): the comment, directive and render rules stay; the app rules below do not apply.
  [ "$PROFILE" != gates-only ] || continue
  if [ "$in_routes" -eq 0 ] && [ "$in_api" -eq 0 ]; then
    if printf '%s\n' "$text" | grep -qE "(navigate|push|replace|redirect)\\([[:space:]]*[\"'\`]/|\\b(to|href|path)=\\{?[[:space:]]*[\"'\`]/|\\bpath:[[:space:]]*[\"'\`]/"; then
      report ✖ "$file" "$line" "hard-coded route: use ${ROUTES_HELPER}.<name> from the routes file" "$text"
    fi
  fi
  if [ "$in_api" -eq 0 ]; then
    if printf '%s\n' "$text" | grep -qE "\\b(url|baseURL|endpoint):[[:space:]]*[\"'\`]/|query:[[:space:]]*\\([^)]*\\)[[:space:]]*=>[[:space:]]*[\"'\`]/|fetchUrl\\(|\\b(fetch|axios\\.(get|post|put|patch|delete))\\([[:space:]]*[\"'\`]"; then
      report ✖ "$file" "$line" "hard-coded API path: build it in the API routes file and import ${API_HELPER}" "$text"
    elif [ -n "$API_LITERAL_RE" ] && printf '%s\n' "$text" | grep -qE "[\"'\`]/?(${API_LITERAL_RE})"; then
      report ✖ "$file" "$line" "hard-coded API path: build it in the API routes file and import ${API_HELPER}" "$text"
    fi
  fi
  # Copy lives in the catalog only when the repo has one.
  if [ -n "$LANG_DIR" ] && [ "$in_routes" -eq 0 ] && [ "$in_api" -eq 0 ] && ! printf '%s\n' "$text" | grep -qE 'console\.|Error\(|import |export \* from|throw '; then
    if printf '%s\n' "$text" | grep -qE ">[[:space:]]*[A-Za-z][^<>{}]*[A-Za-z][[:space:]]*<|\\b(title|placeholder|label|alt|aria-label|helperText|tooltip|message|description)=[\"'][^\"']*[A-Za-z]|[:=][[:space:]]*[\"'\`][A-Z][a-z]+[ ,.!?][^\"'\`]*[\"'\`]"; then
      report ✖ "$file" "$line" "hard-coded text: move it to ${LANG_DIR} and read it from there" "$text"
    fi
  fi
  if printf '%s\n' "$text" | grep -qE 'useSelector\(.*=>[[:space:]]*(\(\{|\[|.*\.(filter|map|reduce|slice|concat)\()' && ! printf '%s\n' "$text" | grep -q shallowEqual; then
    report ✖ "$file" "$line" "useSelector returns a new object or array every time, so the component re-renders on every store change: use createSelector or shallowEqual" "$text"
  fi
  if printf '%s\n' "$text" | grep -qE '<[A-Z][A-Za-z.]*[^>]*\b[a-zA-Z]+=\{\{' && ! printf '%s\n' "$text" | grep -qE '\b(style|sx)=\{\{'; then
    report ⚠ "$file" "$line" "object literal passed as a prop: a new object each render defeats memo; hoist it or useMemo" "$text"
  fi
  if printf '%s\n' "$text" | grep -qE '<[A-Z][A-Za-z.]*[^>]*\b[a-zA-Z]+=\{\['; then
    report ⚠ "$file" "$line" "array literal passed as a prop: a new array each render defeats memo; hoist it or useMemo" "$text"
  fi
  if printf '%s\n' "$text" | grep -qE '\bkey=\{(index|idx|i)\}'; then
    report ⚠ "$file" "$line" "array index used as key: items re-mount when the list changes; use a stable id" "$text"
  fi
done < <(awk '
  /^\+\+\+ / { f = substr($0, 7); next }
  /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; c = 0; next }
  /^\+/ {
    t = substr($0, 2)
    if (t ~ /^[ \t]*(\/\/|\/?\*|\{\/\*)/) c++; else c = 0
    printf "%s\t%d\t%d\t%s\n", f, n, c, t
    n++; next
  }
' "$patch")
[ -z "$progress_tty" ] || printf '\r\033[K' >&2

if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
  echo "scan-diff: clean"
else
  echo "scan-diff: $errors error(s), $warnings warning(s)"
fi
[ "$errors" -eq 0 ]
