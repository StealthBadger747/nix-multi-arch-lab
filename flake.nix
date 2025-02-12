{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    sops-nix.url = "github:Mic92/sops-nix";
    authentik-nix.url = "github:nix-community/authentik-nix";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Add flake-utils to help with multi-platform support
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, sops-nix, authentik-nix, deploy-rs, flake-utils }:
  let
    # Systems we want to support
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  in
  flake-utils.lib.eachSystem supportedSystems (system: {
    # Dev shell is now per-system
    devShells.default = 
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
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
          ./modules/common.nix
          ./modules/hosts/oracle-cloud/free-aarch64.nix
          sops-nix.nixosModules.sops
          authentik-nix.nixosModules.default
        ];
      };

      # Headscale system
      oci-headscale = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          ./modules/common.nix
          ./modules/hosts/oracle-cloud/free-x86.nix
          sops-nix.nixosModules.sops
        ];
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
