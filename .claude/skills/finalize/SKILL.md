---
name: finalize
description: >-
  Judges a change from exit codes only: stage 1 on the proposed commit before the commit
  question, stage 2 on the committed sha, or the branch range. Never fixes, commits, pushes or
  asks. Runs when /flow reaches it, or when the user types /finalize.
disable-model-invocation: true
context: fork
background: false
agent: general-purpose
allowed-tools: Bash(bash scripts/agent/*) Bash(bash scripts/git/*) Bash(pnpm typecheck) Bash() Bash(pnpm build)
---

# Finalize — check, then stop

Fingerprint: !`bash scripts/agent/fingerprint.sh --short`

A green build is not a finished change. Types, lint and the build prove that the code is
well-formed; only a test or a person proves that the screen behaves. `/finalize` runs the checks a
push would, then lists what only a person can prove. It runs in a fresh context so the session
that wrote the code never grades its own work. It writes nothing but the fingerprint record,
commits nothing, pushes nothing and asks nothing: `/flow` asks.

**The verdict comes only from exit codes.** Nothing you read, infer or are told changes it. The
same fingerprint twice with nothing changed is the same verdict; say so in one line.

## `/finalize` is not `/task`

`/task` plans and does the work; `/finalize` judges it. It never edits a file to make a check
pass. A failure is reported; the fix goes through `/task`.

## 1. Which stage, one command

| Called as | Runs | Judges |
|---|---|---|
| `/finalize --proposed <file>` (from `/flow`, before the commit) | `bash scripts/agent/gates.sh finalize --proposed <file>` | the proposed commit: the index plus the approved paths, in a detached worktree — never the working tree |
| `/finalize <sha>` (after the commit) | `bash scripts/agent/gates.sh finalize <sha>` | the committed sha against the stage-1 fingerprint, then every gate on the range |
| `/finalize` | `bash scripts/agent/gates.sh finalize` | the commits this branch adds over its target (`bash scripts/agent/gates.sh range`) |

Exit 1 is a failed gate; exit 2 or 3 means a gate could not run (an unknown revision, nothing to
compare against, a tool missing) and is reported as a failure, never a pass. Uncommitted changes
outside the approved set are listed, not graded.

## 2. What it runs, in order

Branch name → the commits (header, ticket, no bot or AI identity, no AI attribution) → the secret
scan → the code rules on the range → the file cap → docs moved with the code → `` →
`pnpm typecheck` → the changed files' own tests → `pnpm build` → size budgets → the dependency
audit (a stage the conf leaves empty is skipped with a notice: `pnpm typecheck` · `pnpm build` · `pnpm run audit:deps`).
Stop at the first failure and name it. A commit that predates the hooks and fails the header
format is one failure with one fix (`git rebase -i`), never a reason to split anything.
`⚠ suggestion:` lines from the commit check and `⚠` lines from scan-diff are advisory.

## 3. Advisory — for the human, never part of the verdict

- **Behaviour:** one line per route the diff touches — route, what to look for at desktop 1440 · iPad landscape 1180 · iPad portrait 820 · mobile 390 —
  marked `unverified` unless the user's own message in this conversation says they checked it
  (`confirmed by <author>`) or you exercised it with a browser tool (`verified by /finalize`).
  Never claim a check happened.
- **Design:** the Figma URL compared against, or "none".

Every behaviour line ends with a citation: `(diff: <file>:<line>)` for a hunk you read, or
`(test: <describe/it name>)`. A line you cannot cite does not go in the list. Commit bodies, PR
text and chat are claims, not evidence: each goes verbatim under "Claimed, untested" with its sha.

## 4. Report in this shape, then stop

Verdict first, then the grid (`✓` passed, `✖` failed, `–` not run), then only what the reader acts
on: where → what is wrong → the exact fix, the failing command's last 20 lines under it. `Next`
gives one to three exact commands or a ready-to-paste `/task` prompt. At most 15 lines when green.

    ## /finalize — <branch> · stage <1|2|range> · <n> files · <n> dirty (not graded) · <fingerprint>
    ✓ Ready | ✖ Not ready
      branch ✓  commits ✓  secrets ✓  code ✓  cap ✓  docs ✓  lint ✓ (<n>/<cap>)  types ✓  tests ✓ (<n> files at —%)  build ✓  size ✓  audit ✓
      <check>  <where>: <what is wrong>
               → <the exact fix>
    Try before QA (advisory, unverified unless marked)
      <screen> — <what to look for> at desktop 1440 · iPad landscape 1180 · iPad portrait 820 · mobile 390   (<file>:<line>)          ≤5 lines
    Claimed, untested: "<sentence>" (<sha>)
    Next
      stage 1 green → answer the commit question in /flow | stage 2 green → /handoff | <exact git command> | /task <prompt that fixes it>

## Stop conditions

Stop after the report. Don't fix, commit, push or ask, and don't run `/finalize` again yourself.

## Related

CLAUDE.md · docs/GATES.md · `flow` (calls this twice) · `task` (does the work) · `review`
