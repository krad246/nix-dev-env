{
  description = "My Nix development environment flake. Used in my other repositories.";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    extra-experimental-features = "nix-command flakes";
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Infrastructure flakes

    # Legacy and flake compatibility shims.
    flake-compat.url = "github:edolstra/flake-compat";

    # Simple connection glue between direnv, nix-shell, and flakes to get
    # the absolute roots of various subflakes in a project.
    flake-root.url = "github:srid/flake-root";

    # An opinionated Nix flake library (see flake-utils)
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Development flakes

    # Swiss-army-knife formatter.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Code cleanliness checking for developers.
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        flake-compat.follows = "flake-compat";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = inputs @ {
    nixpkgs,
    flake-parts,
    ...
  }: let
    inherit (nixpkgs) lib;

    # For each tool flake, try to import it as a flake-parts module.
    # If there is no associated binding, yield an empty module in its place.
    toolModules = with inputs; ([flake-root] ++ [treefmt-nix pre-commit-hooks-nix]);
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      # Source the discovered flakeModules into the context of this mkFlake call.
      imports = let
        asFlakeModule = input: lib.attrsets.attrByPath ["flakeModule"] (_: {}) input;
      in
        lib.lists.forEach toolModules asFlakeModule;

      # Generate a common cross-platform development and tooling environment.
      # This is pretty similar to flake-utils.eachDefaultSystem but does the layering more sensibly.
      systems = ["x86_64-linux" "aarch64-darwin" "aarch64-linux"];
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        # Set up some code formatting for live development.
        formatter = config.treefmt.build.wrapper;

        treefmt = {
          projectRootFile = lib.attrsets.attrByPath ["flake-root" "projectRootFile"] "flake.nix" config;
          programs = {
            deadnix.enable = true;
            alejandra.enable = true;
            statix.enable = true;
            shellcheck.enable = true;
            shfmt.enable = true;
          };
        };

        # Set up some code formatting prior to 'git push' + some static analysis.
        pre-commit.settings.hooks = {
          cspell.enable = false;
          nil.enable = true;
          deadnix.enable = true;
          alejandra.enable = true;
          statix.enable = true;
          shellcheck.enable = true;
          shfmt.enable = true;
        };

        # Developer shell environments; invoked via `nix develop`
        devShells = rec {
          default = develop;
          develop = pkgs.mkShell {
            # Merge all of the environments of the devShell outputs exposed by the tools.
            inputsFrom = let
              asDevShell = input: lib.attrsets.attrByPath ["devShells" "default"] {} input;
            in
              lib.lists.forEach toolModules asDevShell;

            # Auto-format the source tree when it changes (managed by direnv watches)
            shellHook = let
              direnvBin = lib.getExe pkgs.direnv;
              treefmtBin = lib.getExe config.treefmt.build.wrapper;
              flakeRoot = lib.getExe config.flake-root.package;
            in ''
              flakeRoot="$(${flakeRoot})"
              "${direnvBin}" allow "$flakeRoot"
              "${treefmtBin}" "$flakeRoot"
            '';

            # Install pure versions of core development packages to replace the impure ones
            # from direnv land.
            packages = with pkgs; [git direnv nix-direnv];
          };
        };
      };
    };
}
