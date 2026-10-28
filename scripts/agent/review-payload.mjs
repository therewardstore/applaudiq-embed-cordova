// review-payload.mjs <pr.diff> <review.json> <head-sha> <model> <scope> <files-note> <bot-name>
// Turns the model's review.json into the review GitHub accepts: every comment anchored to a line the diff has
// (the nearest new-side hunk line within 3), the rest kept in the body under "Not anchored", the header with the
// hidden marker `--since last` reads, and a verdict. Pure: reads two files, prints one JSON object, never posts.
import { readFileSync } from 'node:fs';

const [diffPath, reviewPath, sha = '', model = '', scope = 'full', filesNote = '', bot = 'Review'] = process.argv.slice(2);

const HUNK_RE = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/;

/** A line inside a hunk that the new file has: context or added (not removed, not a "\ No newline" note). */
const isNewSide = (raw) => raw !== '' && !raw.startsWith('-') && !raw.startsWith('\\');

// `---`/`+++` are file headers only between a `diff --git` line and the first @@; inside a hunk a removed
// line can start with `-- ` (a SQL comment) and an added one with `++ `.
function step(state, raw) {
  if (raw.startsWith('diff --git ')) return { ...state, header: true, line: 0 };
  if (state.header && raw.startsWith('+++ ')) {
    return { ...state, path: raw.slice(4).trim().replace(/^"(.*)"$/, '$1').replace(/^b\//, '') };
  }
  if (state.header && raw.startsWith('--- ')) return state;
  const hunk = HUNK_RE.exec(raw);
  if (hunk) return { ...state, header: false, line: Number(hunk[1]) };
  if (!state.path || !state.line || !isNewSide(raw)) return state;
  state.lines.get(state.path).add(state.line);
  return { ...state, line: state.line + 1 };
}

/** path → sorted new-side line numbers the diff touches or shows (context lines count: a comment may sit there). */
export function hunkLines(diff) {
  let state = { lines: new Map(), path: '', line: 0, header: false };
  for (const raw of diff.split('\n')) {
    state = step(state, raw);
    if (state.path && !state.lines.has(state.path)) state.lines.set(state.path, new Set());
  }
  return state.lines;
}

/** The line to anchor on: the line itself, else the nearest shown line within 3, else none. */
export function anchor(lines, path, wanted) {
  const set = lines.get(path);
  if (!set || !Number.isInteger(wanted)) return undefined;
  if (set.has(wanted)) return wanted;
  for (let d = 1; d <= 3; d += 1) {
    if (set.has(wanted + d)) return wanted + d;
    if (set.has(wanted - d)) return wanted - d;
  }
  return undefined;
}

/** The model's comments split into the ones a diff line can carry and the rest, as text for the body. */
function placeComments(lines, list) {
  const comments = [];
  const loose = [];
  for (const c of Array.isArray(list) ? list.slice(0, 20) : []) {
    if (!c || typeof c !== 'object') continue;
    const path = String(c.path ?? '');
    const body = String(c.body ?? '');
    const at = anchor(lines, path, Number(c.line));
    if (at) comments.push({ path, line: at, side: 'RIGHT', body });
    else loose.push(`${path}:${String(c.line ?? '?')} — ${body}`);
  }
  return { comments, loose };
}

/** The model's verdict when it gave a valid one; else needs-changes when there is a Must fix or any finding. */
function verdictOf(raw, body, findings) {
  if (raw.verdict === 'ready' || raw.verdict === 'needs-changes') return raw.verdict;
  const mustFix = /^Must fix\n(?!\s*none)\s+\S/m.test(body);
  return mustFix || findings > 0 ? 'needs-changes' : 'ready';
}

/** The posted review: {event, body, comments, verdict}. `verdict` is stripped before posting. */
export function payload(diff, review, meta) {
  const raw = review && typeof review === 'object' ? review : {};
  const { comments, loose } = placeComments(hunkLines(diff), raw.comments);
  let body = typeof raw.body === 'string' && raw.body.trim() ? raw.body : 'nothing to fix';
  const verdict = verdictOf(raw, body, comments.length + loose.length);
  if (loose.length) body += `\n\nNot anchored (outside the diff's hunks)\n${loose.map((l) => `  ${l}`).join('\n')}`;
  const where = meta.scope.replace(/^since-/, 'since ');
  const header = `### ${meta.bot} — review of \`${meta.sha.slice(0, 7)}\` · ${meta.model} · ${where} · ${meta.filesNote}\n<!-- orbit-review sha=${meta.sha} model=${meta.model} scope=${meta.scope} verdict=${verdict} comments=${comments.length} -->`;
  return { event: 'COMMENT', body: `${header}\n\n${body}`.slice(0, 60000), comments, verdict };
}

if (diffPath && reviewPath) {
  let review = {};
  try {
    review = JSON.parse(readFileSync(reviewPath, 'utf8'));
  } catch {
    review = { body: 'AI review: the model wrote no valid review.json', comments: [] };
  }
  const diff = readFileSync(diffPath, 'utf8');
  process.stdout.write(`${JSON.stringify(payload(diff, review, { sha, model, scope, filesNote, bot }))}\n`);
}
