#!/usr/bin/env bash
# The installer keeps this file at the original ~/.config/meowsky/meowsky.sh path.
set -euo pipefail
if [ -n "${BASH_VERSION:-}" ]; then
  meowsky_runtime_file="${BASH_SOURCE[0]}"
else
  eval 'meowsky_runtime_file=${(%):-%x}'
fi
meowsky_runtime_root="$(cd "$(dirname "$meowsky_runtime_file")" && pwd -P)"
if [ ! -d "$meowsky_runtime_root/core" ]; then
  meowsky_runtime_root="$(cd "$meowsky_runtime_root/.." && pwd -P)"
fi
. "$meowsky_runtime_root/core/paths.sh"
. "$meowsky_runtime_root/core/git.sh"
for meowsky_feature in tree md pdf codex workspace; do
  if [ -f "$meowsky_runtime_root/features/$meowsky_feature/$meowsky_feature.sh" ]; then
    . "$meowsky_runtime_root/features/$meowsky_feature/$meowsky_feature.sh"
  fi
done
. "$meowsky_runtime_root/core/cli.sh"
unset meowsky_runtime_file meowsky_feature
