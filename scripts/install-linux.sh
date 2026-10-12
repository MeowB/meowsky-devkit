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

cp "$repo_root/shell/meowsky.sh" "$meowsky_profile"
for runtime_file in core/paths.sh core/git.sh core/cli.sh \
  features/tree/tree.sh features/md/md.sh features/pdf/pdf.sh \
  features/codex/codex.sh features/workspace/workspace.sh; do
  mkdir -p "$meowsky_dir/$(dirname "$runtime_file")"
  cp "$repo_root/$runtime_file" "$meowsky_dir/$runtime_file"
done

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
