{ inputs, mkPkgsUnstable, mkPkgsFrom, self, ... }:
let
  mkHost = { nixpkgsInput, system, modules, specialArgs ? { } }:
    nixpkgsInput.lib.nixosSystem {
      system = null;
      modules = [
        { nixpkgs.hostPlatform.system = system; }
      ] ++ modules;
      inherit specialArgs;
      pkgs = mkPkgsFrom nixpkgsInput system;
    };
in {
  flake.nixosConfigurations = {
    oci-aarch64-base = mkHost {
      nixpkgsInput = inputs.nixpkgs-oci-aarch64-base;
      system = "aarch64-linux";
      modules = [
        "${inputs.nixpkgs-oci-aarch64-base}/nixos/modules/virtualisation/oci-image.nix"
        ./../modules/configs/common.nix
        ./../modules/hosts/oracle-cloud/base.nix
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "aarch64-linux"; };
    };

    proxmox-base = mkHost {
      nixpkgsInput = inputs.nixpkgs-proxmox-base;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-proxmox-base}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/connors-system/main.nix
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    pc24-proxmox = mkHost {
      nixpkgsInput = inputs.nixpkgs-pc24-proxmox;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-pc24-proxmox}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/configs/common.nix
        ./../modules/hosts/pilatus/pc24.nix
        ./../modules/hosts/pilatus/intel-headless.nix
        inputs.sops-nix.nixosModules.sops
        inputs.nixarr.nixosModules.default
      ];
      specialArgs = {
        pkgs-unstable = mkPkgsUnstable "x86_64-linux";
        inherit (inputs) nixarr;
      };
    };

    oci-authentik = mkHost {
      nixpkgsInput = inputs.nixpkgs-oci-authentik;
      system = "aarch64-linux";
      modules = [
        "${inputs.nixpkgs-oci-authentik}/nixos/modules/virtualisation/oci-image.nix"
        ./../modules/configs/common.nix
        ./../modules/hosts/oracle-cloud/free-aarch64.nix
        inputs.sops-nix.nixosModules.sops
        inputs.authentik-nix.nixosModules.default
        ./../modules/services/ycotd-python-queue.nix
      ];
      specialArgs = {
        pkgs-unstable = mkPkgsUnstable "aarch64-linux";
        inherit (inputs) ycotd-python-queue;
      };
    };

    oci-headscale = inputs.nixpkgs-headplane.lib.nixosSystem {
      system = null;
      modules = [
        { nixpkgs.hostPlatform.system = "x86_64-linux"; }
        "${inputs.nixpkgs-headplane}/nixos/modules/virtualisation/oci-image.nix"
        ./../modules/configs/common.nix
        ./../modules/hosts/oracle-cloud/free-x86.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = {
        pkgs-unstable = mkPkgsUnstable "x86_64-linux";
      };
      pkgs = import inputs.nixpkgs-headplane {
        system = "x86_64-linux";
        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
        };
        overlays = [
          (final: prev:
            let
              mk = prev.lib.systems.elaborate;
            in {
              lib = prev.lib // {
                systems = (prev.lib.systems or { }) // {
                  aarch64-darwin = mk "aarch64-darwin";
                  aarch64-linux = mk "aarch64-linux";
                  x86_64-linux = mk "x86_64-linux";
                  x86_64-darwin = mk "x86_64-darwin";
                  i686-linux = mk "i686-linux";
                };
              };
              headplane = prev.headplane.overrideAttrs (old: {
                pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
                  outputHashAlgo = "sha256";
                  outputHash = "sha256-AYfEL3HSRg87I+Y0fkLthFSDWgHTg5u0DBpzn6KBn1Q=";
                });
                meta = (old.meta or { }) // {
                  platforms = [ prev.stdenv.hostPlatform ];
                  badPlatforms = [ ];
                  broken = false;
                };
              });
              headplane-ssh-wasm = prev.headplane-ssh-wasm.overrideAttrs (old: {
                meta = (old.meta or { }) // {
                  platforms = [ prev.stdenv.hostPlatform ];
                  badPlatforms = [ ];
                  broken = false;
                };
              });
              hp_agent = prev.hp_agent.overrideAttrs (old: {
                meta = (old.meta or { }) // {
                  platforms = [ prev.stdenv.hostPlatform ];
                  badPlatforms = [ ];
                  broken = false;
                };
              });
            })
        ];
      };
    };

    bugatti-proxmox-nix = mkHost {
      nixpkgsInput = inputs.nixpkgs-bugatti-proxmox-nix;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-bugatti-proxmox-nix}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/configs/common.nix
        ./../modules/hosts/gibraltar/bugatti-nix/main.nix
        ./../modules/hosts/gibraltar/bugatti-nix/tailscale.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    zagato-proxmox = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/zagato/default.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    giulia-proxmox = mkHost {
      nixpkgsInput = inputs.nixpkgs-giulia-proxmox;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-giulia-proxmox}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/giulia/default.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    aspen-proxmox = mkHost {
      nixpkgsInput = inputs.nixpkgs-aspen-proxmox;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-aspen-proxmox}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/aspen/default.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = {
        pkgs-unstable = mkPkgsUnstable "x86_64-linux";
        inherit self inputs;
      };
    };

    k3s-master-1 = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/zagato/k3s-nodes/master-1.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    k3s-master-2 = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/zagato/k3s-nodes/master-2.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    k3s-master-3 = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/zagato/k3s-nodes/master-3.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    k3s-worker-1 = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/zagato/k3s-nodes/worker-1.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    k3s-worker-2 = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/virtualisation/proxmox-image.nix"
        ./../modules/hosts/ucaia/zagato/k3s-nodes/worker-2.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };

    k3s-worker-N = mkHost {
      nixpkgsInput = inputs.nixpkgs-zagato;
      system = "x86_64-linux";
      modules = [
        "${inputs.nixpkgs-zagato}/nixos/modules/installer/netboot/netboot-minimal.nix"
        ./../modules/hosts/ucaia/zagato/k3s-nodes/worker-N.nix
        inputs.sops-nix.nixosModules.sops
      ];
      specialArgs = { pkgs-unstable = mkPkgsUnstable "x86_64-linux"; };
    };
  };
}
