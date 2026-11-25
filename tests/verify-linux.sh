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
test -d "$fixture/work/project/.meowsky"
test "$(grep -Fxc '/.meowsky/' "$fixture/work/project/.gitignore")" -eq 1
printf 'user reference\n' > "$fixture/work/project/.meowsky/reference.txt"
test "$(cat "$fixture/work/project/.meowsky/reference.txt")" = 'user reference'
readme_hash="$(sha256sum "$fixture/work/project/readme.md")"
rm -rf -- "$fixture/work/project/.meowsky"
test "$(sha256sum "$fixture/work/project/readme.md")" = "$readme_hash"
normalize_preview_paths() {
  sed -E 's#(/meowsky-preview/)preview\.[[:alnum:]]+/#[PREVIEW_DIR]/#g; s#/meowsky-preview/#[PREVIEW_DIR]/#g' "$1"
}
normalize_prompt() {
  normalize_preview_paths "$1" | awk '
    /^tmux <new-session>/ {
      sub(/ <Session context.*$/, " <PROMPT>")
      sub(/ <Project session context.*$/, " <PROMPT>")
      print
      in_prompt=1
      next
    }
    in_prompt && /^tmux </ { in_prompt=0 }
    !in_prompt { print }
  '
}
normalize_prompt "$fixture/baseline.out" > "$fixture/baseline-normalized.out"
normalize_prompt "$fixture/current.out" > "$fixture/current-normalized.out"
diff -u "$fixture/baseline-normalized.out" "$fixture/current-normalized.out"
test "$(grep -c 'Project session context:' "$fixture/current.out")" -eq 2
grep -Fq "Workspace root: $fixture/work/project" "$fixture/current.out"
grep -Fq 'Today: ' "$fixture/current.out"
grep -Fq 'Top-level project tree:' "$fixture/current.out"
grep -Fq 'Git status at startup:' "$fixture/current.out"
grep -Fq 'dev/current.md, dev/spec.md, and dev/goal.md' "$fixture/current.out"
grep -Eq 'If none exists in dev/, check .* in development/\. .* read the files that exist' "$fixture/current.out"
grep -Fq 'If neither directory contains any of these files, inspect README.md' "$fixture/current.out"
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
normalize_preview_paths "$fixture/current.out" > "$fixture/current-previews.out"
normalize_preview_paths "$fixture/installed.out" > "$fixture/installed-previews.out"
diff -u "$fixture/current-previews.out" "$fixture/installed-previews.out"
test -d "$fixture/work/project/.meowsky"
test "$(grep -Fxc '/.meowsky/' "$fixture/work/project/.gitignore")" -eq 1
printf 'user reference\n' > "$fixture/work/project/.meowsky/reference.txt"
git -C "$fixture/work/project" init --quiet
git -C "$fixture/work/project" check-ignore --quiet .meowsky/reference.txt
test "$(cat "$fixture/work/project/.meowsky/reference.txt")" = 'user reference'
mkdir -p "$fixture/existing-rule-project"
printf 'node_modules/\n.meowsky/\n' > "$fixture/existing-rule-project/.gitignore"
existing_rule_hash="$(sha256sum "$fixture/existing-rule-project/.gitignore")"
"$BASH" -c '. "$1"; meowsky_ensure_project_workspace "$2"' -- "$repo/shell/meowsky.sh" "$fixture/existing-rule-project"
test "$(sha256sum "$fixture/existing-rule-project/.gitignore")" = "$existing_rule_hash"
mkdir -p "$fixture/previews/folder.md" "$fixture/previews/folder.pdf"
touch "$fixture/previews/a b.md" "$fixture/previews/ab.md" \
  "$fixture/previews/a b.pdf" "$fixture/previews/ab.pdf" "$fixture/previews/other.txt" \
  "$fixture/previews/folder.md/nested.md" "$fixture/previews/folder.pdf/nested.pdf"
(
  export TMPDIR="$fixture/previews"
  export WORK_HOME="$fixture/work"
  . "$repo/shell/meowsky.sh"
  cd "$fixture/previews"
  pandoc() { printf '%s\t%s\n' "$7" "$8" >> "$fixture/markdown-launches"; }
  xdg-open() { printf '%s\n' "$1" >> "$fixture/viewer-launches"; }

  for pattern in '*' '*.md'; do
    : > "$fixture/markdown-launches"
    : > "$fixture/viewer-launches"
    meowsky md $pattern
    wait
    printf 'a b.md\nab.md\n' | diff -u - <(cut -f2 "$fixture/markdown-launches" | sort)
    test "$(cut -f1 "$fixture/markdown-launches" | sort -u | wc -l)" -eq 2
    test "$(wc -l < "$fixture/viewer-launches")" -eq 2
  done
  for pattern in '*' '*.pdf'; do
    : > "$fixture/viewer-launches"
    meowsky pdf $pattern
    wait
    printf 'a b.pdf\nab.pdf\n' | diff -u - <(sort "$fixture/viewer-launches")
  done
  : > "$fixture/markdown-launches"
  meowsky md '*.md'
  wait
  test "$(wc -l < "$fixture/markdown-launches")" -eq 2

  mkdir "$fixture/no-previews"
  cd "$fixture/no-previews"
  touch only.txt
  if meowsky md * > "$fixture/no-match" 2>&1; then exit 1; fi
  grep -Fq 'No .md files matched.' "$fixture/no-match"
  if meowsky pdf *.pdf > "$fixture/no-match" 2>&1; then exit 1; fi
  grep -Fq 'No .pdf files matched.' "$fixture/no-match"
)
printf 'PASS: shell syntax, original Linux behavior, copied installation layout, wildcard previews.\n'
