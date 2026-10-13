#!/usr/bin/env bash
# No installer, GUI, tmux session or Codex process is started.
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
for file in "$repo"/core/*.sh "$repo"/features/*/*.sh "$repo"/shell/*.sh "$repo"/scripts/*.sh; do
  "$BASH" -n "$file"
done
git -C "$repo" show "${MEOWSKY_BASELINE_REVISION:-3eb387f66ace380745b68ea78a3c1ce08c22de1d}:scripts/install-linux.sh" | awk '
  /^cat > .* <<\047EOF\047$/ { capture=1; next }
  /^EOF$/ { capture=0 }
  capture { print }
' > "$fixture/baseline.sh"
test -s "$fixture/baseline.sh" || { echo 'Use MEOWSKY_BASELINE_REVISION pointing to the pre-refactor revision.' >&2; exit 1; }
mkdir -p "$fixture/work/project/nested"
printf '# preview\n' > "$fixture/work/project/readme.md"
printf 'pdf fixture\n' > "$fixture/work/project/sample.pdf"
cat > "$fixture/exercise.sh" <<'EOF'
set -euo pipefail
runtime="$1"
fixture="$2"
export WORK_HOME="$fixture/work"
. "$runtime"
pandoc() { printf 'pandoc'; printf ' <%s>' "$@"; printf '\n'; }
xdg-open() { printf 'open <%s>\n' "$1"; }
eza() { printf 'tree fixture\n'; }
codex() { :; }
tmux() {
  if [ "$1" = has-session ]; then return 1; fi
  printf 'tmux'; printf ' <%s>' "$@"; printf '\n'
}
meowsky
printf 'root <%s>\n' "$PWD"
meowsky project
printf 'project <%s>\n' "$PWD"
meowsky md readme.md
wait
meowsky markdown readme.md
wait
meowsky pdf sample.pdf
wait
meowsky ./
meowsky .
meowsky_ptree 3
if meowsky md; then exit 1; fi
if meowsky pdf; then exit 1; fi
if meowsky missing; then exit 1; fi
EOF
"$BASH" "$fixture/exercise.sh" "$fixture/baseline.sh" "$fixture" > "$fixture/baseline.out" 2>&1
"$BASH" "$fixture/exercise.sh" "$repo/shell/meowsky.sh" "$fixture" > "$fixture/current.out" 2>&1
normalize_prompt() {
  awk '
    /^tmux <new-session>/ {
      sub(/ <Session context.*$/, " <PROMPT>")
      sub(/ <Project session context.*$/, " <PROMPT>")
      print
      in_prompt=1
      next
    }
    in_prompt && /^tmux </ { in_prompt=0 }
    !in_prompt { print }
  ' "$1"
}
normalize_prompt "$fixture/baseline.out" > "$fixture/baseline-normalized.out"
normalize_prompt "$fixture/current.out" > "$fixture/current-normalized.out"
diff -u "$fixture/baseline-normalized.out" "$fixture/current-normalized.out"
test "$(grep -c 'Project session context:' "$fixture/current.out")" -eq 2
grep -Fq "Workspace root: $fixture/work/project" "$fixture/current.out"
grep -Fq 'Today: ' "$fixture/current.out"
grep -Fq 'Top-level project tree:' "$fixture/current.out"
grep -Fq 'Git status at startup:' "$fixture/current.out"
grep -Fq 'Give a concise orientation:' "$fixture/current.out"
! grep -Fq 'Answering rules:' "$fixture/current.out"
mkdir -p "$fixture/installed"
cp "$repo/shell/meowsky.sh" "$fixture/installed/meowsky.sh"
for runtime_file in core/paths.sh core/git.sh core/cli.sh \
  features/tree/tree.sh features/md/md.sh features/pdf/pdf.sh \
  features/codex/codex.sh features/workspace/workspace.sh; do
  mkdir -p "$fixture/installed/$(dirname "$runtime_file")"
  cp "$repo/$runtime_file" "$fixture/installed/$runtime_file"
done
"$BASH" "$fixture/exercise.sh" "$fixture/installed/meowsky.sh" "$fixture" > "$fixture/installed.out" 2>&1
diff -u "$fixture/current.out" "$fixture/installed.out"
printf 'PASS: shell syntax, original Linux behavior, copied installation layout.\n'
