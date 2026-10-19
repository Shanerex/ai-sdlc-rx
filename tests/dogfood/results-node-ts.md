# Dogfood results: node-ts, full lane

Run 2026-10-19 on `tests/dogfood/README.md`'s node-ts project, `claude -p` with `--resume` (one session), model sonnet
(architect and security run on opus by their agent files). Feature `add-health-endpoint`: GET `/health` returns 200
`{"status":"ok"}`. The "human" was played by the test driver; every gate answer was an explicit "yes".

## Metrics

`cost` is `total_cost_usd` from the JSON output, which accumulates across the resumed session; `delta` is the step's share.

| # | human turn | cost | delta | agent/model turns | secs |
|---|---|---|---|---|---|
| 1 | init | 0.13 | 0.13 | 5 | 28 |
| 2 | feature | 0.15 | 0.02 | 2 | 14 |
| 3 | intake-answer | 0.17 | 0.03 | 4 | 13 |
| 4 | next-req | 0.24 | 0.06 | 1 | 25 |
| 5 | next-req2 | 0.31 | 0.07 | 1 | 33 |
| 6 | answer-q1 | 0.37 | 0.06 | 2 | 26 |
| 7 | g1-yes | 0.39 | 0.03 | 3 | 17 |
| 8 | next-plan | 0.66 | 0.27 | 2 | 69 |
| 9 | g2-yes | 0.68 | 0.02 | 2 | 11 |
| 10 | next-build | 0.85 | 0.17 | 2 | 57 |
| 11 | next-verify | 1.09 | 0.24 | 3 | 171 |
| 12 | g3-yes | 1.12 | 0.03 | 2 | 15 |
| 13 | next-close | 1.19 | 0.06 | 5 | 24 |

- Human turns: 13 invocations, of which #4 was a failed run (defect 1, below) and #1 is one-time setup. A clean run is 11
  turns after init, against the target of 7. The phases cost: requirements about $0.22 (with the retry), plan $0.27, build $0.17,
  verify $0.24, close $0.06; total $1.19.
- The turn overhead is structural, not model noise: every gate is a "yes" turn followed by a separate `/rx:next` turn (g1, g2,
  g3 each cost two), plus the intake answer and the PM question. See "Candidates for T21".
- Spec sizes (lines, cap): requirements 29 (60), plan 29 (100), tasks 10 (40), review 24 (60), state 27 (30), decision entry 5 (6),
  CLAUDE.md 33 (60). All within cap; `state.md` is close to its cap because every event adds a log line.

## Checks from the task

| check | result |
|---|---|
| Edit before G2 is blocked | yes: real `claude -p` Edit on `src/server.ts` was refused with `rx-guard: G2 (plan approval) is not recorded ...` and the file was untouched |
| A red test blocks Stop | yes: with phase `build` and a broken test the Stop hook fired and the session continued (7 turns) and fixed the test |
| `/rx:status` is correct | yes at `done`: phase, three gates, bump, tasks 4/4, next |
| Every spec file within its cap | yes (above) |
| CLAUDE.md byte-identical before and after | yes (`shasum -a 256` equal) |
| `rx-check.sh done` | rc 0; the human commit then passed the pre-commit gate (guard, shared, tests) |
| `rx:pm` / `rx:architect` / `rx:dev` / `rx:qa` / `rx:security` names, SendMessage resume, no `agent_id` on the main thread | all worked |

## Defects (each fixed test-first)

1. `/rx:next` told agents to read templates from `${CLAUDE_PLUGIN_ROOT}/skills/rx-spec/templates/`. A subagent may not read
   outside the project, so the PM was denied and the run stalled. Fix: templates come from `.rx/scripts/templates/`, the copy
   `/rx:init` makes. Test: `tests/test_commands.sh` (RED, then GREEN).
2. The architect's inputs excluded the code, so on a brownfield feature it planned without reading `src/server.ts` and said so.
   Fix: the spawn prompt carries `source_globs` and the architect may Glob, Grep and Read what the ACs touch. Tests:
   `tests/test_agents.sh`, `tests/test_commands.sh` (RED, then GREEN).

## Observations (not fixed here)

- Nothing commits. The dev agent leaves the tree dirty and `close` says "review the diff and commit"; a human commit worked and
  passed the pre-commit gate.
- `/rx:init` skipped `architecture.md` for a 2-commit repo ("not brownfield"). That is by design but means small repos get no
  architecture seed.
- QA noted it did not prove a clean build (it does not delete `dist/`); non-blocking, and the dev ran a clean build.
- The plan-first guard covers the Edit tools only; a Bash `sed -i` gets past the hook and is caught only by pre-commit.

## Candidates for T21 (trim)

- Chain the phase after a gate: on an explicit yes the orchestrator should continue straight into the next phase's work in the
  same turn (g1 yes then plan draft, g2 yes then build and verify, g3 yes then close). That removes three `/rx:next` turns.
- Fold the intake answer into `/rx:feature` (accept why / who / done-when as arguments) to save a turn.
