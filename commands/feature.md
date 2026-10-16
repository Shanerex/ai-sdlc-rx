---
description: Start an rx feature (--quick for a small change). Scaffolds the branch and specs/<id>/state.md, then asks the intake questions.
argument-hint: "[--quick] <name or ticket key>"
---
Start a feature: $ARGUMENTS

1. If `.rx/config.yml` does not exist, tell the human to run `/rx:init` first and stop.
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/rx-new-feature.sh [--quick] '<name>'` with Bash: the name as ONE single-quoted word (escape any `'`), `--quick` only if it was given. It prints `id:`, `branch:` and `lane:`. On a nonzero exit, show its message and stop; never retry with another id.
3. Ask the intake in ONE message, nothing else:
   - full lane: why (the problem), who (the user or system affected), done-when (how we will know)
   - quick lane: what changes and why, done-when
4. When the human answers, record them with Edit and nothing more:
   - full lane: append one log line per answer to `## Log` in `specs/<id>/state.md` (`- <date> intake: why: ...`, keep the file within 30 lines). Set `phase: requirements`, `status: draft`, `next: /rx:next, pm drafts requirements.md`.
   - quick lane: fill `## Change` and the first AC in `specs/<id>/quick.md`. In state.md set `phase: plan`, `status: awaiting-human`, `next: /rx:next, approve quick.md (G2) then dev`.
5. Reply in at most 5 lines: id, branch, lane, and "run /rx:next".

Do not commit, write other spec files, or read the codebase here. Gates `g1` to `g3` stay `none`.
