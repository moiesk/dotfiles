{
  description = "A repeatable macOS development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Track Homebrew itself independently so rebuild.sh can refresh its DSL
    # before current formulae and casks are evaluated during activation.
    brew-src = {
      url = "github:Homebrew/brew";
      flake = false;
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    nix-homebrew.inputs.brew-src.follows = "brew-src";

    treehouse = {
      url = "github:kunchenguid/treehouse/v2.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    no-mistakes = {
      url = "github:kunchenguid/no-mistakes/v1.48.0";
      flake = false;
    };

    matt-pocock-skills = {
      url = "github:mattpocock/skills/v1.1.0";
      flake = false;
    };

    chrome-devtools-axi = {
      url = "github:kunchenguid/chrome-devtools-axi/chrome-devtools-axi-v0.1.29";
      flake = false;
    };

    gh-axi = {
      url = "github:kunchenguid/gh-axi/gh-axi-v0.1.33";
      flake = false;
    };

    lavish-axi = {
      url = "github:kunchenguid/lavish-axi/lavish-axi-v0.1.59";
      flake = false;
    };

    quota-axi = {
      url = "github:kunchenguid/quota-axi/quota-axi-v0.1.30";
      flake = false;
    };

    tasks-axi = {
      url = "github:kunchenguid/tasks-axi/tasks-axi-v0.2.5";
      flake = false;
    };
  };

  outputs = inputs@{
    self,
    nix-darwin,
    nix-homebrew,
    brew-src,
    home-manager,
    nixpkgs,
    ...
  }:
    let
      # ADOPTERS: change this to your macOS username.
      # bootstrap.sh offers to rewrite it automatically when the local macOS
      # user differs from the value below.
      user = "moiesk";
    in {
      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit brew-src inputs user; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "dotfiles-backup";
            home-manager.extraSpecialArgs = { inherit inputs user; };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };
    };
}
