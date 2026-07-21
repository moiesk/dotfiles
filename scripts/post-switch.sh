#!/usr/bin/env bash
# Install user-scoped tools that nix-darwin's Homebrew module does not model.
set -euo pipefail

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
export PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:$PATH"

say "installing mise runtimes"
if ! mise install --jobs=1; then
  say "retrying mise runtime installation after a transient failure"
  mise install --jobs=1
fi

say "installing Pi with Bun"
bun add --global @earendil-works/pi-coding-agent@0.78.0

say "installing shared agent helper CLIs"
mise exec -- npm install --global --prefix "$HOME/.local" \
  gh-axi@0.1.27 \
  chrome-devtools-axi@0.1.26

say "installing uv tools"
if ! uv tool list | rg -q '^batrachian-toad v0\.5\.35$'; then
  uv tool install --force batrachian-toad==0.5.35
fi
if ! uv tool list | rg -q '^interrogate v1\.7\.0$'; then
  uv tool install --force interrogate==1.7.0
fi

say "installing OpenCode plugin dependencies"
bun install --cwd "$HOME/.config/opencode"

say "user-scoped tools are current"
