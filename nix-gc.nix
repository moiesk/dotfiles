{ ... }:
let
  # ── Nix garbage-collection knobs — tune retention and cadence here ──────────
  # Retention window: generations older than this become collectable. Rollback
  # (`darwin-rebuild --rollback`; see README "Rollback and recovery") stays
  # available for every generation newer than this.
  gcRetention = "30d";

  # Weekly cadence. StartCalendarInterval behaves like cron: missing fields are
  # wildcards, so this runs every Sunday at 03:15 local time (Weekday 0 = Sunday).
  # If the laptop is asleep at that moment, launchd runs the job on next wake.
  gcSchedule = {
    Weekday = 0;
    Hour = 3;
    Minute = 15;
  };

  # launchd starts daemons with a minimal PATH and no user environment, so every
  # binary must be absolute. Determinate installs Nix into the default profile;
  # these profile symlinks are stable across the daemon-managed Nix upgrades that
  # rotate the underlying /nix/store path they resolve to.
  nixBin = "/nix/var/nix/profiles/default/bin";
in
{
  # nix-darwin's `nix.gc` / `nix.optimise` modules are inert in this config:
  # they require `nix.enable`, which configuration.nix sets false because
  # Determinate owns the Nix daemon. A plain scheduled LaunchDaemon reclaims the
  # store instead and is independent of `nix.enable`. It runs as root (system
  # daemon) because both collection and store optimisation are system-wide.
  launchd.daemons.nix-gc = {
    script = ''
      set -euo pipefail
      # Delete system-wide generations older than the retention window, keeping
      # everything newer so rollback stays possible, then deduplicate the store.
      ${nixBin}/nix-collect-garbage --delete-older-than ${gcRetention}
      ${nixBin}/nix store optimise
    '';
    serviceConfig = {
      StartCalendarInterval = [ gcSchedule ];
      # Only run on the weekly schedule, never on daemon (re)load / activation.
      RunAtLoad = false;
      StandardOutPath = "/var/log/nix-gc.log";
      StandardErrorPath = "/var/log/nix-gc.log";
    };
  };
}
