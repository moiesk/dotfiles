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

  # These are Moises' requested settings. They are intentionally not copied
  # from the reference dotfiles repository.
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
