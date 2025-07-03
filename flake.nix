{
  nixConfig = {
    substituters = [
      "https://cache.nixos.org?priority=1"
      "https://nix-community.cachix.org?priority=2"
      "https://cuda-maintainers.cachix.org?priority=3"
      "https://numtide.cachix.org?priority=4"
      "https://cache.flox.dev?priority=5"
      "https://deploy-rs.cachix.org?priority=6"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
      "deploy-rs.cachix.org-1:xfNobmiwF/vzvK1gpfediPwpdIP0rpDV2rYqx40zdSI="
    ];

    download-buffer-size = 1000000000;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-overseerr.url = "github:jf-uu/nixpkgs/overseerr";
    sops-nix.url = "github:Mic92/sops-nix";
    authentik-nix.url = "github:marcelcoding/authentik-nix";
    # authentik-nix.url = "github:nix-community/authentik-nix";
    srvos.url = "github:nix-community/srvos";
    deploy-rs.url = "github:serokell/deploy-rs";
    vulnix = {
      url = "github:flyingcircusio/vulnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    headplane = {
      # url = "github:StealthBadger747/headplane/erikp/implement-path-loader";
      url = "github:igor-ramazanov/headplane/update-nix-changes-branch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ycotd-python-queue = {
      url = "git+ssh://git@github.com/StealthBadger747/ycotd-python-queue";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarr = {
      url = "github:StealthBadger747/nixarr/add-qbittorrent";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-overseerr, sops-nix, authentik-nix
    , srvos, deploy-rs, vulnix, flake-utils, headplane, ycotd-python-queue, nixarr }:
    let
      # Systems we want to support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      # Helper function to initialize pkgs
      mkPkgs = system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          crossSystem = if system == "aarch64-linux" then {
            config = "aarch64-unknown-linux-gnu";
            system = "aarch64-linux";
          } else null;
        };

      # Helper function to initialize pkgs-unstable
      mkPkgsUnstable = system:
        import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
          crossSystem = if system == "aarch64-linux" then {
            config = "aarch64-unknown-linux-gnu";
            system = "aarch64-linux";
          } else null;
        };

      mkCustomExtraPackages = system:
        import nixpkgs-overseerr {
          inherit system;
          config.allowUnfree = true;
          crossSystem = if system == "aarch64-linux" then {
            config = "aarch64-unknown-linux-gnu";
            system = "aarch64-linux";
          } else null;
        };
    in flake-utils.lib.eachSystem supportedSystems (system: {
      checks.vulnix = {
        forSystems = supportedSystems;
        builder = system:
          let pkgs = mkPkgs system;
          in pkgs.runCommand "vulnix-vulnerability-check" {
            buildInputs = [ pkgs.vulnix ];
          } ''
            set -e
            vulnix --system --verbose > $out 2>&1
            echo "Vulnerability check completed successfully" >> $out
          '';
      };

      packages = {
        oci-aarch64-image = 
          let
            aarch64Config = self.nixosConfigurations.oci-aarch64-base;
          in
          if system == "aarch64-linux"
          then aarch64Config.config.system.build.OCIImage
          else nixpkgs.legacyPackages.${system}.runCommand "oci-aarch64-image" {} ''
            echo "This package can only be built on aarch64-linux systems"
            exit 1
          '';
        proxmox-x86-linux-image = 
          let 
            config = self.nixosConfigurations.proxmox-base;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "proxmox-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';

        pc24-proxmox-image = 
          let 
            config = self.nixosConfigurations.pc24-proxmox;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "pc24-proxmox-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';

        zagato-proxmox-image = 
          let 
            config = self.nixosConfigurations.zagato-proxmox;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "zagato-proxmox-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';

        giulia-proxmox-image = 
          let 
            config = self.nixosConfigurations.giulia-proxmox;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "giulia-proxmox-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
          
        # K3s cluster node images
        k3s-master-1-image = 
          let 
            config = self.nixosConfigurations.k3s-master-1;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "k3s-master-1-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
          
        k3s-master-2-image = 
          let 
            config = self.nixosConfigurations.k3s-master-2;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "k3s-master-2-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
          
        k3s-master-3-image = 
          let 
            config = self.nixosConfigurations.k3s-master-3;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "k3s-master-3-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
          
        k3s-worker-1-image = 
          let 
            config = self.nixosConfigurations.k3s-worker-1;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "k3s-worker-1-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
          
        k3s-worker-2-image = 
          let 
            config = self.nixosConfigurations.k3s-worker-2;
          in
          if system == "x86_64-linux"
          then config.config.system.build.VMA
          else nixpkgs.legacyPackages.${system}.runCommand "k3s-worker-2-image" {} ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
      };

      # Dev shell is now per-system
      devShells.default = let
        pkgs = mkPkgs system;
        pkgs-unstable = mkPkgsUnstable system;
      in pkgs.mkShell {
        buildInputs = (with pkgs; [
          jq
          age
          sops
          nano
          nh
        ]) ++ ( with pkgs-unstable; [
          # oci-cli
          # opentofu
          deploy-rs.packages.${system}.default
          # vulnix.packages.${system}.default
        ]);

        shellHook = ''
          echo "OCI CLI version: $(oci --version)"
          echo "Opentofu version: $(tofu version)"
          echo "Available image builders:"
          echo " - nix build .#oci-aarch64-image       # For Oracle Cloud (aarch64)"
          echo " - nix build .#proxmox-x86-linux-image # For Proxmox (x86_64)"

          # Add the script to PATH
          export PATH="$PWD/scripts:$PATH"
          # - 'op://vault/title', 'op://vault/title/field', or 'op://vault/title/section/field'
          export EDITOR=nano
          # alias sops='sops-age-op -k "op://Private/personal_remote_machines/private key" '
          # export SOPS_AGE_KEY="$(op read op://Private/age_key/password)"
        '';
      };
    }) // {
      # NixOS configurations remain unchanged but we'll make them more explicit
      nixosConfigurations = {
        # Base OCI aarch64
        oci-aarch64-base = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
            ./modules/configs/common.nix
            ./modules/hosts/oracle-cloud/base.nix
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "aarch64-linux"; };
        };

        # Base Proxmox x86-64
        proxmox-base = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/connors-system/main.nix
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        pc24-proxmox = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/configs/common.nix
            ./modules/hosts/pilatus/pc24.nix
            ./modules/hosts/pilatus/nvidia-headless.nix
            sops-nix.nixosModules.sops
            nixarr.nixosModules.default
          ];
          specialArgs = {
            pkgs-unstable = mkPkgsUnstable "x86_64-linux";
            pkgs-overseerr = mkCustomExtraPackages "x86_64-linux";
            inherit nixarr;
          };
        };
        
        # Authentik system
        oci-authentik = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
            ./modules/configs/common.nix
            ./modules/hosts/oracle-cloud/free-aarch64.nix
            sops-nix.nixosModules.sops
            authentik-nix.nixosModules.default
            ycotd-python-queue.nixosModules.ycotd-python-queue
          ];
          specialArgs = { 
            pkgs-unstable = mkPkgsUnstable "aarch64-linux";
            inherit ycotd-python-queue;
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
            headplane.nixosModules.headplane
          ];
          specialArgs = { 
            pkgs-unstable = mkPkgsUnstable "x86_64-linux";
            inherit headplane;
          };
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
            overlays = [ headplane.overlays.default ];
          };
        };

        # Bugatti Proxmox Nix
        bugatti-proxmox-nix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/configs/common.nix
            ./modules/hosts/gibraltar/bugatti-nix/main.nix
            ./modules/hosts/gibraltar/bugatti-nix/tailscale.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        # Base Zagato Proxmox Image
        zagato-proxmox = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/zagato/default.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        giulia-proxmox = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/giulia/default.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        # K3s Cluster Node 1 (Master)
        k3s-master-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/zagato/k3s-nodes/master-1.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        # K3s Cluster Node 2 (Master)
        k3s-master-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/zagato/k3s-nodes/master-2.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        # K3s Cluster Node 3 (Master)
        k3s-master-3 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/zagato/k3s-nodes/master-3.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        # K3s Cluster Node 4 (Worker)
        k3s-worker-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/zagato/k3s-nodes/worker-1.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };

        # K3s Cluster Node 5 (Worker)
        k3s-worker-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
            ./modules/hosts/ucaia/zagato/k3s-nodes/worker-2.nix
            sops-nix.nixosModules.sops
          ];
          specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
        };
      };

      # Deploy-rs configuration
      deploy.nodes = {
        oci-authentik = {
          hostname = "150.136.213.118";
          sshUser = "erikp";
          fastConnection = true;
          autoRollback = false;  # Temporarily disabled for debugging
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."aarch64-linux".activate.nixos
              self.nixosConfigurations.oci-authentik;
            magicRollback = true;
            remoteBuild = true;
            sshOpts = [ "-o" "StrictHostKeyChecking=no" ];
          };
        };

        oci-headscale = {
          hostname = "129.153.154.190";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.oci-headscale;
            magicRollback = true;
          };
        };

        pc24-proxmox = {
          hostname = "100.64.0.46";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.pc24-proxmox;
            magicRollback = true;
          };
        };

        gib-bugatti = {
          hostname = "100.64.0.28";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.bugatti-proxmox-nix;
            magicRollback = true;
            # remoteBuild = true;
          };
        };

        giulia = {
          hostname = "10.0.4.33";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.giulia-proxmox;
            magicRollback = true;
          };
        };

        zagato-master-01 = {
          hostname = "10.0.4.201";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.k3s-master-1;
            magicRollback = true;
          };
        };

        zagato-master-02 = {
          hostname = "10.0.4.202";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.k3s-master-2;
            magicRollback = true;
          };
        };

        zagato-master-03 = {
          hostname = "10.0.4.203";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.k3s-master-3;
            magicRollback = true;
          };
        };

        zagato-worker-01 = {
          hostname = "10.0.4.204";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.k3s-worker-1;
            magicRollback = false;
          };
        };

        zagato-worker-02 = {
          hostname = "10.0.4.205";
          sshUser = "erikp";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."x86_64-linux".activate.nixos
              self.nixosConfigurations.k3s-worker-2;
            magicRollback = false;
          };
        };
      };

      # Deployment checks
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
