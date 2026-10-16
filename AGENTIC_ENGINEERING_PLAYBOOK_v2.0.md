# Agentic Engineering Playbook
### A setup guide for spec-driven, role-based development with Claude Code (v2)

---

## What this is

A system for structuring AI-assisted development so that:
- Every feature is defined before it is built
- Every role runs in its own context window with its own tools, so boundaries are enforced, not requested
- Every decision is traceable and permanent
- Tests validate every feature before it ships, and a hook refuses to let a feature close on a red suite
- A supervised main session manages the pipeline with human approval at every gate

This playbook is self-contained. A new Claude Code session can read it and set up the entire architecture for any project from scratch.

---

## Why v2

v1.1 worked, but it named things wrong, and the wrong names produced a clumsy folder structure. v2 maps every piece onto the Claude Code primitive built for it.

| v1.1 called it | It actually is | Lives in |
|---|---|---|
| `skills/pm.md`, `skills/architect.md` | Subagents (isolated context, own tools) | `.claude/agents/` |
| `skills/orchestrator.md` | The main session, run by a command | `.claude/commands/orchestrate.md` |
| Standards, spec/handoff/DoD templates, brownfield routine | Skills (progressive disclosure) | `.claude/skills/` |
| "Paste this to set up" prose | Slash commands | `.claude/commands/` |
| "Rules you must never break" | Hooks (deterministic gates) + CLAUDE.md (advisory) | `.claude/settings.json` |
| Flat `handoffs/NNN-from-to.md` | Handoffs co-located with the feature | `specs/NNN-feature/handoffs/` |
| Root-level `ARCHITECTURE.md` etc. | Knowledge layer in one home | `docs/knowledge/` |

The payoff is not cosmetic. Subagents enforce role separation that v1.1 only asked for. Skills stop the playbook from eating context. Hooks turn rules into gates the model cannot skip.

---

## The pipeline

```
Business  →  PM  →  Architect  →  Dev  →  QA  →  PM (close loop)
   ↑                                                      ↓
   └──────────── Main session orchestrates the gates ─────┘
```

Each role is a subagent. Each produces exactly one artifact. The main session (your `/orchestrate` command) holds the dashboard, presents every gate, and waits for your approval before spawning the next role. The orchestrator stays in the main thread on purpose: subagents return only a final message and cannot run an interactive approval loop with you.

---

## Setup instructions for a new project

Save the block below as `.claude/commands/setup-agentic.md`, then run `/setup-agentic`. Or paste it into a Claude Code session directly.

```
Read docs/AGENTIC_ENGINEERING_PLAYBOOK.md.

Set up the agentic engineering architecture for this project:

1. Create CLAUDE.md from the template (AGENTS.md if the tool reads that instead).
   Fill it from what you know about this codebase. Embed the Key invariants and
   @import docs/knowledge/ARCHITECTURE.md.

2. Create the knowledge layer in docs/knowledge/ using the templates:
   ARCHITECTURE.md, DECISIONS.md, LEARNINGS.md. Seed from the codebase.
   ARCHITECTURE.md must not be changed later without human approval.

3. Create the role subagents in .claude/agents/ using the templates.

4. Create the skills in .claude/skills/ using the templates.

5. Create the slash commands in .claude/commands/ using the templates.

6. Create .claude/settings.json and the hook scripts in .claude/hooks/.
   Make the scripts executable.

7. If this is a brownfield project (code already exists):
   Use the brownfield-archaeology skill to backfill specs and seed the knowledge layer.

8. Report: what was created, what needs human input to complete.
```

---

## Folder structure

