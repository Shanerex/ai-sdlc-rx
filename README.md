# Rx AI SDLC

A lean spec-driven feature workflow for Claude Code. A human approves requirements, then the plan, then the result;
agents do the drafting, building and review in between. Small capped files, one `state.md` per feature, scripts instead
of model reasoning wherever a check can be deterministic. Codex support is planned, not in v0.1.

## Install

Requirements: Claude Code, `git`, `jq`, bash (macOS 3.2 is fine). Try it without installing:

    claude --plugin-dir /path/to/rx

or add the repo as a marketplace and install it:

    claude plugin marketplace add /path/to/rx    # or a git URL
    claude plugin install rx@rx

`claude plugin validate /path/to/rx` checks the manifests (it warns that `plugin.json` has no author).

## Quickstart

In the repo you want to work on, on your base branch:

1. `/rx:init` sets up `.rx/`, `docs/knowledge/`, `specs/`, a `.gitignore` entry, and a git pre-commit gate. It reads your
   manifests to write `.rx/config.yml` and `CLAUDE.md` (and `docs/knowledge/architecture.md` for an existing codebase).
   Review the result and commit it on the base branch.
2. `/rx:feature add-health-endpoint` creates the branch and `specs/<id>/`, then asks why / who / done-when.
   Use `--quick` for a small change.
3. `/rx:next` advances one phase and keeps going until it needs you (a question, a gate, or a blocker). Repeat.

`/rx:status` prints the active feature (phase, gates, task progress) from a script; `--all` lists remote feature branches.
After `/rx:init`, `/rx:init --refresh-scripts` re-copies `.rx/scripts` when the plugin is upgraded (`/rx:status` warns when stale).

## The flow

    intake -> requirements -> plan -> build -> verify -> close -> done
                  G1            G2                        G3

- **G1** requirements, **G2** plan (build authorization), **G3** accept. Only an explicit yes from you writes a gate, and
  only the main session may write it; the guard hook refuses subagents.
- `pm` and `architect` work in two passes: a draft plus a brief with the options considered and questions, then your
  answers, then the final file. You see the reasoning and can add suggestions before each gate.
- After G2 `dev` builds every task test-first and stops only for a blocker. `qa` and `security` review in parallel; at most
  two automatic fix loops, then it asks you.
- The quick lane (`--quick`) is `state.md` + `quick.md` with one gate, G2; QA only, no G3.
- Target: 7 human turns per feature. Measured on the dogfood projects: 6 to 7 (full lane), 7 to 8 (quick); see `tests/dogfood/`.

## What is enforced

| where | what |
|---|---|
| PreToolUse hook | no edit of `source_globs` files before G2; `docs/knowledge/architecture.md`, `.rx/config.yml`, `.rx/scripts/**` are human-only; subagents cannot write G1 to G3 |
| Stop hook | in the build phase a red `test_cmd` blocks stopping (timeout, loop guard, cached by file hash) |
| git pre-commit | the same plan-first check on staged files, `rx-check.sh shared`, the test gate; fails if the config or `.rx/scripts` was deleted or rewritten compared with the base branch |
| `rx-check.sh done` | spec hygiene, lane files, final status, all gates, all tasks ticked, `test_cmd` and `lint_cmd` pass |

## Config: `.rx/config.yml`

Flat `key: value` lines. Run `/rx:init` to generate it; a branch cannot change it (`shared` fails).

| key | meaning |
|---|---|
| `test_cmd` | required; the whole test suite, exit 0 = green |
| `test_timeout` | seconds before `test_cmd` is killed (default 600). The Stop hook timeout in `hooks/hooks.json` is 660; raise both together |
| `source_globs` | comma list of code paths that need G2 first, e.g. `src/**,lib/**` (`**` crosses `/`, `*` and `?` do not) |
| `test_globs` | optional; test files outside `source_globs`, included in the test-gate hash |
| `lint_cmd` | optional; run by `rx-check.sh done` |
| `branch_pattern` | feature branch name with one `{id}`, default `feature/{id}` |
| `base_branch` | the branch features start from and merge into, default `main` |
| `enforce_plan_first` | `false` turns off the plan-first guard (default `true`) |
| `version_file`, `version_bump` | `release` (default) protects `version_file` from feature branches; `feature` lets a feature change it |

`security_review` and `feature_id` are written by `/rx:init` but not read in v0.1: security always runs in `verify` mode and
ids come from the name (`UPPER-123` ticket keys as is, otherwise `<date>-<slug>`). There are no coverage keys.

## Merge-safety for teams

A feature branch may touch only code, its own `specs/<id>/`, and NEW files in `docs/knowledge/decisions/` and
`learnings/` (one file per entry, `tags: [a, b]` first line, at most 6 and 5 lines). It must not change `CLAUDE.md`,
`AGENTS.md`, `architecture.md`, `.rx/` or `version_file`. There are no shared counters, so merge-safety holds: parallel branches merge without
non-code conflicts (`tests/test_multidev.sh`). `CLAUDE.md` and `architecture.md` change in their own human PR; on a
branch outside `branch_pattern` the pre-commit gate refuses unless you set `RX_SHARED_OK=1` for that commit.

The local gate is a speed bump (`git commit --no-verify` skips it). Make CI the hard gate: run
`.rx/scripts/rx-check.sh shared <feature-id>` and `rx-check.sh done` from the repo root using the BASE branch's copy of
`.rx/scripts`, not the PR head's, and put `CLAUDE.md`, `docs/knowledge/architecture.md` and `.rx/` under `CODEOWNERS`.
Each developer runs `/rx:init` once per clone to get the pre-commit hook; it is not committed.

## Extending

- Agents: add `agents/<name>.md` (frontmatter `name`, `description`, `tools`, `model`; keep the body to the contract:
  inputs, output file, return format, must / must not). `/rx:next` dispatches the five built-in roles as `rx:<name>`.
- Skills: add `skills/<name>/SKILL.md`. `rx-spec` is the contract for file formats and caps; extend it instead of copying it.
- Hooks: add entries to `hooks/hooks.json` (timeouts are in seconds) calling a script in `scripts/`; scripts exit 0 at once when
  `.rx/config.yml` is absent, use `rx-lib.sh`, and avoid anything newer than bash 3.2.
- Run `tests/run.sh` after any change. Fixtures are plain bash under `tests/`; no bats or shellcheck needed.

## Layout

    .claude-plugin/   plugin.json, marketplace.json      scripts/   rx-*.sh (copied to .rx/scripts by /rx:init)
    agents/ commands/ skills/rx-spec/ hooks/hooks.json   tests/     run.sh, test_*.sh, dogfood/ results
    docs/plans/ docs/tasks/                               design and build record (docs/legacy/ is the v2 playbook)
