meowsky_codex_prompt() {
  local today="$1" root="$2" tree="$3" git_status="$4" codex_prompt
    codex_prompt="Session context ($today):
Workspace root: $root

Top-level project tree:
$tree

Git status at startup:
$git_status

Answering rules:
- Always mention the file or files we are working on in your answer.

At launch, inspect README.md and any docs you find before giving the orientation, so you understand what the codebase is about. Then give me a scoped orientation from the tree above. Keep it concise: identify the likely main parts, what you inspected first, and any setup files that look important. Do not make code changes unless I ask."
  printf '%s' "$codex_prompt"
}