```
project-root/
├── CLAUDE.md                          Agent memory, loaded every session. @imports ARCHITECTURE.md.
│                                        (AGENTS.md instead for Codex/Cursor and similar tools)
├── .claude/
│   ├── agents/                        THE ROLES (subagents, isolated context)
│   │   ├── business.md
│   │   ├── pm.md
│   │   ├── architect.md
│   │   ├── dev.md
│   │   ├── qa.md
│   │   └── reviewer.md                Optional domain expert
│   ├── skills/                        THE PROCEDURES (progressive disclosure)
│   │   ├── engineering-standards/SKILL.md
│   │   ├── spec-authoring/SKILL.md
│   │   ├── handoff-protocol/SKILL.md
│   │   ├── definition-of-done/SKILL.md
│   │   └── brownfield-archaeology/SKILL.md
│   ├── commands/                      THE ENTRY POINTS
│   │   ├── setup-agentic.md
│   │   ├── orchestrate.md
│   │   ├── feature.md
│   │   └── status.md
│   ├── hooks/                         Hook scripts
│   │   ├── guard-architecture.sh
│   │   ├── gate-tests.sh
│   │   └── check-version-bump.sh
│   └── settings.json                  THE ENFORCEMENT (wires hooks to events)
├── docs/
│   ├── knowledge/                     THE KNOWLEDGE LAYER (one home, not root sprawl)
│   │   ├── ARCHITECTURE.md            Human-approval to change (hook-enforced)
│   │   ├── DECISIONS.md               Append-only, why choices were made
│   │   └── LEARNINGS.md               Append-only, patterns and pitfalls
│   └── AGENTIC_ENGINEERING_PLAYBOOK.md  This file
└── specs/
    └── NNN-feature-name/              Everything about a feature lives here
        ├── requirements.md            PM        (no "-spec" suffix; the folder says spec)
        ├── architecture.md            Architect
        ├── design.md                  Architect
        ├── implementation.md          Dev
        ├── testing.md                 QA
        └── handoffs/                  Co-located, ordered, sortable
            ├── 1-business-to-pm.md
            ├── 2-pm-to-architect.md
            ├── 3-architect-to-dev.md
            ├── 4-dev-to-qa.md
            └── 5-qa-to-pm.md
```

Tests live where your build tool expects them (`src/test/java/...` for Maven or Gradle). The playbook does not invent a flat test path.

---

## CLAUDE.md template

> Use the same template for `AGENTS.md` when the tool reads that file (Codex, Cursor). On those tools you keep the structure but lose subagent isolation, skill disclosure, and hook enforcement. See the closing note.

```markdown
# [Project Name]: Claude Context

## What this project is
[One paragraph: what it does, the stack, the stage (POC / production).]

## What this project is NOT
- [Explicit scope boundaries]

---

## Architecture constraints (always-on)
@docs/knowledge/ARCHITECTURE.md

## How this repo is run agentically
Roles are subagents in .claude/agents/. Procedures are skills in .claude/skills/.
Enforcement is in .claude/settings.json (hooks).
- Start a pipeline: /orchestrate
- Stage a new feature: /feature <short name>
- See status: /status

---

## Key invariants (advisory here, enforced by hooks where noted)
1. Read the knowledge layer before any structural change.
2. ARCHITECTURE.md is human-approval only. [hook: guard-architecture]
3. A feature is not done until the full suite passes and coverage meets threshold. [hook: gate-tests]
4. Never assume an external schema. If it is not derivable from code, STOP and ask.
5. Bump the app version per depth of change. [hook: check-version-bump]
6. DECISIONS.md and LEARNINGS.md are append-only.

---

## Implemented specs
[Table: spec ID | feature | status]

## TODOs (known gaps, not bugs)
[bullets]

## Running locally
\`\`\`bash
[commands]
\`\`\`

## Environment variables
[Table: variable | required | default | notes]
```

---

## Role templates (`.claude/agents/`)

Frontmatter sets `name`, `description`, `tools`, and `model`. The `description` drives delegation, so lead with the trigger. The `tools` list is the real boundary: omit `Edit` and a role physically cannot write code. Put judgment-heavy roles on the strongest model and throughput roles on a faster one.

> Subagents load at session start. After hand-editing an agent file, restart the session or use `/agents` so the change takes effect.

### .claude/agents/business.md
```markdown
---
name: business
description: Business stakeholder. Use to kick off a feature: capture market rationale, success criteria, risks, and priority, and write the opening handoff to PM. Often invoked by /feature.
tools: Read, Grep, Glob, Write
model: sonnet
---
You are the Business Stakeholder for this project.

Skills to use: handoff-protocol.

Do:
- Identify the need, the go-to-market criteria, and any compliance or brand risk.
- Write specs/NNN-feature/handoffs/1-business-to-pm.md: rationale, success criteria,
  risks, priority.

Never:
- Write specs, source, or test files. (You have no Edit tool.)
- Override domain review requirements.
```

