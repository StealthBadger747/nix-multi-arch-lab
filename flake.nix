{
  nixConfig = {
    substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos.org"
      "https://cuda-maintainers.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];

    download-buffer-size = 500000000
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    authentik-nix.url = "github:nix-community/authentik-nix";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Add flake-utils to help with multi-platform support
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, sops-nix, authentik-nix, deploy-rs, flake-utils }:
  let
    # Systems we want to support
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    # Helper function to initialize pkgs
    mkPkgs = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # Helper function to initialize pkgs-unstable
    mkPkgsUnstable = system: import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  in
  flake-utils.lib.eachSystem supportedSystems (system: {
    # Dev shell is now per-system
    devShells.default = 
      let
        pkgs = mkPkgs system;
        pkgs-unstable = mkPkgsUnstable system;
      in
      pkgs.mkShell {
        buildInputs = with pkgs; [
          oci-cli
          # terraform
          # python3
          jq
          age
          sops
          nano
          deploy-rs.packages.${system}.default
        ];

        shellHook = ''
          echo "OCI CLI and Terraform development environment loaded"
          echo "OCI CLI version: $(oci --version)"
          # echo "Terraform version: $(terraform version)"

          # Add the script to PATH
          export PATH="$PWD/scripts:$PATH"
          # - 'op://vault/title', 'op://vault/title/field', or 'op://vault/title/section/field'
          export EDITOR=nano
          # alias sops='sops-age-op -k "op://Private/personal_remote_machines/private key" '
          export SOPS_AGE_KEY="$(op read op://Private/age_key/password)"
        '';
      };
  }) // {
    # NixOS configurations remain unchanged but we'll make them more explicit
    nixosConfigurations = {
      # Authentik system
      oci-authentik = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          ./modules/configs/common.nix
          ./modules/hosts/oracle-cloud/free-aarch64.nix
          sops-nix.nixosModules.sops
          authentik-nix.nixosModules.default
        ];
        specialArgs = {
          pkgs-unstable = mkPkgsUnstable "aarch64-linux";
        };
      };

      # Headscale system
      oci-headscale = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          ./modules/configs/common.nix
          ./modules/hosts/oracle-cloud/free-x86.nix
          sops-nix.nixosModules.sops
        ];
        specialArgs = {
          pkgs-unstable = mkPkgsUnstable "x86_64-linux";
        };
      };
    };

    # Deploy-rs configuration
    deploy.nodes = {
      oci-authentik = {
        hostname = "150.136.213.118";
        sshUser = "erikp";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib."aarch64-linux".activate.nixos self.nixosConfigurations.oci-authentik;
          magicRollback = true;
        };
      };

      oci-headscale = {
        hostname = "129.153.154.190";
        sshUser = "erikp";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib."x86_64-linux".activate.nixos self.nixosConfigurations.oci-headscale;
          magicRollback = true;
        };
      };
    };

    # Deployment checks
    checks.aarch64-linux = deploy-rs.lib."aarch64-linux".deployChecks self.deploy;
    checks.x86_64-linux = deploy-rs.lib."x86_64-linux".deployChecks self.deploy;
  };
}
