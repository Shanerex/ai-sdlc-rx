# rx — AI SDLC Toolkit: Design + Build Plan

## Context

Rex runs a spec-driven, role-based workflow with Claude Code (`AGENTIC_ENGINEERING_PLAYBOOK_v2.0.md`). It works, but it is heavy: 5 spec files plus 5 handoffs per feature, a growing CLAUDE.md, approval after every dev task, skills that restate things the model already knows, and status built by an LLM reading files. That costs tokens and turns.

Goal: a reusable toolkit, **rx**, that:
- follows the standard SDLC with human gates (requirements and plan are finished before any code is written)
- keeps the human involved in design. They see the options considered and the reasoning, and they can add suggestions
- needs fewer human turns than vibe-coding back-and-forth (target ≤7 per feature)
- uses tokens sparingly: small capped files, one state file per feature, script-computed status, short agent returns
- plugs into any stack through one config file
- runs on Claude Code first and Codex second, from **one repo**
- keeps CLAUDE.md / AGENTS.md as static project context only, never grown per feature
- scales to several developers on one repo: a feature branch never edits shared non-code files

Decisions made with Rex:
- PM and Architect are **subagents**. Collaboration happens through a two-pass brief → questions → finalize protocol.
- Build: **approve the plan once**. Dev then runs every task and stops only for a blocker or a deviation from the plan.
- Spec set: **4 lean files + state.md**. `state.md` replaces all handoff files.
- Distribution: **Claude Code plugin + `/rx:init`**. Codex gets an install script.
- **Nothing from the v2 playbook is reused by default.** Modern agents already know engineering standards, OWASP, testing practice, stack conventions and how to explore a brownfield codebase. rx ships only what is *required*.

## Inclusion test (what gets bundled)

A component ships only if it passes at least one of these tests:
1. **Contract:** it encodes something rx-specific the model can't infer, such as file formats, caps, the state protocol, the gate order or the brief format.
2. **Determinism:** it must be enforced, not requested. That makes it a hook or a script.
3. **Isolation:** it needs its own context window or tool boundary. That makes it an agent.

Everything else is dropped: generic standards, security checklists, DoD prose, stack profiles, brownfield procedure, session-start banners and knowledge-search helpers. Project-specific rules belong in that project's own CLAUDE.md or config, not in the toolkit. Projects can still add their own skills on top.

## Bundle (minimal)

| Kind | Name | Test passed | Purpose |
|---|---|---|---|
| Agent | pm | Isolation | Writes requirements.md. Two-pass. Tools: Read, Grep, Glob, Write. |
| Agent | architect | Isolation | Writes plan.md + tasks.md. Two-pass. Tools: Read, Grep, Glob, Write. |
| Agent | dev | Isolation | Implements tasks.md, tests green, ticks tasks. Full tools. |
| Agent | qa | Isolation | Verifies each AC, writes the QA part of review.md. No Edit. |
| Agent | security | Isolation | Reviews the diff, writes the security part of review.md. No Edit. |
| Skill | rx-spec | Contract | The only skill. Templates, line caps, ID rules, state.md protocol, brief format, knowledge-entry format. Shared with Codex. |
| Command | /rx:init | Contract | Writes config, knowledge dir, CLAUDE.md (once) and .gitignore entries. If code already exists, seeds architecture.md from the codebase. |
| Command | /rx:feature | Contract | Creates `specs/<id>/` and state.md and runs intake. `--quick` takes the small-change lane. |
| Command | /rx:next | Contract | The orchestrator. Reads state, runs the next phase, presents the gate. |
| Command | /rx:status | Determinism | Runs rx-status.sh. Costs ~0 tokens. |
| Hook | guard | Determinism | PreToolUse Edit\|Write. Blocks source edits before plan approval and blocks architecture.md edits. |
| Hook | gate-tests | Determinism | Stop + SubagentStop. Refuses a red suite during build, and skips when sources haven't changed. |
| Script | rx-check.sh | Determinism | `specs` (caps/sections), `shared` (merge-safety), `done` (tests, coverage, gates, bump recorded). Used by /rx:next close, pre-commit and CI. |

Agent bodies hold only the rx contract: inputs, the output file, the return format and the must/must-not boundary. That is ≤25 lines each, with no generic advice.

## Repo layout: single repo, root = Claude plugin

The `rx-spec` skill uses the Agent Skills format (`SKILL.md`), which both Claude Code and Codex read. Scripts are portable bash, called by Claude hooks, Codex git hooks and CI alike. Only thin adapters differ.