### .claude/agents/pm.md
```markdown
---
name: pm
description: Product Manager. Use to turn the business handoff into requirements, scope, and acceptance criteria, and to close the loop after QA. Owns requirements.md only.
tools: Read, Grep, Glob, Write
model: sonnet
---
You are the Product Manager for this project.

Skills to use: spec-authoring, handoff-protocol, definition-of-done.

You own one artifact: specs/NNN-feature/requirements.md.

Do:
- Read the business handoff and the knowledge layer (docs/knowledge/).
- Write requirements.md: problem, user stories, FR-NNN, acceptance criteria
  (checkboxes), explicit out-of-scope. Set status: approved when done.
- Append a DEC-NNN to DECISIONS.md for any notable scope decision.
- At loop-close only: verify the Definition of Done, then update CLAUDE.md.
- Write specs/NNN-feature/handoffs/2-pm-to-architect.md.

Never:
- Write any other spec file, or any source or test file. (No Edit tool.)
- Make technical decisions.
- Edit ARCHITECTURE.md. (Hook-blocked.)
```

### .claude/agents/architect.md
```markdown
---
name: architect
description: Solution Architect. Use after requirements are approved to decide how a feature fits the system and lock API contracts and data models before any code. Owns architecture.md and design.md.
tools: Read, Grep, Glob, Write
model: opus
---
You are the Solution Architect for this project.

Skills to use: spec-authoring, engineering-standards, handoff-protocol.

You own two artifacts: architecture.md and design.md.

Do:
- Read the PM handoff, requirements.md, and the knowledge layer. Do not relitigate
  decisions already in DECISIONS.md.
- Write architecture.md: how it fits the system, component responsibilities,
  key structural decisions.
- Write design.md: API contracts (request/response shapes), data models, edge
  cases, limitations.
- Append a DEC-NNN to DECISIONS.md for each significant choice (rationale +
  alternatives rejected).
- If the design changes a system-level constraint, PROPOSE the ARCHITECTURE.md diff
  in your report and stop. Do not write it.
- Write specs/NNN-feature/handoffs/3-architect-to-dev.md.

Never:
- Write implementation code (propose; Dev implements).
- Write requirements.md, implementation.md, or testing.md.
- Make product scope decisions.
- Edit ARCHITECTURE.md. (Hook-blocked.)
```

### .claude/agents/dev.md
```markdown
---
name: dev
description: Developer. Use after architecture and design are approved to implement the feature, write tests, and run them green. Owns the source and test code and implementation.md.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---
You are the Developer for this project.

Skills to use: engineering-standards, spec-authoring, handoff-protocol.

You own: the source and test code, and implementation.md.

Do:
- Read the Architect handoff and all three approved spec files, plus relevant
  source, before writing anything.
- Break the work into individual task units, kept in the chat (not a file).
  Before each task, show a one-line summary. Implement one, STOP, wait for approval,
  then the next. If rejected, iterate on that task.
- Write tests where the build tool expects them. Run them. Confirm green.
- Append to LEARNINGS.md any pitfall or workaround; a DEC-NNN for any impl choice
  not covered by design.
- Bump the app version per depth of change.
- Write implementation.md and update CLAUDE.md (new endpoints, tables, files).
- Write specs/NNN-feature/handoffs/4-dev-to-qa.md.

Never:
- Write requirements.md, architecture.md, design.md, or testing.md.
- Refactor unrelated code.
- Skip tests. (A Stop hook refuses a red suite.)
- Edit ARCHITECTURE.md. (Hook-blocked.)
```

### .claude/agents/qa.md
```markdown
---
name: qa
description: QA Engineer. The final gate before loop-close. Use after Dev reports green to verify the feature against acceptance criteria and coverage. Owns testing.md. Reports bugs, never fixes them.
tools: Read, Grep, Glob, Bash, Write
model: sonnet
---
You are the QA Engineer for this project.

Skills to use: definition-of-done, engineering-standards, handoff-protocol.

You own: testing.md.

Do:
- Read the Dev handoff and all four prior spec files. Read LEARNINGS.md for prior
  failure modes to re-check.
- Run the full suite. Report the full output.
- Verify every acceptance criterion in requirements.md.
- Write testing.md: case table (ID/test/expected/result), regression notes, gaps.
- Append to LEARNINGS.md any recurring failure mode or coverage gap.
- If all pass: set status approved, write handoffs/5-qa-to-pm.md.
- If any fail: set status draft, write a blocked handoff back to dev with specifics.

Never:
- Fix bugs. Report them. (No Edit tool on source.)
- Write any spec file other than testing.md.
- Change acceptance criteria.
- Edit ARCHITECTURE.md. (Hook-blocked.)
```

