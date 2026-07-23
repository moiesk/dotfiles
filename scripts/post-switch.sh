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

say "installing the latest Pi with Bun"
# Pi is an agent harness, so keep it current on every rebuild just like the
# Homebrew-managed Claude Code and Codex harnesses. --force makes Bun refresh
# registry metadata instead of accepting a cached resolution of the latest tag.
bun add --global --force @earendil-works/pi-coding-agent@latest

say "installing shared agent helper CLIs"
AGENT_TOOLS_PREFIX="$HOME/.local/share/agent-tools"
mise exec -- npm install --global --prefix "$AGENT_TOOLS_PREFIX" \
  gh-axi@0.1.27 \
  chrome-devtools-axi@0.1.27 \
  lavish-axi@0.1.42 \
  quota-axi@0.1.11 \
  tasks-axi@0.2.3

# Older revisions installed npm's Node-dependent bin links directly in
# ~/.local/bin, where they shadow the Nix-managed, pinned-Node wrappers.
for legacy_link in \
  "$HOME/.local/bin/gh-axi" \
  "$HOME/.local/bin/chrome-devtools-axi" \
  "$HOME/.local/bin/lavish-axi" \
  "$HOME/.local/bin/quota-axi" \
  "$HOME/.local/bin/tasks-axi"; do
  if [[ -L "$legacy_link" ]]; then
    rm "$legacy_link"
  fi
done

say "installing Firstmate agent distro"
FIRSTMATE_DIR="$HOME/firstmate"
if [[ ! -e "$FIRSTMATE_DIR" ]]; then
  (cd "$HOME" && gh-axi repo clone kunchenguid/firstmate)
elif [[ -d "$FIRSTMATE_DIR/.git" ]] &&
  git -C "$FIRSTMATE_DIR" remote get-url origin 2>/dev/null | rg -q '(^|[:/])kunchenguid/firstmate(?:\.git)?$'; then
  say "Firstmate already exists; leaving its mutable clone unchanged"
else
  printf '%s\n' "warning: $FIRSTMATE_DIR exists but is not the expected Firstmate clone; leaving it unchanged" >&2
fi

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
