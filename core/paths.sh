meowsky_resolve_path() {
  local candidate="$1"
  local work_root="${WORK_HOME:-$HOME/work}"

  if [ -e "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [ -e "$work_root/$candidate" ]; then
    printf '%s\n' "$work_root/$candidate"
    return 0
  fi

  return 1
}

meowsky_project_root() {
  local target="$1" git_root
  if command -v git >/dev/null 2>&1; then
    git_root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || git_root=""
    if [ -n "$git_root" ]; then
      (cd "$git_root" && pwd -P)
      return
    fi
  fi
  (cd "$target" && pwd -P)
}

meowsky_ensure_project_workspace() {
  local project_root workspace_path ignore_path
  project_root="$(meowsky_project_root "$1")" || return
  workspace_path="$project_root/.meowsky"
  ignore_path="$project_root/.gitignore"

  if [ -e "$workspace_path" ] || [ -L "$workspace_path" ]; then
    if [ ! -d "$workspace_path" ] || [ -L "$workspace_path" ]; then
      printf 'Project workspace must be a regular directory: %s\n' "$workspace_path" >&2
      return 1
    fi
  fi
  if [ -e "$ignore_path" ] || [ -L "$ignore_path" ]; then
    if [ ! -f "$ignore_path" ] || [ -L "$ignore_path" ]; then
      printf 'Project .gitignore must be a regular file: %s\n' "$ignore_path" >&2
      return 1
    fi
  fi

  if [ ! -d "$workspace_path" ]; then
    mkdir "$workspace_path" || return
  fi
  if [ ! -f "$ignore_path" ]; then
    printf '/.meowsky/\n' > "$ignore_path"
  elif ! grep -Eq '^[[:blank:]]*/?\.meowsky/?[[:space:]]*$' "$ignore_path"; then
    if [ -s "$ignore_path" ] && [ "$(tail -c 1 "$ignore_path" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$ignore_path"
    fi
    printf '/.meowsky/\n' >> "$ignore_path"
  fi
}
