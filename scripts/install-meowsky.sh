#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
meowsky_dir="$config_root/meowsky"
nvim_dir="$config_root/nvim"
meowsky_profile="$meowsky_dir/meowsky.sh"

export MEOWSKY_DEVKIT_HOME="$repo_root"

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y git neovim nodejs npm tmux pandoc xdg-utils eza
else
  echo "apt-get was not found. Install git, neovim, nodejs, npm, tmux, pandoc, xdg-utils, and eza manually." >&2
fi

if ! command -v tree-sitter >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    sudo npm install -g tree-sitter-cli
  fi
fi

mkdir -p "$meowsky_dir" "$nvim_dir"
cp "$repo_root/nvim/init.lua" "$nvim_dir/init.lua"

cat > "$meowsky_profile" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

meowsky_ptree() {
  local level="${1:-3}"

  if command -v eza >/dev/null 2>&1; then
    eza -T -L "$level" --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" .
    return
  fi

  find . -maxdepth "$level" -print | sort
}

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
    local current root today tree session name codex_prompt
    current="$(pwd -P)"

    case "$current/" in
      "$work_root"/*) root="$current" ;;
      *) root="$work_root" ;;
    esac

    if ! command -v tmux >/dev/null 2>&1; then
      echo "tmux was not found. Install it with: sudo apt install -y tmux" >&2
      return 1
    fi

    if ! command -v codex >/dev/null 2>&1; then
      echo "codex was not found. Install the Codex CLI before using meowsky ./." >&2
      return 1
    fi

    cd "$root" || return

    name="$(basename "$root" | tr -cd '[:alnum:]_-')"
    session="meowsky-$name"

    if tmux has-session -t "$session" 2>/dev/null; then
      tmux attach -t "$session"
      return
    fi

    today="$(date +%F)"
    if command -v eza >/dev/null 2>&1; then
      tree="$(eza -T -L 1 --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" .)"
    else
      tree="$(find . -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)"
    fi

    codex_prompt="Session context ($today):
Workspace root: $root

Top-level project tree:
$tree

Start by giving me a scoped orientation of this codebase from the tree above. Keep it concise: identify the likely main parts, what you would inspect first, and any setup files that look important. Do not make code changes unless I ask."

    tmux new-session -d -s "$session" -c "$root" codex -C . "$codex_prompt"
    tmux split-window -h -t "$session:0" -c "$root"
    tmux split-window -v -t "$session:0.1" -c "$root" 'command -v eza >/dev/null 2>&1 && eza -T -L 2 --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" . || find . -maxdepth 2 -type d | sort'
    tmux select-pane -t "$session:0.0"
    tmux attach -t "$session"
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
EOF

chmod +x "$meowsky_profile"

for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ ! -e "$shell_rc" ]; then
    : > "$shell_rc"
  fi

  source_line=". \"$meowsky_profile\""
  if ! grep -Fqx "$source_line" "$shell_rc"; then
    {
      printf '\n# Meowsky Devkit\n'
      printf '%s\n' "$source_line"
    } >> "$shell_rc"
  fi
done

nvim --headless "+Lazy! sync" +qa
nvim --headless "+MasonInstall typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server prisma-language-server" +qa
nvim --headless "+lua require('nvim-treesitter').install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown', 'prisma' }):wait(300000)" +qa

echo
echo "Meowsky bootstrap complete."
echo "Open a new terminal, then run meowsky."