```
ai-sdlc-rx/
├── .claude-plugin/{plugin.json, marketplace.json}   name "rx" → /rx:init, /rx:feature, /rx:next, /rx:status
├── agents/{pm,architect,dev,qa,security}.md
├── commands/{init,feature,next,status}.md
├── skills/rx-spec/
│   ├── SKILL.md                 caps, IDs, state protocol, brief format (short)
│   └── templates/{requirements,plan,tasks,review,state,quick}.md   loaded only when writing
├── hooks/hooks.json             → ${CLAUDE_PLUGIN_ROOT}/scripts/*
├── scripts/                     bash + git + jq
│   ├── rx-lib.sh                config/state key parsing, branch → feature-id
│   ├── rx-status.sh             dashboard (+ --all: remote feature branches)
│   ├── rx-guard.sh
│   ├── rx-gate-tests.sh
│   └── rx-check.sh              specs | shared | done
├── codex/{AGENTS.md.tmpl, install.sh}
├── tests/                       bash tests for scripts against fixture repos
├── docs/legacy/                 v2.0 playbook kept for reference only
└── README.md                    install, quickstart, how to extend
```

Every script exits 0 immediately when `.rx/config.yml` is absent. Plugin hooks fire in every project with the plugin enabled, so this keeps them harmless elsewhere.

## Per-project footprint (written by /rx:init)

```
.rx/config.yml                   written once; flat keys only
.rx/local/                       gitignored: test-hash cache, active-feature fallback
CLAUDE.md                        static project context, written once (≤60 lines)
docs/knowledge/architecture.md   human-approval only (hook-guarded), ≤80 lines
docs/knowledge/decisions/<date>-<slug>.md   one file per decision (≤6 lines, tags in frontmatter)
docs/knowledge/learnings/<date>-<slug>.md   one file per learning (≤5 lines)
specs/<feature-id>/              ticket key or <date>-<slug>; never a shared counter
  state.md        phase, status, gate approvals + approver, bump level, next action, log (≤30)
  requirements.md (≤60)   plan.md (≤100)   tasks.md (≤40)   review.md (≤60)
```

```
# .rx/config.yml
test_cmd: mvn -q test
coverage_cmd: mvn -q jacoco:report
coverage_min: 80
lint_cmd:
version_file: pom.xml
source_globs: src/**
enforce_plan_first: true
security_review: verify        # verify | plan+verify
feature_id: date-slug          # date-slug | ticket
branch_pattern: feature/{id}
base_branch: main
version_bump: release          # release | feature
```

`/rx:init` fills these by reading the repo. The model detects the stack itself, so no detection script or stack profiles are needed.

## CLAUDE.md / AGENTS.md: static project context only

- Per Claude's official guidance, this file holds project context and loads every turn. Keep it at most 60 lines.
- It contains: what the project is and isn't, stack, run/test commands, conventions, hard invariants, and a 3-line rx pointer.
- It never contains spec tables, endpoint lists, TODOs or per-feature notes. It has no `@import` of architecture.md; agents get that path in their spawn prompt.
- It is written once by `/rx:init`. After that only a human edits it, in its own change. `rx-check.sh shared` fails any feature branch that modifies it.

## Multi-developer merge-safety

Rule: **a feature branch only touches code, its own `specs/<feature-id>/`, and *new* files under `docs/knowledge/{decisions,learnings}/`.**

| Conflict source | rx approach |
|---|---|
| DECISIONS / LEARNINGS appends | One file per entry. Parallel branches add different files. |
| Shared counters | None. Feature IDs come from the ticket or date-slug; local IDs (AC-1, T-1) are fine. |
| CLAUDE.md growth | Init-only. |
| architecture.md | Proposed in `plan.md`; a human applies it in a separate PR. |
| Version file | Bump level recorded in state.md; the real bump happens once at release (`version_bump: feature` for solo repos). |
| Active-feature pointer | Taken from the branch name. The fallback lives in gitignored `.rx/local/`. |
| Index/dashboard files | None committed; computed on demand. |

`rx-check.sh shared` diffs `base_branch...HEAD` and fails on a modified shared non-code file, or on any write into another feature's spec folder. It runs at close, in pre-commit and in CI. Team option: G1/G2 can be approved through a specs-only PR.

## Token rules (in rx-spec + agents)

1. Line caps per file, checked by `rx-check.sh specs`.
2. Never restate another file. Refer by ID (`AC-3`, `T-2`, decision filename).
3. Agents read only the paths in their spawn prompt. Knowledge entries are grepped, never read in bulk.
4. A subagent's final message is ≤15 lines. Detail goes in files.
5. Status and checks are scripts, so they cost zero LLM tokens.
6. Model tiering: architect and security on opus; pm, dev and qa on sonnet.
7. State lives on disk, so any phase resumes after `/clear`.

