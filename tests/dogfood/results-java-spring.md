# Dogfood results: quick lane (node-ts) and java-spring (full and quick)

Run 2026-10-19 with the same driver as `results-node-ts.md` (one resumed `claude -p` session per run, model sonnet, the human
played by the driver, every gate an explicit yes). `cost` is the session's cumulative `total_cost_usd`, `delta` the step's share.
Maven 3.9.9 was put on `PATH` by the driver; the config `/rx:init` wrote for java-spring is
`test_cmd: mvn -q -B test`, `source_globs: src/main/**`, `test_globs: src/test/**`, `version_file: pom.xml`.

## Quick lane on node-ts (`add-ping-endpoint`)

| # | human turn | cost | delta | agent/model turns | secs |
|---|---|---|---|---|---|
| 1 | init | 0.12 | 0.12 | 4 | 28 |
| 2 | feature | 0.15 | 0.03 | 2 | 25 |
| 3 | intake | 0.19 | 0.04 | 6 | 26 |
| 4 | next-plan | 0.24 | 0.05 | 3 | 18 |
| 5 | g2-yes | 0.27 | 0.03 | 5 | 37 |
| 6 | next-build | 0.42 | 0.15 | 3 | 50 |
| 7 | next-verify | 0.54 | 0.12 | 3 | 58 |
| 8 | bump | 0.57 | 0.03 | 2 | 11 |
| 9 | next-close | 0.62 | 0.04 | 3 | 20 |

9 invocations (8 after init), $0.62. Specs: quick.md 14 (30), review.md 17 (60), state.md 20 (30). `rx-check.sh done` rc 0; the
human commit passed pre-commit. g1 and g3 stay `none` and the security section reads "not run, quick lane".

## Full lane on java-spring (`add-health-endpoint`)

| # | human turn | cost | delta | agent/model turns | secs |
|---|---|---|---|---|---|
| 1 | init | 0.13 | 0.13 | 4 | 17 |
| 2 | feature | 0.15 | 0.03 | 2 | 11 |
| 3 | intake | 0.19 | 0.04 | 3 | 13 |
| 4 | next-req | 0.35 | 0.15 | 3 | 50 |
| 5 | g1-yes | 0.38 | 0.03 | 4 | 13 |
| 6 | next-plan | 0.65 | 0.27 | 3 | 64 |
| 7 | g2-yes | 0.67 | 0.02 | 3 | 15 |
| 8 | next-build | 0.87 | 0.20 | 3 | 56 |
| 9 | next-verify | 1.12 | 0.25 | 7 | 47 |
| 10 | g3-yes | 1.15 | 0.03 | 3 | 10 |
| 11 | next-close | 1.23 | 0.07 | 7 | 26 |

11 invocations (10 after init), $1.23. The PM asked no question this time (intake was complete), so there is no answer turn:
10 human turns after init versus 11 for node-ts. Specs: requirements 24 (60), plan 28 (100), tasks 10 (40), review 21 (60),
state 26 (30), one decision entry. `rx-check.sh done` rc 0 (with Maven on `PATH`; without it `done` reports
`tests: test_cmd failed (exit 127)`, which is the correct message for a missing tool).

## Quick lane on java-spring (`add-ping-endpoint`)

| # | human turn | cost | delta | agent/model turns | secs |
|---|---|---|---|---|---|
| 1 | init | 0.13 | 0.13 | 5 | 23 |
| 2 | feature | 0.14 | 0.02 | 2 | 10 |
| 3 | intake | 0.17 | 0.03 | 4 | 13 |
| 4 | next-plan | 0.20 | 0.03 | 3 | 17 |
| 5 | g2-yes | 0.23 | 0.03 | 5 | 15 |
| 6 | next-build | 0.38 | 0.15 | 3 | 68 |
| 7 | next-verify | 0.50 | 0.11 | 6 | 40 |
| 8 | bump | 0.52 | 0.02 | 2 | 11 |
| 9 | next-close | 0.57 | 0.05 | 3 | 25 |

9 invocations, $0.57. On this run the intake answer already ended with the G2 question, so turn 4 (`/rx:next`) was redundant;
the minimum is 7 turns after init. Specs: quick.md 14, review.md 17, state.md 20; `done` rc 0.

## Findings

- No toolkit defect surfaced in either stack beyond the two fixed after the node-ts run. `rx:init` picks `mvn -q -B test` and
  splits `src/main/**` from `src/test/**`; the guard, gates, merge of qa/security files, the knowledge entry shape and `done` all
  worked unchanged on Maven.
- The quick lane costs about half of the full lane ($0.57 to $0.62 versus $1.19 to $1.23) and 7 to 8 human turns versus 10 to 11.
- The two lanes disagree on when the G2 question is asked: node-ts needed a `/rx:next` after the intake answer, java-spring did not,
  because the model sometimes shows the plan straight after the intake. The command text should say which (see T21).
- `/rx:next` verify asks the bump and g3 in one `AskUserQuestion`; headless sessions have no picker, so the model asked in plain
  text and the answer worked just as well.
- The dev agent did not commit and the close message says "commit it"; it also reported once that nothing was committed when the
  rx init files had in fact been committed by the human. Harmless, but the close text could stop describing git state.
