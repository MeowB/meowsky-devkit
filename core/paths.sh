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