### .claude/agents/reviewer.md (optional)
```markdown
---
name: reviewer
description: Domain expert reviewer. Use when a feature touches a sensitive area (payments, auth, data integrity) and needs a second read before it ships. Read-only. Returns prioritized findings.
tools: Read, Grep, Glob
model: opus
---
You are a domain expert reviewer with read-only access.

Review the change against the relevant spec files and the knowledge layer.
Return a prioritized findings list (blocker / major / minor) with file and line
references. Do not modify anything.
```

---

## Skill templates (`.claude/skills/`)

A skill is a folder with a `SKILL.md`. Only the `name` and `description` load until a task matches, so write the description like a trigger. Keep each body under about 500 lines and push long reference material into sibling files. Roles reference skills by name, so the same procedure serves several roles without duplication.

The full bodies for four of these are the standalone sections later in this playbook (Engineering standards, Spec file template, Handoff template, Definition of Done). Each `SKILL.md` below carries the frontmatter and points at that section.

```markdown
# .claude/skills/engineering-standards/SKILL.md
---
name: engineering-standards
description: The enforced engineering rules for this repo (knowledge-layer-first, coverage threshold with per-layer test classes, doc comments everywhere, no assumed external schemas, strict versioning). Use before any structural change, before writing code, and before closing a feature.
---
Body = the "Engineering standards (enforced rules)" section of this playbook.
Stack-specific lines (test-class naming, doc-comment tool, version file) are the
only things to edit when forking for another stack.
```
```markdown
# .claude/skills/spec-authoring/SKILL.md
---
name: spec-authoring
description: How to write any of the five spec files, including shared frontmatter, per-file content, and the Open Questions Gate. Use when creating or updating a file under specs/NNN-feature/.
---
Body = the "Spec file template" and "Open Questions Gate" sections.
```
```markdown
# .claude/skills/handoff-protocol/SKILL.md
---
name: handoff-protocol
description: How to write a handoff between roles and where it lives. Use at the end of any phase to pass work to the next role.
---
Body = the "Handoff template" section. Handoffs live at
specs/NNN-feature/handoffs/N-fromrole-to-torole.md.
```
```markdown
# .claude/skills/definition-of-done/SKILL.md
---
name: definition-of-done
description: The Definition of Done checklist QA verifies and PM confirms before loop-close. Use at the QA gate and before closing any feature.
---
Body = the "Definition of Done" section.
```
```markdown
# .claude/skills/brownfield-archaeology/SKILL.md
---
name: brownfield-archaeology
description: How to backfill specs and the knowledge layer for a codebase that already exists. Use once when adopting this playbook on an existing project.
---
Body = the "Brownfield projects" section.
```

---

## Command templates (`.claude/commands/`)

`setup-agentic.md` is the block under "Setup instructions" above. The other three:

### .claude/commands/orchestrate.md
```markdown
You are the orchestrator. You run the main session and never spawn a role without
my explicit approval.

1. Scan specs/ and build the status dashboard (see "Starting the orchestrator").
2. For the first feature with a phase ready to advance, present the gate.
3. Wait. On approval, spawn the next role subagent via the Task tool. The subagent
   gets a FRESH context, so put everything it needs in the prompt: the feature id,
   the exact spec paths to read, and what to produce.
4. When it returns, verify the knowledge layer and CLAUDE.md were updated. Any
   ARCHITECTURE.md change is only PROPOSED and waits for me.
5. Present the next gate.

Rules:
- Open Questions Gate first, always, before approve/reject.
- After Dev: tests must be green before the QA gate (the gate-tests hook backs this).
- Before loop-close: confirm the Definition of Done.
- Blocked = stop, document the reason in the handoff, report to me.
```

### .claude/commands/feature.md
```markdown
Stage a new feature called: $ARGUMENTS

1. Find the next free NNN. Create specs/NNN-$ARGUMENTS/ and its handoffs/ folder.
2. Spawn the business subagent to write handoffs/1-business-to-pm.md.
3. Tell me it is staged and to run /orchestrate when ready.
```

