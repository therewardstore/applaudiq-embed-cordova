# Gates

What runs where. Every stage reads `scripts/agent/agent.conf` through `scripts/agent/gates.sh`;
a gate changes there and in this file, never inside `.husky/`. Where this file and a skill
disagree, the skill wins.

## What runs when

| Stage | Runs | Scope |
|---|---|---|
| pre-commit | the code rules on the staged lines (`scan-diff.sh --cached`) → the file cap (`bash scripts/git/check-file-cap.sh`) → `pnpm typecheck` | staged files, then the whole tree's types |
| commit-msg | the branch ticket filled in (`prepare-commit-msg.sh`), then the header format, ticket match, no attribution trailers or bot identity (`check-commit-msg.sh`) | the message |
| pre-push | branch name (`check-branch.sh`) → commits being pushed (`check-commit-range.sh`) → docs moved (`check-docs-moved.sh`) → `pnpm typecheck` → `pnpm build` → `pnpm run audit:deps` → audit exceptions (`audit-check.sh`) | the branch, new commits, then the tree |
| CI | the `agent-gates` workflow: `bash scripts/agent/gates.sh ci` on the pull request HEAD with the BASE branch's policy, or its own when the base has no `ci` stage yet (branch, commits, secret scan, code rules, cap, docs, lint, types, the full suite, build, size, audit), then the merged result built and tested in `agent-gates-merged`; the AI review is manual (`trs-app ci review <pr>`) | a clean checkout |

## The lint gate

This repo has no lint stage (`GATE_LINT` is empty in `scripts/agent/agent.conf`).

## Tests at pre-push

This app has no test runner wired into the hooks.

## The dependency audit

`pnpm run audit:deps` runs last at pre-push, in `/finalize` and in CI, then `bash scripts/agent/audit-check.sh`,
which holds the tree at zero advisories of any severity. Fix one by upgrading its parent, or by a
`pnpm.overrides` entry when the parent pins a vulnerable line. The one way past it is an advisory no
release fixes yet: its GHSA id goes in `pnpm.auditConfig.ignoreGhsas` and in a row of
`docs/AUDIT-EXCEPTIONS.md` with an end date at most 90 days ahead
(`AUDIT_EXCEPTION_MAX_DAYS`) and the reason it cannot reach users. A fix shipping, the date passing,
a row missing or the package leaving the tree fails the gate, so the list only ever shrinks. A
`pnpm.overrides` entry that crosses a breaking line needs a dated row of its own in the same file.
`.github/workflows/dependency-audit.yml` runs the same check every Monday on the default branch
and opens one issue (label `dependency-audit`) while it fails; `.github/dependabot.yml` raises the
security updates. The audit needs the network, and a new advisory can turn it red on a branch whose
code did not change: that is still a push to hold, not a hook to skip.

## Ranges and exit codes

Every range gate judges the same range: the commits the branch adds over its target, computed once
by `lib.sh` (`origin/master`, else the sha being pushed to, else the upstream, else
the local `master`). `bash scripts/agent/gates.sh range` prints it. No target at all is a
failure with the fix printed, never a pass. Exit codes are shared by every script: 1 a policy failed,
2 bad input (an unknown revision, a bad argument), 3 git or a tool could not run — the hook fails on
all three; only a valid empty diff passes, and says so (`::friday::empty-diff`). At pre-push each
ref git hands the hook gets its own range (a new branch, a force push and a delete included).

## Orbit — the workspace above this repo

This repo sits in an Orbit workspace (`ORBIT=1`, read from `orbit.json`): the repo name, default branch, production ref, ticket pattern and Jira project come from there (`trs-app agents status` says so per key). What friday gives the workspace: `orbit.repo.json` (`trs-app repo-json`), the stage contract
(`ORBIT_STAGE=<stage> bash scripts/agent/gates.sh`, stdin through `FRIDAY_PUSH_REFS`), one
`::friday::gate name=… status=pass|fail|skip role=… ms=…` line per gate and a final
`::friday::verdict` line, `bash scripts/agent/status.sh --json`, and audit lines in
`scripts/agent/state/audit.log` (also `$ORBIT_ROOT/.orbit/log/friday.log`). The hook shim contract
is in `scripts/agent/ci/orbit-hooks.example`; `HOOKS=orbit` makes `session-check` expect it.

## The file cap

