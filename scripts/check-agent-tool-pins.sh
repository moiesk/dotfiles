#!/usr/bin/env bash
# Keep every npm-backed AXI tool's flake, npm, lockfile, and trust pins aligned.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"

for input_package_prefix in \
  'chrome-devtools-axi chrome-devtools-axi chrome-devtools-axi-v' \
  'gh-axi gh-axi gh-axi-v' \
  'lavish-axi lavish-axi lavish-axi-v' \
  'quota-axi quota-axi quota-axi-v' \
  'tasks-axi tasks-axi tasks-axi-v'; do
  read -r flake_input npm_package tag_prefix <<<"$input_package_prefix"

  npm_version="$(jq -er --arg package "$npm_package" \
    '.dependencies[$package]' "$DOTFILES_DIR/agent-tools/package.json")"
  npm_lock_version="$(jq -er --arg package "$npm_package" \
    '.packages[""].dependencies[$package]' \
    "$DOTFILES_DIR/agent-tools/package-lock.json")"
  npm_installed_version="$(jq -er --arg path "node_modules/$npm_package" \
    '.packages[$path].version' "$DOTFILES_DIR/agent-tools/package-lock.json")"

  if [[ "$npm_lock_version" != "$npm_version" ]]; then
    printf 'error: %s npm manifest version %s does not match package-lock root version %s\n' \
      "$npm_package" "$npm_version" "$npm_lock_version" >&2
    exit 1
  fi
  if [[ "$npm_installed_version" != "$npm_version" ]]; then
    printf 'error: %s npm manifest version %s does not match package-lock installed version %s\n' \
      "$npm_package" "$npm_version" "$npm_installed_version" >&2
    exit 1
  fi

  flake_nix_ref="$(sed -nE \
    "s|^[[:space:]]*url = \"github:kunchenguid/${flake_input}/([^\"]+)\";|\\1|p" \
    "$DOTFILES_DIR/flake.nix")"
  if [[ -z "$flake_nix_ref" || "$flake_nix_ref" == *$'\n'* ]]; then
    printf 'error: flake.nix must contain exactly one release URL for %s\n' \
      "$flake_input" >&2
    exit 1
  fi

  expected_ref="${tag_prefix}${npm_version}"
  if [[ "$flake_nix_ref" != "$expected_ref" ]]; then
    printf 'error: %s flake.nix ref %s does not match npm version %s\n' \
      "$npm_package" "$flake_nix_ref" "$npm_version" >&2
    exit 1
  fi

  flake_lock_ref="$(jq -er --arg input "$flake_input" \
    '.nodes[$input].original.ref' "$DOTFILES_DIR/flake.lock")"
  if [[ "$flake_lock_ref" != "$flake_nix_ref" ]]; then
    printf 'error: %s flake.nix ref %s does not match flake.lock ref %s\n' \
      "$npm_package" "$flake_nix_ref" "$flake_lock_ref" >&2
    exit 1
  fi

  trust_row="$(rg -F -- "https://github.com/kunchenguid/${npm_package})" \
    "$DOTFILES_DIR/TRUST.md" || true)"
  if [[ "$(printf '%s' "$trust_row" | rg -c '' || true)" != "1" ]]; then
    printf 'error: TRUST.md must contain exactly one inventory row for %s\n' \
      "$npm_package" >&2
    exit 1
  fi
  for trust_pin in "$expected_ref" "${npm_package}@${npm_version}"; do
    if ! printf '%s' "$trust_row" | rg -Fq -- "$trust_pin"; then
      printf 'error: TRUST.md row for %s does not document the current pin %s\n' \
        "$npm_package" "$trust_pin" >&2
      exit 1
    fi
  done
done

printf '%s\n' 'agent tool pins are aligned'
