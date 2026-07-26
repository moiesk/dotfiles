#!/usr/bin/env bash
# Install user-scoped tools that nix-darwin's Homebrew module does not model.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
refresh_gpg_keybox() {
  command -v gpgconf >/dev/null 2>&1 || return 0
  gpgconf --kill keyboxd 2>/dev/null || true
  gpgconf --launch keyboxd 2>/dev/null || true
}
export PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:$PATH"

say "installing mise runtimes"
if ! mise install --jobs=1; then
  say "refreshing the GPG public-key service before retrying mise"
  refresh_gpg_keybox
  mise install --jobs=1
fi

say "installing locked npm agent tools"
AGENT_TOOLS_PREFIX="$HOME/.local/share/agent-tools"
mkdir -p "$AGENT_TOOLS_PREFIX"
cp "$DOTFILES_DIR/agent-tools/package.json" "$AGENT_TOOLS_PREFIX/package.json"
cp "$DOTFILES_DIR/agent-tools/package-lock.json" "$AGENT_TOOLS_PREFIX/package-lock.json"
cp "$DOTFILES_DIR/agent-tools/.npmrc" "$AGENT_TOOLS_PREFIX/.npmrc"
mise exec -- npm ci --prefix "$AGENT_TOOLS_PREFIX"

# Pi is a first-party harness (decisions #34/#36): it deliberately rolls to the
# latest published release on every rebuild, like the claude-code/codex casks —
# no pin, no cooldown. It is therefore installed on top of the pinned,
# lockfile-driven tools above rather than being listed in package.json/-lock.
# This is the one sanctioned latest-install; validate.sh exempts exactly it.
mise exec -- npm install --prefix "$AGENT_TOOLS_PREFIX" \
  @earendil-works/pi-coding-agent@latest

"$DOTFILES_DIR/scripts/npm-audit.sh" "$AGENT_TOOLS_PREFIX"
mise exec -- npm audit signatures --prefix "$AGENT_TOOLS_PREFIX"

# Pi used to be installed separately by Bun. Remove the stale copy after the
# locked npm installation succeeds so it cannot shadow the Nix-managed wrapper.
if [[ -d "$HOME/.bun/install/global/node_modules/@earendil-works/pi-coding-agent" ]]; then
  bun remove --global @earendil-works/pi-coding-agent
fi

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

say "installing locked OpenCode plugin dependencies"
mise exec -- npm ci --prefix "$HOME/.config/opencode"
"$DOTFILES_DIR/scripts/npm-audit.sh" "$HOME/.config/opencode"
mise exec -- npm audit signatures --prefix "$HOME/.config/opencode"

say "user-scoped tools are current"