A change touching more than 2000 files against `master` is refused by
`bash scripts/git/check-file-cap.sh`; split it. The cap is set high while large clean-ups land; lower it afterwards.

## CI from the terminal

One workflow, **PR checks** (`.github/workflows/pr-quality-gates.yml`), holds every check, numbered so a PR reads
in order: `1 · PR title` (`& description` in an Orbit workspace), `2 · Gates`, `3 · Gates on merged result`, in an
Orbit workspace `4 · Orbit workspace gates` and `5 · Jira update` (it comments on the ticket once the checks pass), and
the **Arivu 💡** review, started only by hand. One CLI over gh drives it (`--ref` defaults to the current
branch; `--review` points status, cancel and rerun at the review's runs):

| Command | What it does |
|---|---|
| `trs-app ci run [--ref b] [--pr n]` | runs PR quality gates by hand on a branch; a PR number retitles that PR |
| `trs-app ci status [--ref b]` | the branch's latest runs and the jobs of the newest |
| `trs-app ci cancel [id] [--ref b] [--force]` | cancels the running runs; `--force` force-cancels one stuck in a post-cancel step |
| `trs-app ci rerun [id] [--ref b] [--all-jobs]` | re-runs the failed jobs of the branch's latest failed run (every job with `--all-jobs`) |
| `trs-app ci review <pr> [--since <sha>\|last] [--model m] [--all]` | starts the Arivu review: after a fix `--since last` reviews only the new commits, `--model` haiku (default), sonnet, opus or fable, `--all` every file; it needs the review secret |

In an Orbit workspace `./orbit ci <verb> <repo>` does the same for any repo from `orbit/`.

## Skipping a hook

`git commit --no-verify` skips pre-commit and commit-msg; pre-push still re-checks every unpushed
commit. `git push --no-verify` skips pre-push as well; after that only CI and review remain.

## Running a hook twice

If `.npmrc` has `enable-pre-post-scripts=true`, an npm script named `precommit` runs before the
repo's `commit` script and the husky hook runs again inside it: name such scripts `verify:*`
instead. lint-staged entries lint the files they receive, never `eslint .`.

## A worked plan

The shape `/task` prints for a `change` ("show the account's points balance on the <Module> view"):

    ## Plan: 1
    Type: change · Risk: medium — a new endpoint consumer · Surfaces: <Module> view + store · Files: …
    Skills read: api-porting, module-structure · Design: none
    Steps: 1) add the endpoint in <Module>/store, ported from the gateway contract, never invented
           2) render it in the view through the design system, copy from the language file
    Not changing: the router, the barrel's public surface
    Evidence: <Module>/store/<entity>Api.ts:<line>, <Module>/views/<View>.tsx:<line>
    Tests: a state test for the selector, a component test for the empty state
    Risks / open questions: none known

A `change` prints this and continues; `new` waits for approval first; a `hotfix` prints the
diagnosis (cause, `file:line`, the one fix) instead.

## Commands

| Command | Proves |
|---|---|
| `pnpm typecheck` | the whole tree typechecks |
| `pnpm build` | it bundles; a broken dynamic import only fails here |
| `pnpm run audit:deps` | no dependency has a moderate-or-worse advisory |
| `bash scripts/agent/audit-check.sh` | no advisory of any severity; each ignored one is an unfixed, dated row in `docs/AUDIT-EXCEPTIONS.md` |
| `bash scripts/agent/scan-diff.sh <range>` | the code rules on the lines a change adds |
| `bash scripts/agent/test-changed.sh <range>` | the changed files' own tests |
| `bash scripts/agent/session-check.sh` | the cheap drift checks, in under a second |
| `bash scripts/agent/session-check.sh full` | the same plus every drift check, for a new session |
| `bash scripts/agent/drift-check.sh` | every /scan drift check; the docs match the tree |
| `bash scripts/agent/fingerprint.sh --short` | the tree /finalize judged; same fingerprint, same verdict |
| `bash scripts/git/check-branch.sh` | the branch can be pushed |
| `bash scripts/git/check-commit-msg.sh <file>` | one message follows the house rules |
| `bash scripts/git/check-commit-range.sh <branch> <range>` | nothing being pushed breaks them, and no bot made it |
| `bash scripts/git/check-docs-moved.sh <range>` | every touched module updated its doc |
| `bash scripts/git/pr-title.sh <branch> <title>` | the PR title as `<TICKET>: <Summary>` |
