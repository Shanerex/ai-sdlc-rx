# rx Toolkit Task Breakdown

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build rx, a lean, token-sparing AI SDLC toolkit that ships as a Claude Code plugin (with a Codex adapter) from a single repo.

**Architecture:** The repo root is the Claude plugin. Portable bash scripts (`scripts/`) enforce the contract through hooks, git pre-commit and CI. One Agent Skills–format skill (`rx-spec`) defines file formats and protocols. Five role agents and four commands orchestrate the workflow. Per-feature state lives in `specs/<id>/state.md`.

**Tech Stack:** bash, git, jq, Markdown (Agent Skills format). No other runtime dependencies. `bats` and `shellcheck` are not installed on this machine, so tests use a small in-repo bash harness.

**Spec:** `docs/plans/2026-10-16-rx-toolkit-plan.md`

**Status:** REVISED after first review (decisions recorded at the bottom). Nothing has been built. This file is the task list. Each task gets expanded into 2–5 minute TDD steps (failing test, run, implement, run, commit) at execution time. See "How to read this" below.

## How to read this

- Tasks are grouped by the six build phases in the plan. Each phase ends with a green test run and a commit.
- Every task lists **Files**, **Interfaces** (what later tasks rely on), **Done when** (the acceptance check), and a commit message.
- "Test" for a script task means a bash test in `tests/` that runs against a fixture repo created in a temp dir.
- Dependencies are explicit. Tasks inside a phase can run in the listed order. Where two tasks are independent, it says so.

## Global Constraints

Copied from the plan; every task implicitly includes these.

- Ship only components that pass the inclusion test: Contract, Determinism or Isolation. No generic standards, security checklists, stack profiles, banners or knowledge-search helpers.
- Nothing from the v2 playbook is reused by default. It moves to `docs/legacy/` for reference only.
- Line caps: `state.md` ≤30, `requirements.md` ≤60, `plan.md` ≤100, `tasks.md` ≤40, `review.md` ≤60, `quick.md` ≤30, decision entry ≤6, learning entry ≤5, `architecture.md` ≤80, CLAUDE.md / AGENTS.md ≤60.
- Agent bodies ≤25 lines, containing only the rx contract: inputs, the output file, the return format, and the must/must-not boundary.
- A subagent's final message is ≤15 lines (pass-2 change summary ≤10).
- Every script exits 0 immediately when `.rx/config.yml` is absent.
- `.rx/config.yml` uses flat keys only.
- Feature branches touch only code, their own `specs/<feature-id>/`, and new files under `docs/knowledge/{decisions,learnings}/`.
- No shared counters. Feature IDs are a ticket key or `<date>-<slug>`.
- Model tiering: architect and security on opus; pm, dev and qa on sonnet.
- Gate order: G1 requirements, G2 plan (build authorization), G3 accept. Target ≤7 human turns per feature.
- Scope for v0.1: Claude Code only. Coverage checking and the Codex adapter are deferred (see Decisions). `coverage_cmd` and `coverage_min` stay out of the config until coverage is built.
- Claude hooks call plugin scripts via `${CLAUDE_PLUGIN_ROOT}`. Pre-commit and CI call the copy in `.rx/scripts/`, written by `/rx:init`.

## Review Focus

Failure modes the plan implies but does not name. Each is pinned by a test in the owning task.

- `.rx/config.yml` exists but is malformed or missing a key (e.g. no `test_cmd`). Scripts should fail with a one-line message, not crash or silently pass. (T4, T8, T10)
- Branch name does not match `branch_pattern` (detached HEAD, `main`, a rebase in progress). Feature-id resolution should fall back to `.rx/local/active`, then to "no active feature", and the guard must then not block unrelated edits. (T4, T9)
- A hook runs in a repo with no git, or with an empty git history (no `base_branch` yet). `rx-check.sh shared` should report that clearly rather than diff against nothing. (T7)
- `state.md` hand-edited into an invalid shape (missing key, unknown phase). Status and guard should report a parse error instead of treating it as "unapproved" or "approved" by accident. (T4, T9)
- A file path containing spaces or glob characters passed to the guard, and `source_globs` that match nothing. (T9)
- The test command hangs or is very slow. The Stop gate must not wedge the session forever. It needs a timeout and the `stop_hook_active` loop guard. (T10)
- Windows line endings or a trailing-newline difference in a spec file changes the line count at the cap boundary. (T6)

