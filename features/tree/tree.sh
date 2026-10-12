meowsky_ptree() {
  local level="${1:-3}"

  if command -v eza >/dev/null 2>&1; then
    eza -T -L "$level" --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" .
    return
  fi

  find . -maxdepth "$level" -print | sort
}
