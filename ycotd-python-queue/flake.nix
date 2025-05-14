{
  description = "YourCarOfTheDay email queue worker";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgs = forAllSystems (system: nixpkgs.legacyPackages.${system});
      
      # Define Python with our overlays function to be reused
      getPython = system: 
        let
          packageOverrides = pkgs.${system}.callPackage ./python-packages.nix { };
          python = pkgs.${system}.python3.override { inherit packageOverrides; };
        in python;
    in
    {
      overlays.default = final: prev: {
        ycotd-python-queue = self.packages.${prev.system}.default;
      };

      packages = forAllSystems (system: {
        default = pkgs.${system}.callPackage ./nix/package.nix {
          python-packages = pkgs.${system}.callPackage ./python-packages.nix { };
        };
      });

      nixosModules.ycotd-python-queue = import ./nix/module.nix;

      devShells = forAllSystems (system:
        let
          python = getPython system;
          pythonWithPackages = python.withPackages (ps: with ps; [
            bullmq
            python-dotenv
            tenacity
          ]);
        in
        {
          default = pkgs.${system}.mkShell {
            packages = [ pythonWithPackages ];
          };
        }
      );
    };
}
