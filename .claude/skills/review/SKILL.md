---
name: review
description: >-
  Reviews a diff or a pull request line by line against this repo's rules and prints findings a
  reviewer would leave as comments, split into Must fix and Worth a look. Never edits, commits or
  approves. Use when the user types /review [<range> | <PR number>].
disable-model-invocation: true
context: fork
background: false
agent: general-purpose
allowed-tools: Bash(bash scripts/agent/*) Bash(bash scripts/git/*) Bash(git diff *) Bash(git log *) Bash(gh pr diff *) Bash(gh pr view *)
---

# Review — read like a reviewer, report like one

Target: $ARGUMENTS (a `<base>..<tip>` range, a PR number, or nothing = `bash scripts/agent/gates.sh range`)

The gates prove the mechanics; a review proves the change is the right one, small enough, and
says why. This runs in a fresh context so the author's session never reviews its own work. It
writes nothing and changes nothing.

## 1. Get the diff

    range="$(bash scripts/agent/gates.sh range)"; git diff "$range"      # or: gh pr diff <n>
    bash scripts/agent/scan-diff.sh "$range"                              # the mechanical findings, first

Mechanical lines (`✖`, `⚠`) are quoted, not re-derived. Everything below is what a script cannot see.

## 2. Read every added line against the rubric

| Look for | Rule |
|---|---|
| A reason the reader cannot infer | a comment says why, ≤2 lines; a directive is one line with `-- <why>` |
| New UI | built with this repo's own UI library and its existing components (its UI skill); no new kit or design system without a ticket |
| State read in a render | selectors stable, no object literals as props, keys stable |
| A test that only mirrors the implementation | tests assert behaviour the user sees |
| A doc the change makes wrong | module docs move with the code (`scripts/git/doc-map.txt`) |
| Scope creep | files the ticket does not need; a second change hiding in the first |
| A dependency added | the trailer says why, the size is known, nothing already in the tree does it |

## 3. Report in this shape, then stop

One line per finding, as the comment you would leave, with the exact place. At most 20 lines.

    ## /review — <range | PR #n> · <n> files · <n> findings
    Must fix
      <file>:<line>  <what is wrong> → <the fix>
    Worth a look
      <file>:<line>  <the question or the smaller way>
    Mechanical: <scan-diff summary line>
    Next
      /task <prompt that fixes the Must fix lines> | nothing to fix: /finalize

## Stop conditions

Stop after the report. Don't fix, don't approve, don't run `/review` again yourself.
