meowsky_codex_prompt() {
  local today="$1" root="$2" tree="$3" git_status="$4" codex_prompt
    codex_prompt="Project session context:
Workspace root: $root
Today: $today

Top-level project tree:
$tree

Git status at startup:
$git_status

At launch, look in the workspace root for dev/current.md, dev/spec.md, and dev/goal.md. If none exists in dev/, check for current.md, spec.md, and goal.md in development/. In the first location with any of these files, read the files that exist in the order listed and briefly summarize the available current state, spec, and goal. Treat goal.md as session context. Start a Goal only when the user asks.

If neither directory contains any of these files, inspect README.md if present and relevant documentation for the task. Briefly describe the project, its main folders and setup files, and its starting Git state. Treat the Git snapshot as startup context rather than live status."
  printf '%s' "$codex_prompt"
}
