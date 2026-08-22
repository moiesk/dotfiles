#!/usr/bin/env bash
# Keep TRUST.md's OpenCode inventory entry true against the manifest that
# actually installs the package: the documented pin and every cited release
# permalink must name the installed version, and the Tier C classification
# holds only while the committed OpenCode directory ships no runtime plugin or
# custom-tool code.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TRUST_FILE="$DOTFILES_DIR/TRUST.md"
CONFIG_DIR="home/.config/opencode"
MANIFEST="$DOTFILES_DIR/$CONFIG_DIR/package.json"
PACKAGE="@opencode-ai/plugin"
UPSTREAM="anomalyco/opencode"
LOW_CAPABILITY_TIER="Tier C"

for required in "$TRUST_FILE" "$MANIFEST"; do
  [[ -f "$required" ]] || {
    printf 'error: missing OpenCode trust input: %s\n' "$required" >&2
    exit 1
  }
done

version="$(jq -r --stream --arg package "$PACKAGE" \
  'select(length == 2 and .[0] == ["dependencies", $package]) | .[1]' \
  "$MANIFEST")"
version_count="$(printf '%s\n' "$version" | awk 'NF { count++ } END { print count + 0 }')"
if [[ "$version_count" != "1" ]]; then
  printf 'error: %s/package.json must contain exactly one dependency record for %s\n' \
    "$CONFIG_DIR" "$PACKAGE" >&2
  exit 1
fi
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'error: %s pin must be a plain exact semver: %s\n' "$PACKAGE" "$version" >&2
  exit 1
fi

row_lines="$(grep -n -F -- "\`$PACKAGE\`" "$TRUST_FILE" | grep -E '^[0-9]+:\|' || true)"
row_count="$(printf '%s\n' "$row_lines" | awk 'NF { count++ } END { print count + 0 }')"
if [[ "$row_count" != "1" ]]; then
  printf 'error: TRUST.md must contain exactly one inventory row for %s (found %s)\n' \
    "$PACKAGE" "$row_count" >&2
  exit 1
fi
row_number="${row_lines%%:*}"
row="${row_lines#*:}"

documented_pins="$(grep -F -o -- "$PACKAGE@" <<<"$row" | grep -c '' || true)"
if [[ "$documented_pins" != "1" ]] ||
  ! grep -Fq -- "$PACKAGE@$version" <<<"$row"; then
  printf 'error: TRUST.md row for %s does not document exactly one current pin %s@%s\n' \
    "$PACKAGE" "$PACKAGE" "$version" >&2
  exit 1
fi

if ! grep -Fq -- "$CONFIG_DIR/package.json" <<<"$row"; then
  printf 'error: TRUST.md row for %s must cite its authoritative pin location %s/package.json\n' \
    "$PACKAGE" "$CONFIG_DIR" >&2
  exit 1
fi

evidence_refs="$(grep -o -E "github\.com/$UPSTREAM/(tree|blob)/[^/]+/" "$TRUST_FILE" |
  sed -E "s|github\.com/$UPSTREAM/(tree\|blob)/||; s|/$||" | sort -u)"
if [[ -z "$evidence_refs" ]]; then
  printf 'error: TRUST.md must cite %s release evidence for %s\n' "$UPSTREAM" "$PACKAGE" >&2
  exit 1
fi
while IFS= read -r evidence_ref; do
  if [[ "$evidence_ref" != "v$version" ]]; then
    printf 'error: TRUST.md cites %s evidence at %s but %s/package.json installs %s\n' \
      "$UPSTREAM" "$evidence_ref" "$CONFIG_DIR" "$version" >&2
    exit 1
  fi
done <<<"$evidence_refs"

tier="$(awk -v row="$row_number" '
  /^## / { heading = $0 }
  NR == row { sub(/^## /, "", heading); print heading; exit }
' "$TRUST_FILE")"
if [[ -z "$tier" ]]; then
  printf 'error: TRUST.md row for %s is not inside a capability tier section\n' \
    "$PACKAGE" >&2
  exit 1
fi

if [[ "$tier" == "$LOW_CAPABILITY_TIER"* ]]; then
  if ! git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: cannot confirm the %s tracked file set outside a git work tree, so the %s classification is unverifiable here\n' \
      "$CONFIG_DIR" "$LOW_CAPABILITY_TIER" >&2
    exit 1
  fi
  tracked="$(git -C "$DOTFILES_DIR" ls-files -- "$CONFIG_DIR")"
  if [[ -z "$tracked" ]]; then
    printf 'error: %s has no tracked files, so the %s classification cannot be confirmed\n' \
      "$CONFIG_DIR" "$LOW_CAPABILITY_TIER" >&2
    exit 1
  fi
  while IFS= read -r tracked_file; do
    [[ -z "$tracked_file" ]] && continue
    case "${tracked_file#"$CONFIG_DIR/"}" in
      .npmrc | package.json | package-lock.json) ;;
      *)
        printf 'error: %s classifies %s as %s, which assumes %s holds only the npm manifests and .npmrc; %s adds runtime OpenCode plugin/tool code, so the tier must be re-evaluated\n' \
          'TRUST.md' "$PACKAGE" "$LOW_CAPABILITY_TIER" "$CONFIG_DIR" "$tracked_file" >&2
        exit 1
        ;;
    esac
  done <<<"$tracked"
fi

printf '%s\n' 'OpenCode trust inventory is aligned'
