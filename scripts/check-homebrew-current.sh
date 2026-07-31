#!/usr/bin/env bash
# Report whether Homebrew has outdated packages without treating warnings as packages.
set -uo pipefail

stdout_file="$(mktemp)" || exit 2
stderr_file="$(mktemp)" || {
  rm -f "$stdout_file"
  exit 2
}
trap 'rm -f "$stdout_file" "$stderr_file"' EXIT

HOMEBREW_NO_AUTO_UPDATE=1 brew outdated >"$stdout_file" 2>"$stderr_file"
status=$?

print_lines() {
  awk 'BEGIN { first = 1 } { if (!first) printf " "; printf "%s", $0; first = 0 } END { printf "\n" }' "$@"
}

if [[ "$status" -ne 0 ]]; then
  printf 'Homebrew could not check for outdated packages'
  if [[ -s "$stdout_file" || -s "$stderr_file" ]]; then
    printf ': '
    print_lines "$stdout_file" "$stderr_file"
  else
    printf '\n'
  fi
  exit 2
fi

if [[ -s "$stdout_file" ]]; then
  printf 'Homebrew packages remain outdated: '
  print_lines "$stdout_file"
  exit 1
fi
