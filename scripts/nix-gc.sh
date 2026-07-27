#!/usr/bin/env bash
# Reclaim Nix store space after a successful darwin-rebuild switch.
#
# Invoked from rebuild.sh once the switch has succeeded, so garbage collection
# is tied to the rebuild the owner actually performs instead of a launchd
# calendar job that a powered-off laptop would silently miss. It runs at most
# once every GC_INTERVAL_DAYS and keeps every generation newer than
# GC_RETENTION, so rollback (see the README "Rollback and recovery" section)
# stays possible.
set -euo pipefail

# --- Tunables -----------------------------------------------------------------
# Minimum number of days between cleanups. Raise this to collect less often.
GC_INTERVAL_DAYS=7
# Keep every generation created within this window, including the current one,
# so `darwin-rebuild --rollback` / `--switch-generation` still work. Passed
# verbatim to `nix-collect-garbage --delete-older-than`. A bare `-d` /
# `--delete-old` would instead strip every non-current generation, destroying
# the rollback window, so it is deliberately not used here.
GC_RETENTION="30d"
# Set REBUILD_SKIP_GC=1 to skip garbage collection for a single rebuild,
# mirroring rebuild.sh's REBUILD_YES opt-out convention.
REBUILD_SKIP_GC="${REBUILD_SKIP_GC:-0}"
# ------------------------------------------------------------------------------

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ "$REBUILD_SKIP_GC" == "1" ]]; then
  say "skipping Nix garbage collection (REBUILD_SKIP_GC=1)"
  exit 0
fi

# Resolve Nix binaries the same way the rest of the rebuild flow does, so this
# works even when invoked with a minimal PATH.
export PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"

if ! NIX_COLLECT_GARBAGE="$(command -v nix-collect-garbage)"; then
  printf '%s\n' "warning: nix-collect-garbage not found; skipping garbage collection" >&2
  exit 0
fi

# The last-cleanup timestamp lives outside the repository in the XDG state dir
# so a clean checkout never carries scheduling state around with it.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STAMP_FILE="$STATE_DIR/nix-gc-last-run"

now="$(date +%s)"
if [[ -f "$STAMP_FILE" ]]; then
  last="$(cat "$STAMP_FILE" 2>/dev/null || printf '0')"
  # Treat a corrupt (non-numeric) stamp as "never run" rather than failing.
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  interval_seconds=$(( GC_INTERVAL_DAYS * 24 * 60 * 60 ))
  elapsed=$(( now - last ))
  if (( elapsed < interval_seconds )); then
    days_left=$(( (interval_seconds - elapsed + 86399) / 86400 ))
    say "skipping Nix garbage collection (ran <${GC_INTERVAL_DAYS}d ago; ~${days_left}d until next)"
    exit 0
  fi
fi

# User-profile generations. This is the core operation; a genuine failure here
# is surfaced rather than swallowed, and leaves the timestamp untouched so the
# next rebuild retries.
say "collecting Nix garbage older than ${GC_RETENTION} (user profile)"
"$NIX_COLLECT_GARBAGE" --delete-older-than "$GC_RETENTION"

# System (darwin) generations live under the root-owned system profile and need
# sudo. rebuild.sh already ran `sudo darwin-rebuild switch`, so credentials are
# normally still cached. Probe with `sudo -n` so a non-interactive rebuild never
# hangs on a password prompt; prompt only when a TTY is present, otherwise warn
# and leave the system generations for the next interactive rebuild. The
# resolved absolute path is passed through so sudo's secure_path cannot hide it.
system_gc_deferred=0
if sudo -n true 2>/dev/null; then
  say "collecting Nix garbage older than ${GC_RETENTION} (system profile)"
  sudo -n "$NIX_COLLECT_GARBAGE" --delete-older-than "$GC_RETENTION" ||
    printf '%s\n' "warning: system-profile GC failed; continuing" >&2
elif [[ -t 0 ]]; then
  say "collecting Nix garbage older than ${GC_RETENTION} (system profile, sudo)"
  sudo "$NIX_COLLECT_GARBAGE" --delete-older-than "$GC_RETENTION" ||
    printf '%s\n' "warning: system-profile GC failed; continuing" >&2
else
  system_gc_deferred=1
  printf '%s\n' "warning: no cached sudo credentials and no TTY; skipped system-profile GC" >&2
fi

# Deduplicate identical store paths. Best-effort: a failure here never fails the
# rebuild or blocks recording the timestamp.
if NIX_BIN="$(command -v nix)" && "$NIX_BIN" store optimise 2>/dev/null; then
  say "optimised the Nix store"
else
  printf '%s\n' "warning: nix store optimise failed or nix was not found; continuing" >&2
fi

# Record success so the interval gate above skips the next several rebuilds.
# If system-profile GC was deferred for want of sudo credentials and a TTY,
# leave the timestamp untouched so the next rebuild retries it instead of the
# interval gate skipping the collection entirely.
if (( system_gc_deferred )); then
  say "Nix garbage collection complete (system profile deferred; will retry next rebuild)"
else
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$now" > "$STAMP_FILE"
  say "Nix garbage collection complete"
fi