---

## Phase 1 — Foundations

### Task 1: Repo bootstrap and test harness

**Files:**
- Create: `.gitignore`, `tests/run.sh`, `tests/lib/assert.sh`, `tests/lib/fixture.sh`
- Move: `AGENTIC_ENGINEERING_PLAYBOOK_v2.0.md` → `docs/legacy/AGENTIC_ENGINEERING_PLAYBOOK_v2.0.md`
- Test: `tests/test_harness.sh`

**Interfaces:**
- Produces: `tests/run.sh` (runs every `tests/test_*.sh`, exits non-zero if any fail).
- Produces: `assert_eq`, `assert_exit <code> <cmd...>`, `assert_contains <haystack> <needle>` in `assert.sh`.
- Produces: `fixture_repo <dir>`, which creates a git repo on `main` with an initial commit. `fixture_config <dir> [key=value...]` writes `.rx/config.yml` with defaults and overrides.

**Done when:** `git init` done, the playbook is in `docs/legacy/`, `tests/run.sh` passes with the harness self-test, and an intentionally failing assertion is shown to fail the run.

**Commit:** `chore: bootstrap repo, test harness, move v2 playbook to legacy`

### Task 2: Plugin manifests

**Files:**
- Create: `.claude-plugin/plugin.json` (name `rx`), `.claude-plugin/marketplace.json`
- Test: `tests/test_manifests.sh`

**Interfaces:**
- Produces: plugin name `rx`, so commands resolve as `/rx:init`, `/rx:feature`, `/rx:next`, `/rx:status`.

**Done when:** both JSON files parse with `jq`, `name` is `rx`, and `claude --plugin-dir .` loads without error. Check the current plugin manifest schema in the docs first and record the version checked in the commit body.

**Commit:** `feat: add plugin manifests`

### Task 3: `rx-spec` skill and templates

**Files:**
- Create: `skills/rx-spec/SKILL.md`
- Create: `skills/rx-spec/templates/{requirements,plan,tasks,review,state,quick}.md`
- Test: `tests/test_templates.sh`

**Interfaces:**
- Produces the **contract** every later task reads:
  - the line-cap table
  - ID rules: `AC-n` (acceptance criteria), `T-n` (tasks), `R-n` (requirements), local per feature
  - the `state.md` key set (below)
  - the brief format (`UNDERSTANDING / OPTIONS / ASSUMPTIONS / QUESTIONS`)
  - the knowledge-entry format (frontmatter with `tags`, then ≤6 / ≤5 lines)
  - section headings required in each template (consumed by `rx-check.sh specs`)
- `state.md` frontmatter keys: `feature`, `phase` (`intake|requirements|plan|build|verify|close|done`), `status` (`draft|awaiting-human|approved|blocked`), `g1`, `g2`, `g3` (each `none` or `approved:<approver>:<date>`), `bump` (`none|patch|minor|major`), `next` (one-line next action). The body is a log of ≤30 lines.
- `SKILL.md` stays short. Templates are loaded only when writing.

**Done when:** each template is within its own cap, contains the required headings, and `SKILL.md` is ≤80 lines. Test asserts template line counts and heading presence.

**Commit:** `feat: add rx-spec skill and templates`

### Task 4: `rx-lib.sh`

**Files:**
- Create: `scripts/rx-lib.sh`
- Test: `tests/test_lib.sh`

**Interfaces:**
- Produces (sourced by every other script):
  - `rx_root` prints the git toplevel (or `$PWD` if not a git repo)
  - `rx_enabled` returns 0 only if `.rx/config.yml` exists
  - `rx_noop_unless_enabled` runs `exit 0` from the caller when disabled
  - `rx_cfg <key> [default]` prints a flat-yaml value (handles quotes, trailing comments, empty values)
  - `rx_feature_id` resolves the id from the current branch via `branch_pattern`, then `.rx/local/active`, else prints nothing and returns 1
  - `rx_state_get <feature-id> <key>` reads a `state.md` frontmatter key
  - `rx_state_valid <feature-id>` returns non-zero with a one-line reason on a malformed `state.md`
  - `rx_die <msg>` writes to stderr and exits 2

