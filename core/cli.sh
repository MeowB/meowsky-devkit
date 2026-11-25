meowsky_preview_files() {
  local preview="$1" extension="$2"
  shift 2

  local current_directory_only=false
  if [ "$#" -gt 1 ]; then
    current_directory_only=true
  elif [ "$1" = '*' ] || [ "${1,,}" = "*$extension" ]; then
    local -a entries
    mapfile -d '' -t entries < <(
      shopt -u failglob
      shopt -s nullglob
      printf '%s\0' ./*
    )
    set -- "${entries[@]}"
    current_directory_only=true
  fi

  local target path
  local matched=false
  for target in "$@"; do
    if [ "$current_directory_only" = true ]; then
      path="$target"
    else
      path="$(meowsky_resolve_path "$target")" || {
        printf 'Path was not found: %s\n' "$target" >&2
        return 1
      }
    fi
    if [[ -f "$path" && "${path,,}" == *"$extension" ]]; then
      matched=true
      # Prefix local paths so filenames starting with a dash are operands.
      [[ "$path" != -* ]] || path="./$path"
      "$preview" "$path" || return
    fi
  done

  if [ "$matched" = false ]; then
    printf 'No %s files matched.\n' "$extension" >&2
    return 1
  fi
}

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
    meowsky_preview_files meowsky_md .md "${@:2}"
    return
  fi

  if [ "$action" = "pdf" ]; then
    if [ -z "$target" ]; then
      echo "Usage: meowsky pdf <file.pdf>" >&2
      return 1
    fi
    meowsky_preview_files meowsky_pdf .pdf "${@:2}"
    return
  fi

  if [ "$action" = "./" ] || [ "$action" = "." ]; then
    meowsky_workspace
    return
  fi

  if [ -n "$action" ]; then
    if [ -d "$action" ]; then
      meowsky_ensure_project_workspace "$action" || return
      cd "$action" || return
      return
    fi

    if [ -d "$work_root/$action" ]; then
      meowsky_ensure_project_workspace "$work_root/$action" || return
      cd "$work_root/$action" || return
      return
    fi

    echo "Path was not found: $action" >&2
    return 1
  fi

  cd "$work_root" || return
}
