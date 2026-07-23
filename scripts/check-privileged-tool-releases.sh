#!/usr/bin/env bash
# Report stable Treehouse/no-mistakes releases after the routine cooldown.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GH_AXI_BIN="${GH_AXI_BIN:-gh-axi}"
COOLDOWN_DAYS="${TOOL_UPDATE_COOLDOWN_DAYS:-7}"
FAILURES=0

check_release() {
  local input_name="$1" repository="$2"
  local pinned metadata latest published published_epoch now age_seconds cooldown_seconds

  pinned="$(jq -er --arg input "$input_name" \
    '.nodes[$input].original.ref' "$DOTFILES_DIR/flake.lock")"
  metadata="$("$GH_AXI_BIN" api GET "/repos/$repository/releases/latest")"
  latest="$(awk -F': ' '/^tag_name:/ { print $2; exit }' <<<"$metadata")"
  published="$(awk -F': ' '/^published_at:/ { print $2; exit }' <<<"$metadata")"
  published="${published%\"}"
  published="${published#\"}"

  if [[ -z "$latest" || -z "$published" ]]; then
    printf 'error: incomplete release metadata for %s\n' "$repository" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  if [[ "$pinned" == "$latest" ]]; then
    printf '%s is on the latest stable release (%s)\n' "$input_name" "$pinned"
    return
  fi

  published_epoch="$(node -e \
    'const value = Date.parse(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); console.log(Math.floor(value / 1000));' \
    "$published")"
  now="$(date -u +%s)"
  age_seconds=$((now - published_epoch))
  cooldown_seconds=$((COOLDOWN_DAYS * 86400))

  if ((age_seconds < cooldown_seconds)); then
    printf '%s %s is available but remains in the %s-day cooldown (pinned: %s)\n' \
      "$input_name" "$latest" "$COOLDOWN_DAYS" "$pinned"
    return
  fi

  printf 'error: %s stable release %s is past cooldown; pinned release is %s\n' \
    "$input_name" "$latest" "$pinned" >&2
  FAILURES=$((FAILURES + 1))
}

check_release treehouse kunchenguid/treehouse
check_release no-mistakes kunchenguid/no-mistakes

if ((FAILURES > 0)); then
  exit 1
fi
