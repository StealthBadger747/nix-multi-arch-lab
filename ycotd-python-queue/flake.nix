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

      packages = forAllSystems (system: 
        let
          python = getPython system;
          # Create a Python environment with all required packages
          pythonWithPackages = python.withPackages (ps: with ps; [
            bullmq
            python-dotenv
            tenacity
          ]);
        in
        {
          default = pkgs.${system}.stdenv.mkDerivation {
            name = "ycotd-python-queue";
            src = self;
            buildInputs = [ pythonWithPackages ];
            installPhase = ''
              mkdir -p $out/bin
              cp -r $src/main.py $out/bin/
              chmod +x $out/bin/main.py
              echo '#!/usr/bin/env sh' > $out/bin/ycotd-email-queue
              echo 'exec ${pythonWithPackages}/bin/python3 $out/bin/main.py "$@"' >> $out/bin/ycotd-email-queue
              chmod +x $out/bin/ycotd-email-queue
            '';
          };
        }
      );

      devShells = forAllSystems (system:
        let
          python = getPython system;
          # Create a Python environment with all required packages
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
