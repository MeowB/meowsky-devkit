meowsky_git_summary() {
  local root="$1"

  if ! command -v git >/dev/null 2>&1; then
    printf '%s\n' "Git: command not found"
    return
  fi

  (
    cd "$root" || exit 1

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf '%s\n' "Git: not a repository"
      return
    fi

    local branch origin upstream sync changes change_count
    branch="$(git branch --show-current 2>/dev/null || true)"
    if [ -z "$branch" ]; then
      branch="detached at $(git rev-parse --short HEAD 2>/dev/null || printf '%s' unknown)"
    fi

    origin="$(git remote get-url origin 2>/dev/null || true)"
    if [ -z "$origin" ]; then
      origin="none"
    fi

    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    sync="no upstream"
    if [ -n "$upstream" ]; then
      set -- $(git rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null || printf '0 0')
      sync="ahead $1, behind $2 vs $upstream"
    fi

    changes="$(git status --short 2>/dev/null || true)"
    if [ -z "$changes" ]; then
      change_count=0
      changes="clean"
    else
      change_count="$(printf '%s\n' "$changes" | wc -l | tr -d ' ')"
      changes="$change_count changed file(s)"
    fi

    printf 'Branch: %s\n' "$branch"
    printf 'Origin: %s\n' "$origin"
    printf 'Sync: %s\n' "$sync"
    printf 'Working tree: %s\n' "$changes"
  )
}
