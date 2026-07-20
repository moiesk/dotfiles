#!/usr/bin/env bash
# Install user-scoped tools that nix-darwin's Homebrew module does not model.
set -euo pipefail

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
export PATH="$HOME/.asdf/shims:$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:$PATH"

say "installing asdf runtimes from .tool-versions"
asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git 2>/dev/null || true
asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git 2>/dev/null || true
(cd "$HOME" && asdf install)

say "installing Pi with Bun"
bun add --global @earendil-works/pi-coding-agent@0.78.0

say "installing shared agent helper CLIs"
npm install --global --prefix "$HOME/.local" \
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