**Done when:** tests cover config parsing (quotes, comments, empty, missing key), branch → id for `feature/{id}`, detached HEAD fallback, `.rx/local/active` fallback, and invalid-state detection. All pass.

**Commit:** `feat: add rx-lib shared shell helpers`

### Task 5: `rx-status.sh`

Depends on: T3, T4.

**Files:**
- Create: `scripts/rx-status.sh`
- Test: `tests/test_status.sh`

**Interfaces:**
- Consumes: `rx_feature_id`, `rx_state_get`.
- Produces: `rx-status.sh [--all]`. It prints one block for the active feature (id, phase, status, gates, bump, next, task progress `n/m` counted from `tasks.md` checkboxes). With `--all` it adds one line per remote feature branch, reading `specs/*/state.md` through `git show origin/<branch>:...` without checking anything out. It also warns on one line when `.rx/scripts/.rx-version` differs from the version in `.claude-plugin/plugin.json` (stale script copy; run `/rx:init --refresh-scripts`).

**Done when:** tests cover the active-feature output, no active feature, `--all` with two remote branches, the stale-version warning (match and mismatch), and the no-op without config. No LLM is involved.

**Commit:** `feat: add rx-status dashboard script`

### Task 6: `rx-check.sh specs`

Depends on: T3, T4. Independent of T5.

**Files:**
- Create: `scripts/rx-check.sh` (dispatcher with the `specs` subcommand only)
- Test: `tests/test_check_specs.sh`

**Interfaces:**
- Produces: `rx-check.sh specs [feature-id]`. It exits 0 or 1 and prints one line per violation (`file: reason`). It checks line caps, required headings, ID uniqueness (`AC-n`, `T-n`), and that each `T-n` in `tasks.md` references an existing `AC-n`. It counts lines with CRLF normalised.
- Exposes the dispatcher shape that T7 and T8 extend: `rx-check.sh <specs|shared|done> [args]`.

**Done when:** each rule has a pass and a fail case, including a file at exactly the cap (pass) and cap+1 (fail), and a CRLF file.

**Commit:** `feat: add rx-check specs`

### Task 7: `rx-check.sh shared`

Depends on: T6.

**Files:**
- Modify: `scripts/rx-check.sh`
- Test: `tests/test_check_shared.sh`

**Interfaces:**
- Produces: `rx-check.sh shared`. It diffs `base_branch...HEAD` and fails on:
  - any modified (not newly added) file under `docs/knowledge/`
  - any change to `CLAUDE.md`, `AGENTS.md`, or the `version_file`
  - any change under another feature's `specs/<other-id>/`
  - any modified existing decision or learning file
  New files under `docs/knowledge/{decisions,learnings}/` and anything in the active feature's `specs/<id>/` are allowed. Everything else is treated as code and allowed.
- Reports clearly when `base_branch` does not exist (no silent pass).

