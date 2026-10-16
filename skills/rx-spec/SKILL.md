---
name: rx-spec
description: rx spec contract - file caps, ID rules, state.md protocol, two-pass brief, knowledge-entry format, token rules.
---
# rx-spec

Contract for every rx agent and command. Templates live in `templates/` (this dir); load one only when writing that file.

## Caps (lines, whole file incl. frontmatter or tags line)

| file | cap |
|---|---|
| `state.md` | 30 |
| `requirements.md` | 60 |
| `plan.md` | 100 |
| `tasks.md` | 40 |
| `review.md` | 60 |
| `quick.md` | 30 |
| `review.qa.md` | 30 |
| `review.security.md` | 30 |
| `architecture.md` | 80 |
| `CLAUDE.md` | 60 |
| `AGENTS.md` | 60 |
| decision entry | 6 |
| learning entry | 5 |

Specs live in `specs/<feature-id>/`. `review.qa.md` and `review.security.md` are temp files from qa/security; the orchestrator merges them into `review.md`, then deletes them.

## Files and IDs

- Every spec file opens with `---` frontmatter, flat `key: value`, no nesting. Frontmatter counts toward the cap.
- Non-state specs have one key: `status: draft|final`.
- The template's `## ` headings are the required `## ` headings: they must be present (extra sections are fine).
- IDs are local to the feature, unique within it, never global counters. Other files cite by ID, never restate.
- `- R-n: text` requirement (requirements.md). `- AC-n: text` acceptance criterion (requirements.md, quick.md).
- Task line, exactly: `- [ ] T-n (AC-n, AC-n): description`. Ticked is `- [x]`. Each T cites at least one existing AC. In tasks.md and quick.md every checkbox line (also `* [ ]`, `1. [ ]`) must be a task line.

## state.md

Frontmatter keys, in order:
- `feature`: feature id
- `phase`: intake|requirements|plan|build|verify|close|done
- `status`: draft|awaiting-human|approved|blocked
- `g1`, `g2`, `g3`: `none` or `approved:<approver>:<YYYY-MM-DD>`
- `bump`: none|patch|minor|major
- `next`: one-line next action

Body is `## Log`, one line per event. Whoever appends near the 30-line cap must collapse older log lines into one summary line; gate facts live in `g1`-`g3`, never delete them.

State protocol:
- state.md is the single source of truth for phase and gates.
- Only the orchestrator writes `g1`-`g3`, and only after an explicit human yes.
- dev updates `status` and `next` and ticks tasks. Any phase resumes from state.md after /clear.

## Lanes (enforced by `rx-check.sh done`)

- Full lane: `state.md`, `requirements.md`, `plan.md`, `tasks.md`, `review.md` all required; `g1`, `g2`, `g3` approved.
- Quick lane (`quick.md` exists): `state.md` + `quick.md` required, `review.md` optional. The only gate is `g2` (pre-build authorization); there is no `g3`. Lanes never mix: `quick.md` excludes `requirements.md`, `plan.md`, `tasks.md`.
- At done every spec file except `state.md` is `status: final` and no `review.qa.md`/`review.security.md` is left. Finalized by: pm (pass 2) `requirements.md`; architect (pass 2) `plan.md`, `tasks.md`; orchestrator `review.md` (when merging qa/security) and `quick.md` (once its gate is approved).

## Two-pass (pm, architect)

- Pass 1: write the file with `status: draft`; return BRIEF:
  - `UNDERSTANDING`: 2-3 lines
  - `OPTIONS`: architect only, at most 3, one line each with trade-off, then a recommendation
  - `ASSUMPTIONS`
  - `QUESTIONS`: at most 5, each with options and a default
- Pass 2 (resumed with the human's answers): finalize the file, set `status: final`, return a change summary of at most 10 lines.

## Knowledge entries

- `docs/knowledge/decisions/<YYYY-MM-DD>-<slug>.md`: at most 6 lines.
- `docs/knowledge/learnings/<YYYY-MM-DD>-<slug>.md`: at most 5 lines.
- One entry per file (a regular file, never a symlink or directory): plain text, first line `tags: [a, b]` (bare, no `---` fences), then the body. The cap counts the whole file, tags line included.
- Entries are grepped by tag, never bulk-read.

## Token rules

- Read only the paths in your spawn prompt. Refer by ID; never restate another file.
- Final message to the caller is at most 15 lines; detail goes in files. Load a template only when writing that file.
