---
description: Set up rx in this repo: config, CLAUDE.md, knowledge dirs, .gitignore, pre-commit gate; seeds architecture.md for existing code. Safe to rerun; --refresh-scripts updates .rx/scripts only.
argument-hint: "[--refresh-scripts]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/rx-init-files.sh *), Bash(rm -f .rx/local/draft-*), Bash(git log *), Bash(git ls-files *), Bash(git symbolic-ref *), Read, Glob, Grep, Write(.rx/local/draft-*)
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/rx-init-files.sh $ARGUMENTS`

The script above did the deterministic part: directories, .gitignore, `.rx/scripts`, the pre-commit gate. It printed whether `config`, `claude_md` and `architecture` are present or missing.

- If it failed, or `--refresh-scripts` was passed, show its message in one line and stop. If it warned about an existing pre-commit hook, tell the human to call `.rx/scripts/rx-precommit.sh` from it.
- Fill only what is `missing`. Never replace what is `present`.

For each missing file, write the draft to `.rx/local/draft-<name>.md`, then install it with `${CLAUDE_PLUGIN_ROOT}/scripts/rx-init-files.sh <flag> <draft>`. The guard blocks direct writes to the real paths, and the script refuses to overwrite and enforces the caps. On a nonzero exit, fix the draft once and retry; then `rm -f .rx/local/draft-*`.

1. `config` (`--install-config`): read the manifests (package.json, pom.xml, build.gradle, pyproject.toml, go.mod, Cargo.toml) and any CI file, then write flat `key: value` lines, no nesting:
   `test_cmd` (required; the real command, quiet flags), `source_globs` (comma list, e.g. `src/**`), `lint_cmd` (empty if none), `version_file` (the file holding the version, if any), `enforce_plan_first: true`, `security_review: verify`, `feature_id: date-slug`, `branch_pattern: feature/{id}`, `base_branch` (from `git symbolic-ref refs/remotes/origin/HEAD`, else the existing main or master), `version_bump: release`. Add `test_globs` only if tests live outside `source_globs`. There are no coverage keys in v0.1.
2. `claude_md` (`--install-claude-md`): at most 60 lines. What the project is and is not, stack, run and test commands, conventions, hard invariants, then a 3-line rx pointer: workflow is `/rx:feature <name>` then `/rx:next`; specs live in `specs/<id>/`; formats are in the rx-spec skill. No `@import`, no spec tables, endpoint lists, TODOs or per-feature notes.
3. `architecture` (`--install-architecture`), brownfield only (the repo has source files under `source_globs` and more than a few commits; otherwise skip it): at most 80 lines of modules and their jobs, entry points, data flow and boundaries, read from the code. State only what you saw. A human owns this file afterwards.

Finish in at most 8 lines: what was created, what already existed, the pre-commit status, and the next steps. Tell the human to review the diff and commit the rx files on `base_branch` (the pre-commit gate lets that commit through), then run `/rx:feature <name>`. Do not commit anything yourself.
