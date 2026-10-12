meowsky_md() {
  local target="$1"
  local pandoc
  pandoc="$(command -v pandoc || true)"

  if [ -z "$pandoc" ]; then
    echo "pandoc was not found. Install it with: sudo apt install -y pandoc" >&2
    return 1
  fi

  local target_path
  target_path="$(meowsky_resolve_path "$target")" || {
    echo "Path was not found: $target" >&2
    return 1
  }

  local preview_dir="${TMPDIR:-/tmp}/meowsky-preview"
  mkdir -p "$preview_dir"

  local name
  name="$(basename "${target_path%.*}" | tr -cd '[:alnum:]_.-')"
  if [ -z "$name" ]; then
    name="preview"
  fi

  local html_path="$preview_dir/$name.html"
  pandoc --standalone --from gfm --metadata title=Preview --output "$html_path" "$target_path"

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$html_path" >/dev/null 2>&1 &
  fi
}
