---
description: Show the active rx feature (phase, gates, task progress). Add --all for every remote feature branch. Runs a script, no model reasoning.
argument-hint: "[--all]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh *)
---
!`${CLAUDE_PLUGIN_ROOT}/scripts/rx-status.sh $ARGUMENTS`

Print the output above verbatim and nothing else. If it is empty, print only: rx is not set up here, run /rx:init. Do not read files or call tools.
