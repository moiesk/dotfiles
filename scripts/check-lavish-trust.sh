#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
NIX_BIN="${NIX_BIN:-nix}"
TRUST_FILE="$DOTFILES_DIR/TRUST.md"

expected_capability='Renders agent responses into reviewable HTML artifacts. Upstream 0.1.60+ automatically adds a Tailscale listener when available unless `LAVISH_AXI_HOST` is explicitly set; this managed configuration sets `LAVISH_AXI_HOST=127.0.0.1`, which disables automatic Tailscale binding and keeps the review server loopback-only by default. The `share` command preserves hosted publishing as an explicit opt-in.'
expected_trust='Pinned to an exact release; the managed loopback default prevents automatic network exposure, and hosted sharing remains output-only and explicitly initiated.'

row_count="$(awk -F '|' '$2 ~ /kunchenguid\/lavish-axi/ { count++ } END { print count + 0 }' "$TRUST_FILE")"
if [[ "$row_count" != "1" ]]; then
  printf 'error: TRUST.md must contain exactly one lavish-axi inventory row (found %s)\n' \
    "$row_count" >&2
  exit 1
fi

read_trust_field() {
  local field="$1"
  awk -F '|' -v field="$field" '$2 ~ /kunchenguid\/lavish-axi/ {
    value = $field
    sub(/^[[:space:]]+/, "", value)
    sub(/[[:space:]]+$/, "", value)
    print value
  }' "$TRUST_FILE"
}

capability="$(read_trust_field 4)"
trust_basis="$(read_trust_field 5)"
if [[ "$capability" != "$expected_capability" ]]; then
  printf '%s\n' 'error: TRUST.md must disclose lavish-axi automatic Tailscale binding, the managed loopback override, and explicit hosted sharing' >&2
  exit 1
fi
if [[ "$trust_basis" != "$expected_trust" ]]; then
  printf '%s\n' 'error: TRUST.md must explain why lavish-axi remains low-capability under the managed configuration' >&2
  exit 1
fi

if ! command -v "$NIX_BIN" >/dev/null 2>&1; then
  printf '%s\n' 'warning: Nix is not installed; skipped lavish-axi managed environment evaluation' >&2
  exit 0
fi

managed_hosts="$($NIX_BIN eval --json \
  --apply 'users: builtins.mapAttrs (_: userConfig: userConfig.home.sessionVariables.LAVISH_AXI_HOST or null) users' \
  "$DOTFILES_DIR#darwinConfigurations.mac.config.home-manager.users")"
if ! jq -e 'length > 0 and all(.[]; . == "127.0.0.1")' <<<"$managed_hosts" >/dev/null; then
  printf '%s\n' 'error: every managed user must set LAVISH_AXI_HOST to 127.0.0.1' >&2
  exit 1
fi

printf '%s\n' 'lavish-axi trust controls are enforced'
