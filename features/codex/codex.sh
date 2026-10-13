meowsky_codex_prompt() {
  local today="$1" root="$2" tree="$3" git_status="$4" codex_prompt
    codex_prompt="Project session context:
Workspace root: $root
Today: $today

Top-level project tree:
$tree

Git status at startup:
$git_status

At launch, inspect README.md if present and relevant documentation for the task. Give a concise orientation: what the project does, its main folders and setup files, and its starting Git state. Treat this snapshot as startup context rather than live status."
  printf '%s' "$codex_prompt"
}
