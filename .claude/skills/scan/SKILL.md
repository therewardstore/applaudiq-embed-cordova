---
name: scan
description: >-
  Orients an agent in this repo once per session: reads every skill and governing doc in full,
  checks what they claim against the filesystem, and reports what governs this repo and where
  CLAUDE.md has drifted. Use only when the user types /scan.
disable-model-invocation: true
context: fork
background: false
agent: general-purpose
allowed-tools: Bash(bash scripts/agent/*) Bash(bash scripts/git/*)
---

# Scan — orient, then stop

CLAUDE.md is a claim about this repo, and nothing checks it: a skill lands without a row, a gate
is renamed, a doc keeps naming a file that moved. `/scan` reads the map, checks it against the
filesystem, and reports. It writes nothing, plans nothing and edits nothing. Step 4 is what earns
the command: a new session runs the drift check for you (`session-check.sh full`), a resume only
the cheap part; this skill is the full read plus the drift script. It runs in a forked context so the read never lands in the working
conversation — only the report does.

> **If a future edit strips step 4, delete this skill.** Without the drift check `/scan` is a
> recitation of a file the agent already has.

## `/scan` is not `/task`

`/scan` once per session; `/task` at the start of each change; `/finalize` at the end. `/scan`
says what governs _this repo_; `/task` says what governs _this change_. `/scan` never classifies a
request, never produces a plan and never opens a file under `src/`. If you find yourself writing
steps, stop: that is `/task`.

## 1. Place yourself

    git rev-parse --show-toplevel && git status -sb && git log --oneline -5

Note the branch and whether the tree is dirty; uncommitted work you did not make is the user's,
and you do not touch it.

## 2. Read everything that governs this repo

A deliberate, expensive read — you are invoked to _know_ the rules. State how many lines it
covered.

1. `CLAUDE.md`.
2. Every skill in `.claude/skills/`, end to end. Where a doc and a skill disagree, the skill wins.
3. `docs/README.md`, then every document it lists, starting with `docs/GATES.md`.

## 3. Read the facts no doc can hold current

    cat scripts/agent/agent.conf
    cat .nvmrc
    grep -E '"(@therewardstore/[a-z-]+|react|typescript)":' package.json

## 4. Check the map against the territory

    bash scripts/agent/drift-check.sh

Every check is a function in that script; it prints one line per mismatch as
`<check> → <file:line>`. Report its lines and add no check of your own: a check that is not in the
script does not exist here. A new check goes through `/task`, into the script, together with the
doc fix that makes it pass. Fix nothing — a fix is a change, and a change goes through `/task`.

## 5. Report in this shape, then stop

Twenty lines at most. Verdict first; each drift line is where → what is wrong → the fix; no
paragraph per skill, no restating docs, no `Note:`. Lines of 120 characters or fewer.

    ## /scan — <repo> @ <branch> · <sha> · <n> dirty · <n> checks · read <n> files
    ✓ No drift — the docs match the repo | ✖ <n> drifts — the docs disagree with the repo
      <file>:<line>  <what the doc says, and what the repo has> → <the fix>
    What governs this repo
      Stack   <one line from step 3>
      Skills  <n> — <names>
      Gates   <the commands in agent.conf, one line>
      No skill yet: <modules>                  (omit when none)
    Next
      /task fix the <n> drifted docs above     (with no drift: /task <your change>)

## Stop conditions

Stop after the report. Do not begin a task, do not fix drift, do not invoke another command.

## Related

CLAUDE.md · docs/README.md · `task` — the per-change flow this hands off to · `finalize` — the
end-of-task check
