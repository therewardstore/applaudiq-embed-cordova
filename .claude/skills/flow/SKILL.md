---
name: flow
description: >-
  Carries any request in this repo from the first message to a pull request: decides where the
  work belongs and which type it is, settles the ticket and branch, runs /task, asks the developer
  before any commit, runs the second check, /handoff and ship.sh, and ends with what the developer
  does next. Use for every request when TASK_MODE=auto, or when the user types /flow <request>.
---

# Flow — the life of a change

Request: $ARGUMENTS

Nothing here is new work: `/task` plans and builds, `/finalize` judges, `/handoff` explains,
`scripts/agent/ship.sh` pushes. `/flow` is the order they run in and the two moments it stops: the
plan (by work type) and the commit question. It never commits, pushes or skips a hook on its own.

## 0. Where am I, what is this

- **Where.** `git rev-parse --show-toplevel` names the repo (`applaudiq-embed-cordova`). In a workspace
  root (no `scripts/agent/agent.conf` here, several repos below) resolve the repo from the request
  — folder names, or `orbit.json` names and aliases in an Orbit workspace — ask once if unclear,
  then `cd` into it; never edit at the root.
- **Type**, confirmed in one line, decides how much stops you:
  | Type | What it is | Plan | Gates |
  |---|---|---|---|
  | `hotfix` | production is wrong now; one cause, one fix, no new dependency, migration or module crossing (`no-deps,no-migrations,module-scope`) | none: print the read-only diagnosis and go | `low` |
  | `change` | an enhancement or fix inside existing modules | print the plan, continue; stop for approval only on auth, payments, routing infrastructure or shared state | `medium` |
  | `new` | a module, a screen, a flow, a contract | plan approved before the first edit | `high` |
  A hotfix branches from `master` (and is recorded in Orbit when there is one);
  everything else from `master`.

- **Read first**, in full: `CLAUDE.md`, `docs/README.md` and the docs it lists for the touched
  area, the module docs `scripts/git/doc-map.txt` names, and the skills the change touches.

- **Orbit workspace.** Intake is `orbit work <type> [KEY]` (ticket, branch, change record) and
  the ship is `orbit ship`; this skill runs steps 2–4 inside the repo and writes the QA plan and
  verdicts into `.orbit/changes/<KEY>.md`. Root chat: `orbit where` names the repo.

## 1. Ticket and branch

- Never a branch without a ticket, never a guessed ticket: on a ticket branch (`TRS-12587-…`)
  reuse it; with a ticket in the request use it; otherwise ASK (give the ticket, or say `propose`).
- Else, after step 2's diff exists, propose a ticket **from the real change** — project
  `AIQ`, type `Task` (a hotfix is a Bug when
  `getJiraProjectIssueTypesMetadata` lists one, else `Task`), summary ≤70 characters,
  description with the files, the why and the acceptance. Fields: `getJiraIssueTypeMetaWithFields`
  (requiredFieldsOnly false), then ONE question with options for every field it marks required plus the
  house fields the project has — **Ticket Size** (XS trivial · S few files · M several files or two
  repos · L cross-repo with a rollout · XL · Arch; recommend one), **Is Ad-hoc** (Yes/No), and for a
  Bug **Criticality** and **Environment**. Assignee and Dev Assignee = the developer
  (`lookupJiraAccountId` on `git config user.email`; ask only when nothing matches). Show it all, and
  create it only after the developer says `yes`, with the Atlassian MCP (`createJiraIssue`, the fields
  in `additional_fields`, `assignee_account_id`). Never from CI, never without the yes. No Atlassian tools in the session → say so and stop at the proposal: the developer connects
  Atlassian (claude.ai connector, or `/mcp` → Atlassian → Authenticate) or gives a key; never ask for a
  Jira token. Then `git switch -c <KEY>-<slug>` from the base above — before any commit: a header
  ticket on a branch without one is refused.
- Unrelated dirty files are the developer's: list them under `Not staged (yours)`, never stash.

## 2. Build: `/task`

Run `.claude/skills/task/SKILL.md` with the type from step 0; it reads the skills first, plans by
type, builds, and ends with `bash scripts/agent/gates.sh task <risk>` green. Record every path it
created or edited as task-owned in `scripts/agent/state/<KEY>.md` (`owned:` lines).

## 3. Stage 1 — the proposed commit, then the question

Write the approved set — the task-owned paths plus any the developer names — one per line to a
temp file and run `/finalize` (forked), which runs `bash scripts/agent/gates.sh finalize
--proposed <file>`: the snapshot is judged in a detached worktree, never the working tree. A path
staged by someone else outside the set stops here: answer `include` or `unstage` (printed), you
never unstage. Then **ask, and wait**:

    Ready to commit <n> files as `<type>(<KEY>): <subject>` · fingerprint <short>
      commit  — I commit as you (your git identity; no attribution lines)
      done    — you committed by hand; I continue
      stop    — leave everything as it is

Ask it after **every** finished task, in every AI tool. Only `commit` makes you run `git add --
<approved paths>` and `git commit` (hooks on), and it covers that one commit: the next task asks again.
A yes to the ticket, the plan or a fix is not a yes to commit. A file with
unrelated unstaged hunks is staged whole only on `whole`; otherwise stop and ask.

## 4. Stage 2, handoff, ship

1. `bash scripts/agent/gates.sh finalize <sha>` — the committed sha against the stage-1
   fingerprint; a mismatch re-runs every gate, and a failure here means a NEW commit (amend only
   before anything is pushed).
2. `/handoff` — the QA plan into `docs/qa/<KEY>.md` (`.orbit/changes/<KEY>.md` in an Orbit
   workspace; tracked, `.qa/` stays for private notes), committed as `docs(<KEY>): qa plan`.
3. `bash scripts/agent/ship.sh` — with `TASK_PUSH=auto`: `auto` runs it now as the
   developer (push, PR titled `<KEY>: <Summary>` from the Jira summary and reused when one exists;
   a PR opened in GitHub's UI is retitled by the `pr-title` job of `.github/workflows/pr-quality-gates.yml`; resumes from `scripts/agent/state/<KEY>.md`, never
   force-pushes or rebases); `manual` prints the push and PR commands for the developer. Either way
   it prints the Jira comment with its `[friday handoff <fingerprint>]` marker: post it with the
   Atlassian MCP (`addCommentToJiraIssue`) unless the ticket already has a comment with that marker.

## Recovery

- Push rejected by the pre-push hook → print the gate's last lines and the exact fix; no retry loop.
- Base moved / PR conflict → print `git fetch && git rebase origin/master && git push
  --force-with-lease`; the developer runs it.
- `gh` not logged in → the PR link goes in `Next`. No Atlassian MCP → the printed comment goes in `Next`.
- A gate that could not run (exit 2 or 3) is a failure to report, never a pass.
- CI red or stuck → `trs-app ci status`, then `trs-app ci rerun` (the failed jobs) or `trs-app ci cancel
  [--force]`; `trs-app ci run` starts PR quality gates by hand; `trs-app ci review <pr>` (or a PR comment `/arivu review`)
  starts the AI review, `/ci run` re-runs the PR checks. `2a · Push receipt` red = pushed with the hooks off: push again
  with them on, never `--no-verify`. Ask before cancelling a run you did not start.

## Next for the developer — every run ends with it

    Next
      <1–3 exact commands or links: review the PR · merge → Amplify deploys · rollback = redeploy the previous build or a revert PR>

## Related

`task` · `finalize` · `handoff` · `review` · docs/GATES.md · CLAUDE.md
