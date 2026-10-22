---
name: handoff
description: >-
  Writes the QA test plan for a finished change — what changed for the user, where to look, and
  the test cases — into the tracked change record, in a tester's words with no code, and comments
  it on the ticket. Use when /flow reaches it, or when the user types /handoff after /finalize said ready.
disable-model-invocation: true
---

# Handoff — explain the change to QA

Green gates prove code health, not that the feature behaves. QA proves behaviour, and this plan
is what they follow. It is written for a tester who never sees the code: touchpoints and test
criteria, nothing about files, branches or commands. It writes one file and changes nothing else.

## handoff is not finalize

`/finalize` judges whether the change is ready; `/handoff` assumes it is. If `/finalize` hasn't
run in this conversation, or said "not ready", say so and stop.

## 1. Read the change

- The ticket from `git symbolic-ref --short HEAD`; the repo is `applaudiq-embed-cordova`.
- The diff over the range `bash scripts/agent/gates.sh range` prints, and the commit bodies.
- The areas it touches via `scripts/git/doc-map.txt` and their docs.
- The screens and routes the change touches; who owns each.
- New or changed endpoints the change calls.
- The permission key or flag that gates each route.
- The `/finalize` report in this conversation: its behaviour checklist and marks.

## 2. Write the test plan

One Markdown document in exactly this shape:

    # QA — <TICKET>: <the feature, in the words a user would use>
    Test on: <the build QA uses, e.g. dev> · Web (desktop 1440 · iPad landscape 1180 · iPad portrait 820 · mobile 390)<, native apps when the change ships there>
    Ticket: <TICKET> · Design reference: <figma link> | none · Handed off: <date>
    ## What changed for the user
    <2–5 bullets in plain language: what a user now sees or can do>
    ## Where to look
    | Screen or flow | How to get there | What changed there |
    ## Test cases
    | # | Case | Steps | Expected result | Platforms |
    <happy path first, then variations, then error and edge cases: empty and error states,
    invalid input, slow network, back or refresh mid-flow, signed out mid-flow; one user action
    and one visible outcome per row; Platforms is text — the widths or apps that apply, and why>
    ## Accounts, flags and data QA needs
    <account type, flags to switch on, seeded data; "Ask the author for: <thing>" where the
    diff does not say>
    ## Verified by the developer
    <the /finalize checklist items marked confirmed or verified, in user words; else "none">
    ## Not changed — no need to retest
    <neighbouring screens and flows the change does not touch>

Rules. No repo name, branch, commit sha, file path, route path, localhost URL or shell command
anywhere: a tester never sees the code. No checkboxes, result cells or blanks to fill: QA records
outcomes in their own tool; this document only informs. Citations from the diff and the tests
decide what goes in, and are never printed. Every expected result is read from the diff or a test,
never imagined; a gap becomes "Ask the author for: …", never a question in the table. Commit
bodies are claims: they reach "What changed" only when a diff hunk or a test backs them.
Web covers desktop, iPad and mobile widths.
A change with no user-facing effect (docs, tooling, tests) gets the short form: the header, "What
changed for the user: nothing — this change is internal; nothing to test in the product", and
"Not changed".

## 3. Deliver it

Write the document to `docs/qa/<TICKET>.md` (the `## QA` section of `.orbit/changes/<KEY>.md` in an
Orbit workspace; tracked, so QA and CI see it; `.qa/` stays for private notes and is never
migrated) and print the path. Developer confirmations are appended, never rewritten:
`confirmed: <case> @ <sha>`, written by `/flow`'s follow-up commit — with `QA_CONFIRM=advisory`,
`required` means CI's `qa-confirmed` check needs one per case.
Then comment the plan's "What changed" and the PR link on the ticket with the marker
`[friday handoff <fingerprint>]` with the Atlassian MCP (`addCommentToJiraIssue`, the text
`ship.sh` prints); a ticket that already has a comment with that marker gets no second one.
Print the body only if asked. Change nothing else: no source edits; the commit is `/flow`'s.

## Stop conditions

Stop after printing the path and `Next` (`/flow` ships, or: `bash scripts/agent/ship.sh`). Don't
test, don't commit, don't run another command.

## Related

CLAUDE.md · `finalize` (runs before this) · `task` (made the change)