**Done when:** tests cover pass (code + own specs + new knowledge files) and fail (CLAUDE.md edit, architecture.md edit, other feature's spec edit, edited existing decision, version file edit, missing base branch).

**Commit:** `feat: add rx-check shared (merge-safety)`

### Task 8: `rx-check.sh done`

Depends on: T6, T7.

**Files:**
- Modify: `scripts/rx-check.sh`
- Test: `tests/test_check_done.sh`

**Interfaces:**
- Produces: `rx-check.sh done [feature-id]`. It runs `specs` and `shared`, then requires:
  - `test_cmd` exits 0
  - `lint_cmd` (if set) exits 0
  - `g1`, `g2` and `g3` are all `approved:*` in `state.md`
  - `bump` is recorded (not blank)
  - every checkbox in `tasks.md` is ticked
- Coverage is intentionally not checked in v0.1.

**Done when:** a pass case and one fail case per requirement above. Command timeouts are enforced.

**Commit:** `feat: add rx-check done`

**Phase 1 exit:** `tests/run.sh` green. Commit tag `phase-1`.

---

## Phase 2 — Agents and orchestration

### Task 9: `rx-guard.sh` (PreToolUse hook)

Depends on: T4.

**Files:**
- Create: `scripts/rx-guard.sh`
- Test: `tests/test_guard.sh`

**Interfaces:**
- Consumes: hook JSON on stdin (`tool_name`, `tool_input.file_path`). Verify the current hook payload and block-exit contract in the Claude Code docs before writing.
- Produces: exit 0 to allow. Exit 2 with a one-line reason on stderr to block. Rules:
  - block any Edit/Write to `docs/knowledge/architecture.md`
  - if `enforce_plan_first` is true and a feature is active, block edits to paths matching `source_globs` while `g2` is not `approved:*`
  - never block edits under `specs/`, `docs/`, `.rx/`, or when there is no active feature
  - when `state.md` is invalid, block nothing and print a warning

**Done when:** tests cover block before G2, allow after G2, architecture.md always blocked, no active feature allowed, paths with spaces, `source_globs` matching nothing, invalid state warns without blocking, and no-op without config.

**Commit:** `feat: add plan-first and architecture guard`

### Task 10: `rx-gate-tests.sh` (Stop and SubagentStop hook)

Depends on: T4.

**Files:**
- Create: `scripts/rx-gate-tests.sh`
- Test: `tests/test_gate_tests.sh`

**Interfaces:**
- Consumes: hook JSON (`stop_hook_active`) and `.rx/local/test-hash`.
- Produces: exit 0 or 2. It acts only when `phase` is `build`. It hashes the files matching `source_globs` plus the test files. If the hash equals the cached hash of the last green run, it skips. Otherwise it runs `test_cmd` with a timeout. On green it stores the hash. On red it exits 2 with the last ~15 lines of output. When `stop_hook_active` is true it exits 0, so there is no infinite loop.

**Done when:** tests cover skip-on-unchanged, block-on-red, pass-on-green (hash written), not-in-build allowed, `stop_hook_active` allowed, timeout handled, missing `test_cmd` reported, and no-op without config.

**Commit:** `feat: add test gate hook`

### Task 11: `hooks/hooks.json`

Depends on: T9, T10.

**Files:**
- Create: `hooks/hooks.json`
- Test: `tests/test_hooks_json.sh`

**Interfaces:**
- Registers `PreToolUse` (matcher `Edit|Write`) → guard, and `Stop` + `SubagentStop` → gate-tests. Commands use `${CLAUDE_PLUGIN_ROOT}/scripts/...`.

**Done when:** `jq` validates the file, every referenced script exists and is executable, and `claude --plugin-dir .` loads the hooks. Also verify the MultiEdit/NotebookEdit tool names against current docs, and add them to the matcher if needed.

**Commit:** `feat: register guard and test-gate hooks`

### Task 12: Agents `pm` and `architect` (two-pass)

Depends on: T3.

**Files:**
- Create: `agents/pm.md`, `agents/architect.md`
- Test: `tests/test_agents.sh` (frontmatter and body-length lint, shared with T13)

**Interfaces:**
- `pm`: tools Read, Grep, Glob, Write; model sonnet. Inputs: intake from `state.md`, the `requirements.md` template path. Output: `specs/<id>/requirements.md`. Pass 1 writes `status: draft` and returns a BRIEF. Pass 2 finalizes and returns a ≤10-line change summary.
- `architect`: tools Read, Grep, Glob, Write; model opus. Inputs: `requirements.md`, `docs/knowledge/architecture.md`, and grepped decision entries. Output: `plan.md` (with "Options considered") and `tasks.md`. Same two-pass shape. The BRIEF carries ≤3 OPTIONS plus a recommendation. It proposes architecture changes inside `plan.md` and never edits `architecture.md`.
- Both: the final message is ≤15 lines. Neither reads files outside the paths in its spawn prompt.

**Done when:** the lint passes (valid frontmatter, ≤25 body lines, tool list and model match above) and the T3 brief format is referenced, not restated.

**Commit:** `feat: add pm and architect agents`

### Task 13: Agents `dev`, `qa`, `security`

Depends on: T3. Independent of T12.

**Files:**
- Create: `agents/dev.md`, `agents/qa.md`, `agents/security.md`

**Interfaces:**
- `dev`: full tools; model sonnet. It runs every task in `tasks.md` in order and ticks each one. It runs `test_cmd` before each tick. It stops only on a blocker or a deviation from the plan, and then sets `status: blocked` plus `next` in `state.md` and returns ≤15 lines.
- `qa`: no Edit; model sonnet. It verifies each `AC-n` and writes only `specs/<id>/review.qa.md`.
- `security`: no Edit; model opus. It reviews the diff against `base_branch` and writes only `specs/<id>/review.security.md`.
- The two run in parallel and never touch the same file. The orchestrator (T15) merges them into `review.md` and deletes the two temp files. Each temp file is ≤30 lines so the merged `review.md` stays within its 60-line cap.

**Done when:** the shared lint from T12 passes. Both reviewers' tool lists exclude Edit and each names exactly one output file.

**Commit:** `feat: add dev, qa and security agents`

### Task 14: `/rx:feature` (with `--quick`)

Depends on: T3, T4.

**Files:**
- Create: `commands/feature.md`
- Test: `tests/test_feature_scaffold.sh` (tests the scaffold helper only)
- Create (if needed): `scripts/rx-new-feature.sh`, a deterministic scaffold so the command doesn't spend tokens on mkdir and templating

**Interfaces:**
- `/rx:feature <name>`:
  1. computes the id (`date-slug` or ticket key from the arg)
  2. creates the branch from `branch_pattern`
  3. creates `specs/<id>/state.md` from the template (phase `intake`)
  4. asks the intake batch: why / who / done-when
  5. records the answers in `state.md` and sets `next`
- `--quick`: scaffolds `quick.md` instead. The lane is quick.md → one gate → dev → qa → close.

**Done when:** the scaffold script test passes (id generation, collision with an existing id refused, branch created, state valid per `rx_state_valid`). The command text is ≤40 lines.

**Commit:** `feat: add /rx:feature command`

### Task 15: `/rx:next` (orchestrator)

Depends on: T12, T13, T14.

**Files:**
- Create: `commands/next.md`

**Interfaces:**
- Reads `state.md` and dispatches by `phase`:
  - **requirements:** pm pass 1 → show the brief and ask every question in one batch → resume the same agent with SendMessage for pass 2 → G1
  - **plan:** architect, same protocol → G2, which authorizes build and unlocks the guard
  - **build:** dev runs all tasks
  - **verify:** qa and security in parallel (each writes its own temp file) → orchestrator merges into `review.md` and deletes the temp files → G3, with ≤2 auto fix loops
  - **close:** run `rx-check.sh done` and `shared`, write new decision and learning files, set `state=done`
- Skips the question turn when a brief has no open questions.
- Writes gate approvals and the approver into `state.md` only after an explicit human yes.
- Falls back to re-running the agent with the draft path plus the answers when SendMessage resume is unavailable.

**Done when:** a dry-run walk-through over a fixture `specs/<id>/` at each phase shows the right dispatch. Dispatch decisions are table-driven in the command text and verified by reading. Full end-to-end verification happens in T19.

**Commit:** `feat: add /rx:next orchestrator`

### Task 16: `/rx:status` command

Depends on: T5. Independent of T15.

**Files:**
- Create: `commands/status.md`

**Interfaces:**
- Runs `${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh "$@"` and prints the output verbatim. No reasoning, no file reads.

**Done when:** `/rx:status` in a fixture project prints the script output and uses a minimal token count.

**Commit:** `feat: add /rx:status command`

**Phase 2 exit:** `tests/run.sh` green, plugin loads cleanly. Tag `phase-2`.

---

## Phase 3 — Init

### Task 17: `/rx:init`

Depends on: T2, T3, T9–T11.

**Files:**
- Create: `commands/init.md`
- Create: `scripts/rx-init-files.sh`, the deterministic part: dirs, `.gitignore` entries, pre-commit hook install
- Test: `tests/test_init_files.sh`

**Interfaces:**
- Deterministic part (script): creates `.rx/local/`, `docs/knowledge/{decisions,learnings}/`, `specs/`; appends `.rx/local/` to `.gitignore` idempotently; copies `scripts/` into `.rx/scripts/`, copies `skills/rx-spec/templates/` into `.rx/scripts/templates/` (`rx-check.sh specs` derives required headings from them and looks in `<script-dir>/templates` when run from the copy), and writes `.rx/scripts/.rx-version` (the plugin version); installs a pre-commit hook that runs `.rx/scripts/rx-guard.sh`, `.rx/scripts/rx-check.sh shared` and the test gate; refuses to overwrite an existing `.rx/config.yml` or `CLAUDE.md`. `rx-init-files.sh --refresh-scripts` re-copies `scripts/`, the templates and the version stamp without touching anything else.
- Model part (command): reads the repo and fills `.rx/config.yml` (no coverage keys), writes CLAUDE.md (≤60 lines, 3-line rx pointer, no `@import`), and, for brownfield repos, seeds `architecture.md` (≤80 lines) from the codebase.

**Done when:** the script test passes (idempotent on a second run, never clobbers, `.gitignore` deduplicated, `--refresh-scripts` updates a stale copy and the version stamp, the installed pre-commit hook runs from `.rx/scripts/` with no plugin present). In a scratch repo, `/rx:init` produces a valid config and a CLAUDE.md within the cap.

**Commit:** `feat: add /rx:init command`

**Phase 3 exit:** tag `phase-3`.

---

## Phase 4 — Dogfood and tune (Claude)

Add a component only when a measured failure proves it necessary.

### Task 18: Scratch repos

**Files:**
- Create (outside the repo, in the scratchpad): `node-ts` and `java-spring` minimal projects with passing tests.

**Done when:** `test_cmd` runs green in both. No toolkit code changes.

**Commit:** none; fixtures are kept outside the repo (record the setup steps in `tests/dogfood/README.md`).

### Task 19: Full feature on node-ts

Depends on: T15, T17, T18.

- [ ] `/rx:init`, then `/rx:feature add-health-endpoint`, then `/rx:next` repeated to done.
- [ ] Record human turns, `/cost` per phase, and the line count of every spec file.
- [ ] Verify: an Edit before G2 is blocked; a red test blocks Stop; `/rx:status` is correct; every spec file is within its cap; CLAUDE.md is byte-identical before and after (`shasum`).
- [ ] File each defect found as a failing test in `tests/` first, then fix.

**Deliverable:** `tests/dogfood/results-node-ts.md` (metrics and defects).

**Commit:** `test: dogfood node-ts full feature, fixes`

### Task 20: Quick lane on node-ts, then both lanes on java-spring

Depends on: T19.

- [ ] Run `--quick` on node-ts.
- [ ] Run one full feature and one quick change on java-spring (Maven).

**Deliverable:** `tests/dogfood/results-java-spring.md`.

**Commit:** `test: dogfood java-spring and quick lane, fixes`

### Task 21: Measure, compare, trim

Depends on: T19, T20.

- [ ] Compare against a v2-playbook run of the same feature: human turns, tokens, spec bytes.
- [ ] Trim agent prompts, templates and command text. Re-run `tests/run.sh` after each trim.
- [ ] Remove any component that dogfooding showed was never needed.

**Deliverable:** `tests/dogfood/comparison.md`, with the ≤7 turns target met or the gap explained.

**Commit:** `perf: trim prompts and templates from dogfood measurements`

### Task 22: Multi-developer merge test

Depends on: T7, T19.

- [ ] Create two parallel feature branches in a scratch repo. Each adds a decision and a learning.
- [ ] Merge both into `main`. Expected: zero non-code conflicts.
- [ ] On a third branch, edit CLAUDE.md. Expected: `rx-check.sh shared` fails.
- [ ] Automate the above as `tests/test_multidev.sh`.

**Commit:** `test: multi-dev merge-safety scenario`

**Phase 4 exit:** tag `phase-4`.

---

## Phase 5 — Codex adapter (DEFERRED, not in v0.1)

Codex is not available right now, so T23–T25 are parked and skipped. Resume them when Codex is available. T24 must then mirror what T17 already does for Claude projects (copy `scripts/` to `.rx/scripts/` with the version stamp, install the same pre-commit hook).

### Task 23: Verify Codex capabilities

**Files:**
- Create: `codex/CAPABILITIES.md` (≤30 lines, dated, with source links)

**Interfaces:**
- Records the findings that decide T24: the skills directory path, custom agents/subagents, hooks, agent resume, and the AGENTS.md size limit.
- Fallback decision recorded: if custom agents are unsupported, each phase runs in a fresh session with a role prompt and state on disk.

**Done when:** each of the five capabilities is marked supported or unsupported with a link. Stop and check in with the human if Codex cannot run any of the skill, hooks or scripts.

**Commit:** `docs: record Codex capability check`

### Task 24: `AGENTS.md.tmpl` and `install.sh`

Depends on: T23, T17.

**Files:**
- Create: `codex/AGENTS.md.tmpl`, `codex/install.sh`
- Test: `tests/test_codex_install.sh`

**Interfaces:**
- `install.sh <target-repo>` copies `skills/rx-spec` into the Codex skills directory and `scripts/` into `.rx/scripts/`, writes AGENTS.md (≤60 lines, same static rules as CLAUDE.md), and installs the git pre-commit hook (`rx-guard`, `rx-check.sh shared`, test gate). It never overwrites an existing AGENTS.md or hook without a flag, and it is idempotent.

**Done when:** the install test passes against a fixture repo (files present, hook executable, second run is a no-op, AGENTS.md ≤60 lines). The pre-commit hook blocks a source commit before G2.

**Commit:** `feat: add Codex adapter`

### Task 25: Codex dogfood

Depends on: T24.

- [ ] `install.sh` into a scratch repo and run one feature.
- [ ] Confirm that pre-commit blocks code before the plan is approved.
- [ ] Record the findings in `tests/dogfood/results-codex.md`.

**Commit:** `test: Codex dogfood results, fixes`

**Phase 5 exit:** tag `phase-5`.

---

## Phase 6 — README and release

### Task 26: README

**Files:**
- Create: `README.md`

**Contents:** install (Claude plugin; a one-line note that Codex support is planned), a quickstart (`/rx:init` → `/rx:feature` → `/rx:next`), the gate flow, the config key reference, merge-safety rules, and how to add your own agents, skills or hooks. ≤150 lines.

**Done when:** a fresh reader can follow the quickstart in a scratch repo without any other doc (verified by a run).

**Commit:** `docs: add README`

### Task 27: Final verification

- [ ] `tests/run.sh` green.
- [ ] `claude --plugin-dir .` loads and passes plugin validation.
- [ ] Re-run the plan's Verification section, ticking each line item. Skip the Codex line and the coverage checks (both deferred).
- [ ] Tag `v0.1.0` (Claude Code only).

**Commit:** `chore: release v0.1.0`

---

## Decisions from review (2026-10-16)

1. **Scripts outside the plugin:** `/rx:init` copies `scripts/` into `.rx/scripts/` for Claude projects. A version stamp (`.rx/scripts/.rx-version`) lets `rx-status.sh` flag a stale copy, and `--refresh-scripts` updates it. Affects T5, T17.
2. **Coverage:** ignored for v0.1. `rx-check.sh done` does not check it, and the config has no coverage keys. Affects T8, T17, T18, T20.
3. **qa and security output:** each writes its own temp file (`review.qa.md`, `review.security.md`). The orchestrator merges them into `review.md` and deletes the temp files. Affects T13, T15.
4. **Test harness:** plain bash, no `bats`, no `shellcheck`. Affects T1.
5. **Codex:** deferred. No Codex access right now, so Phase 5 (T23–T25) is parked and v0.1 is tested and released on Claude Code only. Affects T26, T27.

## Self-review

- **Spec coverage:** bundle table → T3, T9–T17. Layout → T1–T3, T11, T26 (Codex files deferred with T24). Per-project footprint → T14, T17. Token rules → T3, T12–T13 and measured in T21. Merge-safety → T7, T22. Workflow and gates → T15. Two-pass → T12, T15. Codex → T23–T25 (deferred). Verification list → T19, T22, T27 (Codex and coverage lines skipped).
- **Placeholders:** none intentionally. Per-step TDD detail is deferred to execution time (stated in "How to read this").
- **Names:** `rx_cfg`, `rx_feature_id`, `rx_state_get` and `rx_state_valid` are defined in T4 and used in T5, T9, T10, T14. `rx-check.sh <specs|shared|done>` is defined in T6.
