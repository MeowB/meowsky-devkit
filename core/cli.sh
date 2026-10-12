meowsky() {
  local action="${1:-}"
  local target="${2:-}"
  local work_root="${WORK_HOME:-$HOME/work}"

  mkdir -p "$work_root"
  work_root="$(cd "$work_root" && pwd -P)"

  if [ "$action" = "md" ] || [ "$action" = "markdown" ]; then
    if [ -z "$target" ]; then
      echo "Usage: meowsky md <file.md>" >&2
      return 1
    fi
    meowsky_md "$target"
    return
  fi

  if [ "$action" = "pdf" ]; then
    if [ -z "$target" ]; then
      echo "Usage: meowsky pdf <file.pdf>" >&2
      return 1
    fi
    meowsky_pdf "$target"
    return
  fi

  if [ "$action" = "./" ] || [ "$action" = "." ]; then
    meowsky_workspace
    return
  fi

  if [ -n "$action" ]; then
    if [ -d "$action" ]; then
      cd "$action" || return
      return
    fi

    if [ -d "$work_root/$action" ]; then
      cd "$work_root/$action" || return
      return
    fi

    echo "Path was not found: $action" >&2
    return 1
  fi

  cd "$work_root" || return
}

alias dev='meowsky'
