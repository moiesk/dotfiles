{ brew-src, user, ... }:
{
  imports = [
    ./homebrew.nix
    ./nix-gc.nix
  ];

  # Determinate manages the Nix daemon installed by bootstrap.sh.
  nix.enable = false;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };

  # Codex's system layer supplies portable defaults. The higher-precedence
  # ~/.codex/config.toml remains mutable for machine-specific model, effort,
  # and project trust choices.
  environment.etc."codex/config.toml".text =
    builtins.readFile ./home/.codex/config.defaults.toml;

  # ADOPTERS: these are the repo owner's preferred macOS defaults. They are
  # intentionally not copied from the reference dotfiles repository; adjust them
  # to taste.
  system.defaults = {
    dock.autohide = true;
    NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically = true;
    CustomUserPreferences."com.apple.finder" = {
      ShowTabView = true;
      FinderSpawnTab = true;
      AppleWindowTabbingMode = "always";
    };
  };

  nix-homebrew = {
    enable = true;
    autoMigrate = true;
    inherit user;
  };

  # nix-homebrew keeps Homebrew's source in the Nix store, outside the mutable
  # prefix. Restore the completion target expected by Homebrew's standard
  # share/zsh/site-functions/_brew symlink.
  system.activationScripts.homebrewZshCompletion.text = ''
    mkdir -p /opt/homebrew/completions/zsh
    ln -sfn ${brew-src}/completions/zsh/_brew /opt/homebrew/completions/zsh/_brew
  '';

  system.stateVersion = 6;
}
