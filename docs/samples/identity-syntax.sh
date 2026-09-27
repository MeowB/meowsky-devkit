#!/usr/bin/env bash
# Inspect shell variables, functions, expansions and operators.
readonly LIMIT=4
total() {
  local extra="${1:-2}"
  if [[ "$extra" -gt 0 ]]; then
    printf '%s: %d\n' "Matrix" "$((LIMIT + extra))"
  else
    return 1
  fi
}
total 2
