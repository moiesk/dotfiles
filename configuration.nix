{ user, ... }:
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
    inherit user;
  };

  system.stateVersion = 6;
}
