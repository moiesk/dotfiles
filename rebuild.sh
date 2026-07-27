#!/usr/bin/env bash
# Reapply the configuration after editing the repository.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'EOF'
usage: rebuild.sh [--yes] [--help]

Reapply the nix-darwin configuration with darwin-rebuild switch.

Before switching, the strict Homebrew cleanup (cleanup = "zap") is previewed via
scripts/homebrew-preflight.sh, which lists undeclared formulae, casks, and taps
that the rebuild would remove and requires confirmation before proceeding.

The system closure is then built without activating it (darwin-rebuild build).
This build gate always runs and needs no sudo; a build failure aborts before the
switch mutates the running system. --yes never skips it.

  --yes, -y   Skip the Homebrew delta preview and confirmation. Only use this
              when homebrew.nix already declares everything you want to keep.
              Equivalent to setting REBUILD_YES=1.
  --help, -h  Show this help and exit.

With no opt-out and no interactive terminal, the preflight refuses to proceed
when undeclared items are present rather than silently zapping them.

After a successful switch, scripts/nix-gc.sh reclaims Nix store space at most
once every 7 days, keeping a 30-day rollback window. Set REBUILD_SKIP_GC=1 to
skip garbage collection for a single rebuild.
EOF
}

REBUILD_YES="${REBUILD_YES:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)
      REBUILD_YES=1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -e "$HOME/.dotfiles" && ! -L "$HOME/.dotfiles" ]]; then
  printf 'error: %s exists and is not a symlink\n' "$HOME/.dotfiles" >&2
  exit 1
fi

ln -sfn "$DOTFILES_DIR" "$HOME/.dotfiles"

if ! command -v darwin-rebuild >/dev/null 2>&1; then
  printf 'error: darwin-rebuild is missing; run ./bootstrap.sh first\n' >&2
  exit 1
fi

if [[ "$REBUILD_YES" == "1" ]]; then
  printf '==> skipping Homebrew cleanup preview (opt-out set)\n'
else
  printf '==> previewing strict Homebrew cleanup\n'
  "$DOTFILES_DIR/scripts/homebrew-preflight.sh"
fi

printf '==> building system closure (no activation)\n'
if ! darwin-rebuild build --flake "$DOTFILES_DIR#mac"; then
  printf 'error: the configuration failed to build; aborting before switch\n' >&2
  exit 1
fi

printf '==> applying nix-darwin configuration\n'
sudo darwin-rebuild switch --flake "$DOTFILES_DIR#mac"

"$DOTFILES_DIR/scripts/post-switch.sh"
"$DOTFILES_DIR/scripts/nix-gc.sh"
"$DOTFILES_DIR/scripts/doctor.sh"
