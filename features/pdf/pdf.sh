meowsky_pdf() {
  local target="$1"
  local target_path
  target_path="$(meowsky_resolve_path "$target")" || {
    echo "Path was not found: $target" >&2
    return 1
  }

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$target_path" >/dev/null 2>&1 &
  else
    echo "xdg-open was not found. Install it with: sudo apt install -y xdg-utils" >&2
    return 1
  fi
}