### .claude/commands/status.md
```markdown
Scan specs/ and print the pipeline status dashboard. Change nothing.
For each feature, show the phase grid and the single next action.
```

---

## Enforcement (hooks)

Hooks are the difference between "Claude should" and "Claude cannot." CLAUDE.md is advisory; a hook runs on every matching event and can block a tool call (PreToolUse exit 2) or refuse to end a turn (Stop exit 2). Start with these three.

### .claude/settings.json
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/guard-architecture.sh" }
        ]
      }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": ".claude/hooks/gate-tests.sh" } ] }
    ]
  }
}
```

### .claude/hooks/guard-architecture.sh
```bash
#!/usr/bin/env bash
# Block writes to the human-approval-only architecture file. Exit 2 denies the call.
path="$(jq -r '.tool_input.file_path // empty')"
case "$path" in
  *docs/knowledge/ARCHITECTURE.md)
    echo "ARCHITECTURE.md is human-approval only. Propose the diff and stop." >&2
    exit 2 ;;
esac
exit 0
```

### .claude/hooks/gate-tests.sh
```bash
#!/usr/bin/env bash
# Refuse to end the turn on a red suite. Swap mvn for your runner. Exit 2 = keep working.
if ! mvn -q test >/tmp/agentic-test.log 2>&1; then
  echo "Test suite is red. Fix it before this turn ends. See /tmp/agentic-test.log" >&2
  exit 2
fi
exit 0
```

### .claude/hooks/check-version-bump.sh
```bash
#!/usr/bin/env bash
# Warn at commit if pom.xml version was untouched. Wire to a PreToolUse Bash matcher.
if git diff --cached --quiet -- pom.xml 2>/dev/null; then
  echo "Reminder: pom.xml version not bumped. Bump per depth of change." >&2
fi
exit 0
```

> Hook matcher syntax and event names shift occasionally. Configure with the `/hooks`
> menu (it validates) and check the current hooks guide rather than trusting this JSON
> verbatim on your installed version.

---

## Knowledge layer (mandatory)

Three files in `docs/knowledge/`. The persistent source of truth for WHY the system is the way it is. It survives across sessions and across subagents. Subagents start fresh, so the orchestrator must point each one at these files in its spawn prompt.

| File | Purpose | Who writes | Change rule |
|---|---|---|---|
| `ARCHITECTURE.md` | Design decisions, constraints, rationale. | Architect proposes | Human approval required. Hook-enforced. |
| `DECISIONS.md` | WHY a choice was made, not just what. | Any role appends | Append-only. |
| `LEARNINGS.md` | Patterns that worked, pitfalls, workarounds. | Any role appends | Append-only. |

### How each role uses the knowledge layer

| Role | Reads | Writes |
|---|---|---|
| Business | ARCHITECTURE (constraints), DECISIONS | (none) |
| PM | All three | DECISIONS (scope) |
| Architect | All three | DECISIONS (design); proposes ARCHITECTURE |
| Dev | All three | LEARNINGS (pitfalls); DECISIONS (impl choices) |
| QA | All three | LEARNINGS (failure modes, coverage gaps) |

### Knowledge layer templates

```markdown
# ARCHITECTURE.md
> Design decisions and constraints. Human-approval only to change.
## System overview
[What the system is, its boundaries, what it is NOT]
## Key components and responsibilities
## Constraints (do not violate)
## Open architectural questions
```
```markdown
# DECISIONS.md
> Append-only. Newest first.
## DEC-NNN: [Title] (YYYY-MM-DD)
- Context: [what forced a decision]
- Decision: [what was chosen]
- Why: [rationale; alternatives rejected]
- Consequences: [trade-offs accepted]
```
```markdown
# LEARNINGS.md
> Append-only. Newest first.
## LEARNING-NNN / PITFALL-NNN: [Title] (YYYY-MM-DD)
- What happened:
- Takeaway:
- How to apply next time:
```

---

## Engineering standards (enforced rules)

These apply to every role and every phase. They are the body of the `engineering-standards` skill, and the hard ones are also in CLAUDE.md as Key invariants. Where a hook enforces a rule it is marked. A stricter project rule wins.

1. **Knowledge layer first.** Read ARCHITECTURE.md, DECISIONS.md, and LEARNINGS.md before any structural change. ARCHITECTURE.md is human-approval only. [hook: guard-architecture]
2. **Test coverage at or above 80%** across controllers, services, repositories, and utils, each with its own dedicated test class (`*ControllerTest`, `*ServiceTest`, `*RepositoryTest`, `*UtilsTest`). Cover the happy path and every meaningful edge case. [hook: gate-tests]
3. **Doc comments everywhere.** Every public class, method, and constructor in source AND test files carries a comment explaining intent. (JavaDoc for this stack.)
4. **Never assume external schemas.** Do not invent the shape of an API response, message payload, or DB schema. If it is not derivable from existing code, STOP and raise an Open Question.
5. **Strict versioning.** Locate the version (`pom.xml` here) and bump patch / minor / major by depth of change. Every shipped feature bumps it. [hook: check-version-bump]

Rules 2 and 3 are written for Java / Spring. When forking for another stack, edit only the `engineering-standards` skill: change the test-class naming, the doc-comment tool, and the version file. Nothing else references the stack.

---

## Open Questions Gate

Whenever a role hits ambiguity it cannot resolve from specs, code, or the knowledge layer, it raises an Open Questions Gate BEFORE the normal approve/reject gate. No approve/reject gate is presented while open questions remain. An unknown external schema (standard 4) always triggers this gate.

Gate order for every role: Open Questions Gate (if any), then Approve/Reject Gate.

```
OPEN QUESTIONS: [Feature] / [phase]

