{
  description = "Moises' repeatable macOS development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    brew-src.follows = "nix-homebrew/brew-src";

    treehouse = {
      url = "github:kunchenguid/treehouse/v2.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    no-mistakes = {
      url = "github:kunchenguid/no-mistakes/v1.40.2";
      flake = false;
    };

    matt-pocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    lavish-axi = {
      url = "github:kunchenguid/lavish-axi/lavish-axi-v0.1.42";
      flake = false;
    };

    tasks-axi = {
      url = "github:kunchenguid/tasks-axi/tasks-axi-v0.2.3";
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
      # bootstrap.sh offers to update this when the local macOS user differs.
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
