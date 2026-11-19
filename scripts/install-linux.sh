#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
meowsky_dir="$config_root/meowsky"
nvim_dir="$config_root/nvim"
meowsky_profile="$meowsky_dir/meowsky.sh"

export MEOWSKY_DEVKIT_HOME="$repo_root"

codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_instructions="$repo_root/features/codex/global-instructions.md"
codex_target="$codex_home/AGENTS.md"

replace_codex_instructions() (
  staged=$(mktemp "$codex_home/.meowsky-agents.XXXXXXXX")
  backup=
  backup_ready=false
  trap 'rm -f -- "$staged"; if ! $backup_ready && [ -n "$backup" ]; then rm -f -- "$backup"; fi' EXIT

  cp -- "$codex_instructions" "$staged"
  if [ -L "$codex_target" ] || [ ! -f "$codex_target" ] ||
    [ "$(sha256sum < "$codex_target")" != "$1" ]; then
    echo "Codex instructions changed while awaiting confirmation. Review $codex_target and rerun setup." >&2
    exit 1
  fi
  backup=$(mktemp "$codex_target.meowsky-backup-XXXXXXXX")
  cp -p -- "$codex_target" "$backup"
  if [ "$(sha256sum < "$backup")" != "$1" ] || [ -L "$codex_target" ] ||
    ! cmp -s "$backup" "$codex_target"; then
    echo "Codex instructions changed during backup. Review $codex_target and rerun setup." >&2
    exit 1
  fi
  backup_ready=true
  echo "Backed up previous Codex instructions: $backup"
  chmod --reference="$backup" "$staged"
  mv -T -- "$staged" "$codex_target"
  echo "Installed Codex global instructions: $codex_target"
)

if [ -L "$codex_target" ]; then
  echo "Global Codex instructions are a link and were preserved: $codex_target" >&2
elif [ -f "$codex_target" ]; then
  if cmp -s "$codex_instructions" "$codex_target"; then
    echo "Codex global instructions are already current: $codex_target"
  else
    original_hash=$(sha256sum < "$codex_target")
    printf 'Current Codex instructions: %s\nMeowsky template: %s\n' "$codex_target" "$codex_instructions"
    printf 'Type replace to back up and replace the existing file, or press Enter to keep it: ' >&2
    if read -r choice && [ "$choice" = replace ]; then
      replace_codex_instructions "$original_hash"
    else
      echo "Existing Codex AGENTS.md was kept: $codex_target" >&2
    fi
  fi
elif [ -e "$codex_target" ]; then
  echo "Expected a file but found another path at $codex_target" >&2
  exit 1
else
  mkdir -p "$codex_home"
  if cp -nT -- "$codex_instructions" "$codex_target" && cmp -s "$codex_instructions" "$codex_target"; then
    echo "Installed Codex global instructions: $codex_target"
  elif [ -e "$codex_target" ] || [ -L "$codex_target" ]; then
    echo "Review $codex_target before rerunning setup. The initial copy could not be verified." >&2
    exit 1
  else
    echo "Could not install Codex global instructions: $codex_target" >&2
    exit 1
  fi
fi

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