Must be resolved before this phase is approved:
1. [question]. Why it matters: [impact if guessed wrong]
2. ...

(Answer inline. The approve/reject gate will not be presented until these are resolved.)
```

---

## Spec file template (all five files use this structure)

```yaml
---
feature: Human-readable feature name
spec_id: "NNN"
phase: requirements | architecture | design | implementation | testing
owner: PM | Architect | Dev | QA
status: draft | approved
version: "1.0"
entry_criteria:
  - what must be true before this phase starts
exit_criteria:
  - what must be true before the next phase starts
---

# [Phase]: [Feature Name]

[Content specific to this phase, see "What goes in each file"]
```

### What goes in each file

| File | Owner | Contains |
|---|---|---|
| `requirements.md` | PM | Problem, user stories, FR-NNN, acceptance criteria (checkboxes), out of scope |
| `architecture.md` | Architect | How it fits the system, component responsibilities, key structural decisions |
| `design.md` | Architect | API contracts (request/response shapes), data models, edge cases, limitations |
| `implementation.md` | Dev | Files changed, endpoints, migrations, key decisions, where the tests live |
| `testing.md` | QA | Case table (ID / test / expected / result), regression notes, known gaps |

---

## Handoff template

Handoffs live inside the feature, ordered by pipeline position: `specs/NNN-feature/handoffs/N-fromrole-to-torole.md`.

```markdown
# Handoff: [Feature Name]

| Field | Value |
|---|---|
| Feature # | NNN |
| From / To | [Role] → [Role] |
| Status | ready / blocked |
| Date | YYYY-MM-DD |
| Spec | specs/NNN-feature/[phase].md |

## Context
Why this work exists.

## What was done
- decisions or work completed

## What the receiving role must do
1. specific, actionable steps

## Acceptance criteria
- [ ] criterion 1

## Read first
- specs/NNN-feature/[relevant files]

## Do not touch
- explicit list
```

---

## Brownfield projects (code already exists)

This is the body of the `brownfield-archaeology` skill. Run it once when adopting the playbook on an existing repo:

```
Use the brownfield-archaeology skill.

1. Identify every major feature already built.
2. For each, create specs/NNN-feature/ and write all five spec files describing
   what the code ACTUALLY does. Set status: approved (they document reality).
3. Seed the knowledge layer from the code: ARCHITECTURE.md (current design +
   constraints), DECISIONS.md (rationale you can infer), LEARNINGS.md (known
   pitfalls). After this, ARCHITECTURE.md changes need human approval.
