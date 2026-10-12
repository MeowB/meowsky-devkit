meowsky_workspace() {
    local current root today tree git_status session name codex_prompt
    current="$(pwd -P)"
    root="$current"

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

    git_status="$(meowsky_git_summary "$root")"

    codex_prompt="$(meowsky_codex_prompt "$today" "$root" "$tree" "$git_status")"

    tmux new-session -d -s "$session" -c "$root" codex -C . "$codex_prompt"
    tmux split-window -h -t "$session:0" -c "$root"
    tmux split-window -v -t "$session:0.1" -c "$root" 'command -v eza >/dev/null 2>&1 && eza -T -L 2 --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" . || find . -maxdepth 2 -type d | sort'
    tmux select-pane -t "$session:0.0"
    tmux attach -t "$session"
}
