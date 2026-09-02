{ brew-src, user, ... }:
{
  imports = [ ./homebrew.nix ];

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

  # A native Homebrew prefix IS the brew repository, so its own
  # share/zsh/site-functions/_brew -> ../../../completions/zsh/_brew link ships
  # with the checkout. nix-homebrew instead keeps the source in the Nix store and
  # only links Library/Homebrew into the prefix, so neither hop exists and
  # `brew shellenv`'s fpath entry (HOMEBREW_PREFIX/share/zsh/site-functions) is
  # empty. Create that entry directly, as a single hop to the store: the
  # interpolation below is a genuine reference of the activation script, so
  # brew-src is retained as part of the system closure and the link cannot dangle.
  # Only site-functions is maintained -- nothing on this machine reads the
  # prefix's completions/ directory, so a second link there would be an
  # unreferenced copy of the same failure mode.
  #
  # This must live in postActivation: nix-darwin 26.05 runs a fixed list of named
  # fragments, so a self-named system.activationScripts.<name> entry is evaluated
  # but never executed.
  system.activationScripts.postActivation.text = ''
    mkdir -p /opt/homebrew/share/zsh/site-functions
    ln -sfn ${brew-src}/completions/zsh/_brew /opt/homebrew/share/zsh/site-functions/_brew
  '';

  system.stateVersion = 6;
}
