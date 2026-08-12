#!/usr/bin/env bash
# Keep every npm-backed AXI tool's flake, npm, lockfile, and trust pins aligned.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
INVENTORY="$DOTFILES_DIR/scripts/agent-tool-pins.tsv"
[[ -f "$INVENTORY" ]] || {
  printf 'error: missing agent tool inventory: %s\n' "$INVENTORY" >&2
  exit 1
}

inventory_packages=""
inventory_count=0
while IFS=$'\t' read -r flake_input npm_package tag_prefix extra; do
  [[ -z "$flake_input" || "$flake_input" == \#* ]] && continue
  if [[ -z "$npm_package" || -z "$tag_prefix" || -n "${extra:-}" ]]; then
    printf 'error: invalid agent tool inventory row for %s\n' "$flake_input" >&2
    exit 1
  fi
  if grep -Fxq -- "$npm_package" <<<"$inventory_packages"; then
    printf 'error: duplicate agent tool inventory row for %s\n' "$npm_package" >&2
    exit 1
  fi
  inventory_packages="${inventory_packages}${inventory_packages:+$'\n'}${npm_package}"
  inventory_count=$((inventory_count + 1))

  npm_values="$(jq -r --stream --arg package "$npm_package" \
    'select(length == 2 and .[0] == ["dependencies", $package]) | .[1]' \
    "$DOTFILES_DIR/agent-tools/package.json")"
  npm_count="$(printf '%s\n' "$npm_values" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "$npm_count" != "1" ]]; then
    printf 'error: agent-tools/package.json must contain exactly one dependency record for %s\n' \
      "$npm_package" >&2
    exit 1
  fi
  npm_version="$npm_values"
  if [[ ! "$npm_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'error: %s npm manifest pin must be a plain exact semver: %s\n' \
      "$npm_package" "$npm_version" >&2
    exit 1
  fi

  npm_lock_values="$(jq -r --stream --arg package "$npm_package" \
    'select(length == 2 and .[0] == ["packages", "", "dependencies", $package]) | .[1]' \
    "$DOTFILES_DIR/agent-tools/package-lock.json")"
  npm_lock_count="$(printf '%s\n' "$npm_lock_values" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "$npm_lock_count" != "1" ]]; then
    printf 'error: agent-tools/package-lock.json must contain exactly one root dependency record for %s\n' \
      "$npm_package" >&2
    exit 1
  fi
  npm_lock_version="$npm_lock_values"

  npm_installed_values="$(jq -r --stream --arg path "node_modules/$npm_package" \
    'select(length == 2 and .[0] == ["packages", $path, "version"]) | .[1]' \
    "$DOTFILES_DIR/agent-tools/package-lock.json")"
  npm_installed_count="$(printf '%s\n' "$npm_installed_values" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "$npm_installed_count" != "1" ]]; then
    printf 'error: agent-tools/package-lock.json must contain exactly one installed record for %s\n' \
      "$npm_package" >&2
    exit 1
  fi
  npm_installed_version="$npm_installed_values"

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

  flake_lock_values="$(jq -r --stream --arg input "$flake_input" \
    'select(length == 2 and .[0] == ["nodes", $input, "original", "ref"]) | .[1]' \
    "$DOTFILES_DIR/flake.lock")"
  flake_lock_count="$(printf '%s\n' "$flake_lock_values" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "$flake_lock_count" != "1" ]]; then
    printf 'error: flake.lock must contain exactly one original ref record for %s\n' \
      "$flake_input" >&2
    exit 1
  fi
  flake_lock_ref="$flake_lock_values"
  if [[ "$flake_lock_ref" != "$flake_nix_ref" ]]; then
    printf 'error: %s flake.nix ref %s does not match flake.lock ref %s\n' \
      "$npm_package" "$flake_nix_ref" "$flake_lock_ref" >&2
    exit 1
  fi

  trust_row="$(rg -F -- "https://github.com/kunchenguid/${npm_package})" \
    "$DOTFILES_DIR/TRUST.md" || true)"
  if [[ "$(printf '%s\n' "$trust_row" | awk 'NF { count++ } END { print count + 0 }')" != "1" ]]; then
    printf 'error: TRUST.md must contain exactly one inventory row for %s\n' \
      "$npm_package" >&2
    exit 1
  fi
  for trust_pin in "$expected_ref" "${npm_package}@${npm_version}"; do
    if [[ "$(grep -F -o -- "$trust_pin" <<<"$trust_row" | grep -c '' || true)" != "1" ]]; then
      printf 'error: TRUST.md row for %s does not document exactly one current pin %s\n' \
        "$npm_package" "$trust_pin" >&2
      exit 1
    fi
  done
done <"$INVENTORY"

[[ "$inventory_count" -gt 0 ]] || {
  printf '%s\n' 'error: agent tool inventory is empty' >&2
  exit 1
}
while IFS= read -r manifest_package; do
  if ! grep -Fxq -- "$manifest_package" <<<"$inventory_packages"; then
    printf 'error: npm-backed AXI dependency %s is missing from scripts/agent-tool-pins.tsv\n' \
      "$manifest_package" >&2
    exit 1
  fi
done < <(jq -r '.dependencies | keys[] | select(endswith("-axi"))' \
  "$DOTFILES_DIR/agent-tools/package.json")

printf '%s\n' 'agent tool pins are aligned'