4. Update CLAUDE.md to reflect the full current state.
5. Report: features found, spec files created, knowledge seeded, gaps.
```

---

## The test rule

A feature is not done until tests pass. Non-negotiable, and now hook-backed.

- Dev writes tests alongside every implementation.
- Tests live where the build tool expects them, not in a flat per-feature file.
- The `gate-tests` Stop hook refuses to end the turn on a red suite.
- `testing.md` defines what "pass" means; QA verifies it.
- Coverage must meet standard 2: at or above 80% across controllers, services, repositories, and utils, each with its own dedicated test class, every key path and edge case covered. A stricter project rule wins.

---

## Definition of Done

This is the body of the `definition-of-done` skill. A feature is not done, and PM does not close the loop, until every box is checked. QA verifies at its gate; PM confirms at loop-close.

- [ ] All acceptance criteria in `requirements.md` are met
- [ ] Full test suite passes (no regressions, not just the new tests)
- [ ] Coverage meets the threshold across controllers, services, repositories, utils, each with its own dedicated test class
- [ ] Every key path and meaningful edge case has a test
- [ ] Every source and test file carries doc comments
- [ ] No external schema was assumed; every unknown was confirmed with a human
- [ ] App version bumped per depth of change
- [ ] No open questions remain (Open Questions Gate cleared)
- [ ] Knowledge layer updated (DECISIONS.md for decisions, LEARNINGS.md for pitfalls; any ARCHITECTURE.md change approved by a human)
- [ ] CLAUDE.md updated (spec status, new endpoints/files, resolved TODOs)
- [ ] All five spec files are `status: approved`

---

## Starting the orchestrator

Run `/orchestrate`. It scans `specs/`, builds the dashboard, and presents the first gate.

```
PIPELINE STATUS ([date])

Feature              | Req | Arch | Design | Impl | Test | Next action
---------------------|-----|------|--------|------|------|------------------
NNN-feature-name     | ✅  | ✅   | ✅     | ✅   | ✅   | Loop closed
NNN-other-feature    | ✅  | ✅   | ✅     | ✅   | ⬜   | Ready for QA
NNN-new-feature      | ✅  | ⬜   | ⬜     | ⬜   | ⬜   | Ready for Architect
```

Gate format before every subagent spawn:

```
GATE: [Feature], [current phase] → [next phase]

Completed: [summary from the current spec file]
Next role will: [summary of next phase scope]
Files touched: [list]

Approve to proceed? (approve / reject [reason] / skip)
```

---

## What changes in practice

| v1.1 (named wrong) | v2 (named right) |
|---|---|
| Roles called "skills", boundaries were prose | Roles are subagents; boundaries are tool allowlists |
| Whole playbook loaded every phase | Skills load name + description, body on demand |
| "ARCHITECTURE.md needs approval" was a hope | A hook blocks the write |
| "Not done until tests pass" was a hope | A Stop hook refuses a red suite |
| Orchestrator was a "skill" file | Orchestrator is the main session via /orchestrate |
| Setup was copy-paste prose | Setup is /setup-agentic |
| Handoffs flat, collide across features | Handoffs co-located and ordered per feature |
| Knowledge layer loose at root | Knowledge layer in docs/knowledge/ |
| Java standards plus a fake JS test path | Stack-specifics isolated to one skill; no fake path |

---

## Minimum viable start

You do not need all of this on day one. The structure is what compounds.

1. Write `CLAUDE.md`: what exists, the invariants, how to run. (30 min)
2. Create two subagents: `pm` and `dev`. (20 min)
3. Create two skills: `engineering-standards` and `spec-authoring`. (20 min)
4. Add the `guard-architecture` and `gate-tests` hooks. Most enforcement for the least effort. (20 min)
5. Run `/feature your-next-thing`, then `/orchestrate`.
6. Add Architect, QA, Reviewer, the remaining skills, and the version hook as you build confidence.

> The goal is not a perfect system on day one. The goal is a structure every session builds on, that gets stronger with every feature shipped.

---

## If you are not on Claude Code

Codex, Cursor, and similar tools read `AGENTS.md`, not `CLAUDE.md`, and do not have native subagents, skills, or hooks. Keep the folder structure and the discipline, but you lose the three things that make v2 stronger than v1.1: context isolation per role, progressive disclosure of standards, and deterministic enforcement. On those tools, fold the role definitions back into `AGENTS.md` as prose sections, keep the skills as plain reference docs the agent is told to read, and enforce the hard rules in your CI pipeline instead of hooks. The pipeline, specs, knowledge layer, and gates still work. They just run on your discipline rather than the tool's.
