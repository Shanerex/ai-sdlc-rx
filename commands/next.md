---
description: Advance the active rx feature by one phase (requirements, plan, build, verify, close). Dispatches the right agent and stops at each human gate.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/rx-check.sh *), Bash(git config user.name)
---
State of the active feature:

!`${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh`

Pick the row from the `phase:` line (never from `next:`, which is only a hint) and the lane, do exactly that row, then stop and say what `/rx:next` will do next. No feature shown: tell the human to run `/rx:feature`. The lane is `quick` if `specs/<id>/quick.md` exists, else `full`. Contract: skill rx-spec. Templates: `${CLAUDE_PLUGIN_ROOT}/skills/rx-spec/templates/`.

| lane phase | action |
|---|---|
| full intake | Ask why / who / done-when in one AskUserQuestion batch, log the answers in state.md, set `phase: requirements`. |
| full requirements | Protocol A with `rx:pm`, file `requirements.md`, gate `g1`; on yes `phase: plan`. |
| full plan | Protocol A with `rx:architect`, files `plan.md` + `tasks.md`, gate `g2`; on yes `phase: build`. List plan.md "Architecture changes" for the human. |
| full build | Spawn `rx:dev` for `tasks.md`, `plan.md`, `requirements.md`. Afterwards: `status: blocked` means show `next` and ask the human; all tasks ticked means `phase: verify`. |
| full verify | Protocol V with `rx:qa` and `rx:security`. Pass: ask for g3 and the bump; `phase: close`. |
| full close | Protocol C. |
| full done | Report the feature is done; the human opens the PR. |
| quick plan | Show `quick.md`; explicit yes writes `g2`, sets `quick.md` to `status: final`, `phase: build`. |
| quick build | Spawn `rx:dev` for `quick.md`, same outcome as full build. |
| quick verify | Protocol V with `rx:qa` only (Security section: "not run, quick lane"). Pass: ask the bump only (no g3); `phase: close`. |
| quick close | Protocol C. |
| quick done | As full done. |

## Protocol A: two-pass agent and gate
1. If the file is missing, or is `status: draft` and you do not have its brief in this conversation, spawn the agent for pass 1. The prompt names pass 1, the intake or input paths, the template path and the output file(s); for the architect also `docs/knowledge/architecture.md` and `docs/knowledge/decisions/`. Set state `status: draft`.
2. Show the BRIEF. If QUESTIONS is not empty, ask all of them in one AskUserQuestion batch (options and defaults from the brief). If it is empty, skip the question turn.
3. Pass 2: SendMessage the answers to the same agent. If SendMessage is unavailable or the agent is gone, spawn it again with the draft path and the answers. It sets `status: final`.
4. Set state `status: awaiting-human`, show the change summary and ask for the gate. Only an explicit yes in this conversation counts: write `gN: approved:<approver>:<YYYY-MM-DD>`, advance the phase, set `status: draft` and a one-line `next`. Feedback: back to step 3. Anything else: change nothing.

## Protocol V: verify
1. Spawn the reviewers in ONE message so they run in parallel. Prompts: the AC and task paths, and for security the `base_branch` from `.rx/config.yml`. Each writes only its own file: `review.qa.md`, `review.security.md`.
2. Merge them into `review.md` from the template (QA, Security, Verdict; at most 60 lines), set `status: final`, delete both temp files.
3. A failing verdict: at most 2 auto fix loops (spawn `rx:dev` with the blocking IDs only, then repeat from step 1). Still failing: set `status: blocked` and ask the human.
4. A passing verdict: ask the human for g3 (full lane) and `bump: none|patch|minor|major` in one AskUserQuestion. Write `bump`; write g3 only on an explicit yes.

## Protocol C: close
1. Write new knowledge files only, never edit existing ones: a decision (`docs/knowledge/decisions/<YYYY-MM-DD>-<slug>.md`, at most 6 lines) per choice worth keeping from plan.md, a learning (`.../learnings/`, at most 5 lines) per surprise. First line `tags: [a, b]`. None is fine.
2. Set `status: final` on any spec file still `draft` (not state.md).
3. Run `${CLAUDE_PLUGIN_ROOT}/scripts/rx-check.sh done`. Fix what is mechanical; otherwise show the lines and set `status: blocked`.
4. Green: `phase: done`, `status: approved`, `next: open a PR; a human merges`.

## Rules
- Approver is `git config user.name` with spaces and colons replaced by `-`. Only this command writes `g1` to `g3`; the guard blocks subagents.
- Never edit `docs/knowledge/architecture.md`, CLAUDE.md, AGENTS.md or `.rx/`.
- Read only the status block and the files a step names. Agents return at most 15 lines; relay them, do not restate them.
- Append one `## Log` line to state.md per event; near 30 lines collapse the oldest into one summary line.