## Workflow and gates

```
/rx:feature <name>   intake (why / who / done-when, one batch) → state.md
/rx:next             advance one phase:
  requirements  pm pass-1 → brief + questions → you answer → pm pass-2 → G1
  plan          architect pass-1 → options + questions → you answer → pass-2 → G2
                (G2 = build authorization; guard unlocks source edits)
  build         dev runs all tasks, test gate; stops only on blocker/deviation
  verify        qa + security in parallel → review.md → G3 accept / fix (≤2 auto loops)
  close         rx-check.sh done + shared; write new decision/learning files; state=done
/rx:feature --quick  one quick.md (≤30 lines) → one gate → dev → qa → close
/rx:status           script dashboard
```

That is about 6 human turns per feature. Phases with no open questions skip their question turn.

### Two-pass protocol (pm, architect)

- **Pass 1:** read the inputs, write a draft (`status: draft`), and return a BRIEF:
  - `UNDERSTANDING` (2–3 lines)
  - `OPTIONS` (architect: ≤3, one line each with the trade-off, plus a recommendation)
  - `ASSUMPTIONS`
  - `QUESTIONS` (≤5, each with options and a default)
- **Orchestrator:** shows the brief and asks every question in one batch. You answer, override, or add suggestions.
- **Pass 2:** the orchestrator resumes the same subagent with SendMessage, so its context is intact and nothing is re-read. The agent finalizes the file and returns a ≤10-line change summary. Then the gate.
- `plan.md` keeps an "Options considered" section, so the design reasoning stays on record.
- Codex fallback: re-run the agent with the draft path plus your answers.

## Codex adapter

- `install.sh` copies `skills/rx-spec` into the Codex skills directory and `scripts/` into `.rx/scripts/`. It writes a ≤60-line AGENTS.md (same static rules as CLAUDE.md) and installs a git pre-commit hook that runs `rx-guard` (plan-first), `rx-check.sh shared` and the test gate.
- Roles map to Codex custom agents if Codex supports them. Otherwise each phase runs in a fresh session with a role prompt, with state on disk.
- Before building it, check current Codex support for the skills path, subagents, hooks and agent resume.

## Build plan

1. **Foundations.** Run `git init` and move the playbook to `docs/legacy/`. Add the plugin manifests, the `rx-spec` skill and templates, `rx-lib.sh`, `rx-status.sh` and `rx-check.sh`, plus bash tests.
2. **Agents and orchestration.** Add the 5 agents, the commands `/rx:feature` (with `--quick`), `/rx:next` and `/rx:status`, the guard and gate-tests hooks, and `hooks.json`.
3. **Init.** Add `/rx:init`: config, CLAUDE.md, knowledge dirs, .gitignore, and seeding architecture.md for brownfield repos.
4. **Dogfood and tune (Claude).** Use two scratch repos (node-ts, java-spring) with one full feature and one quick change each. Measure human turns, tokens (`/cost`) and file sizes, and compare with a v2-playbook run. Trim prompts and templates further. Add a component only when a measured failure proves it necessary.
5. **Codex adapter.** Verify capabilities, then build `AGENTS.md.tmpl` and `install.sh`. Dogfood one feature.
6. **README.** Install, quickstart, and how to add your own agents, skills or hooks.

Each phase ends with tests green and a commit.

## Verification

- Bash tests against fixture repos cover:
  - status parsing and branch → feature-id resolution
  - the guard blocking before G2 and allowing after
  - the gate-tests skip and block paths
  - `rx-check.sh` specs, shared and done, each pass and fail
  - every script being a no-op without `.rx/config.yml`
- `claude --plugin-dir .` loads cleanly and passes plugin validation.
- End-to-end in a scratch repo:
  - `/rx:init`, then `/rx:feature add-health-endpoint`, then `/rx:next` repeated until done.
  - An Edit before G2 is blocked.
  - A red test blocks Stop.
  - `/rx:status` is correct.
  - Every spec file is within its cap.
  - Human turns ≤7.
  - CLAUDE.md is byte-identical before and after.
- Multi-dev: two parallel feature branches, each adding a decision and a learning, merge into main with zero non-code conflicts. A CLAUDE.md edit on a branch fails `rx-check.sh shared`.
- Codex: `install.sh` into a scratch repo, run one feature, and confirm pre-commit blocks code before the plan is approved.
