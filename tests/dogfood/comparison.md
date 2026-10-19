# Measure, compare, trim (Task 21)

## What was measured

Same feature (`add-health-endpoint`, GET `/health`) on node-ts, full lane, three ways. Costs are `total_cost_usd` for the whole
session (sonnet main thread; architect and security on opus), driver-played human, every gate an explicit yes.

| | T19 run (`results-node-ts.md`) | after chaining (this task) |
|---|---|---|
| invocations incl. `/rx:init` | 13 (1 failed, 1 PM question) | 7 (no PM question) |
| human turns after init | 11 clean | 6 |
| session cost | $1.19 | $1.05 |
| spec bytes (5 spec files) | 6797 | 6325 |

After-chaining run, per step:

| # | human turn | cost | delta | agent/model turns | secs |
|---|---|---|
| 1 | init | 0.12 | 0.12 | 4 | 19 |
| 2 | feature | 0.14 | 0.02 | 2 | 9 |
| 3 | intake | 0.17 | 0.03 | 5 | 18 |
| 4 | next-req | 0.33 | 0.16 | 3 | 78 |
| 5 | g1-yes | 0.61 | 0.28 | 2 | 84 |
| 6 | g2-yes | 0.99 | 0.38 | 5 | 111 |
| 7 | g3-yes | 1.05 | 0.06 | 5 | 26 |

The 7-turn target is met without a PM question (6 after init) and with one it is 7 (the answer is one more turn). Quick lane:
7 to 8 turns after init, $0.57 to $0.62 (`results-java-spring.md`).

## v2 playbook comparison

Not a live run. A faithful v2 run means installing the playbook's six roles, five skills and hooks in a scratch project and
playing six role gates; that was judged not worth the spend for a number the playbook's own rules already determine, so this
is modeled from `docs/legacy/AGENTIC_ENGINEERING_PLAYBOOK_v2.0.md`. Treat the v2 column as an estimate.

| | rx (measured) | v2 playbook (modeled from its rules) |
|---|---|---|
| human turns after setup | 6 to 7 | about 14: `/feature`, `/orchestrate`, an approval before each of 6 role spawns ("never spawn a role without my explicit approval"), 1 to 2 Open Questions Gate rounds, and dev stops after every task for approval (4 tasks here) |
| files written for one feature | 5 spec files + 1 decision entry | 5 spec files + 5 handoffs + DECISIONS/LEARNINGS appends + CLAUDE.md updates the orchestrator must verify |
| spec bytes | 6.3 KB (all within caps) | uncapped; not measured |
| always-loaded project context | CLAUDE.md 1.2 KB, never grown | CLAUDE.md template 1.5 KB plus `@import` of ARCHITECTURE.md, and it grows per feature |
| shipped prompt text | agents 6.0 KB, commands 10.0 KB, skill and templates 5.8 KB, hooks.json 0.6 KB: 22.5 KB | roles, skills, commands and hooks templates 12.5 KB, plus CLAUDE.md and knowledge templates 3.3 KB: 15.8 KB |

The static prompt text of rx is not smaller than v2's templates; the saving is in turns and in files written per feature,
and in what is loaded every turn (a command or an agent loads only when used). That matches the plan's stated priorities.

## Trims made, and not made

- Made, from measured failures: the architect now reads code under `source_globs` (T19), templates come from the project copy
  (T19), and a gate yes continues into the next phase in the same turn (this task: 11 turns down to 6).
- Not made: no agent prompt, template or command text was cut. None of the three runs showed a failure or cost that traces to
  prompt length (cost is dominated by the plan and the build/verify turns, the model's work), and every shipped component was
  used at least once across the lanes: `pm`, `architect`, `dev`, `qa`, `security`, the guard, the Stop gate, `rx-check` (specs,
  shared, done), `/rx:init`, `/rx:feature`, `/rx:next`, `/rx:status` (script-only, exercised in T16 and T19).
  `commands/next.md` (the largest at about 48 lines) is the first place to look if cost becomes the problem.
- Left for a later release: fold the intake answer into `/rx:feature` arguments (one turn), and ask the G2 question straight after
  the quick-lane intake (the java quick run did, node-ts did not).
