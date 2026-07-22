#!/usr/bin/env bash
# Convert old managed symlinks to mutable files and overlay portable settings.
set -euo pipefail

DOTFILES_DIR="${1:?usage: materialize-agent-configs.sh DOTFILES_DIR [JQ_BIN]}"
JQ_BIN="${2:-$(command -v jq)}"

materialize_mutable_file() {
  local live_path="$1"

  mkdir -p "$(dirname "$live_path")"

  # Preserve a readable legacy out-of-store link before Home Manager forgets it.
  if [[ -L "$live_path" ]]; then
    if [[ -r "$live_path" ]]; then
      local link_copy
      link_copy="$(mktemp "$(dirname "$live_path")/.agent-config.XXXXXX")"
      cp -L "$live_path" "$link_copy"
      chmod 600 "$link_copy"
      rm "$live_path"
      mv "$link_copy" "$live_path"
    else
      rm "$live_path"
    fi
  fi
}

merge_portable_json() {
  local live_path="$1" portable_path="$2"
  local merged

  materialize_mutable_file "$live_path"
  merged="$(mktemp "$(dirname "$live_path")/.agent-config.XXXXXX")"

  if [[ -e "$live_path" ]]; then
    "$JQ_BIN" -s '.[0] * .[1]' "$live_path" "$portable_path" > "$merged"
  else
    "$JQ_BIN" '.' "$portable_path" > "$merged"
  fi

  chmod 600 "$merged"
  mv "$merged" "$live_path"
}

merge_portable_json \
  "$HOME/.claude/settings.json" \
  "$DOTFILES_DIR/home/.claude/settings.portable.json"

# Codex gets portable defaults from /etc/codex/config.toml. Its user config is
# deliberately mutable and may be absent until Codex needs to persist a choice.
materialize_mutable_file "$HOME/.codex/config.toml"

# Pi currently has no portable settings in this repository. Preserve an old
# linked configuration during migration, but allow both files to be absent on a
# fresh machine so Pi can create them with machine-appropriate defaults.
materialize_mutable_file "$HOME/.pi/agent/settings.json"
materialize_mutable_file "$HOME/.pi/agent/models.json"
