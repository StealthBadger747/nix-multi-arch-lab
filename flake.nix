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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-oci-aarch64-base.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-proxmox-base.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-pc24-proxmox.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-oci-authentik.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-bugatti-proxmox-nix.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-giulia-proxmox.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-aspen-proxmox.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-zagato.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    authentik-nix.url = "github:nix-community/authentik-nix";
    srvos.url = "github:nix-community/srvos";
    deploy-rs.url = "github:serokell/deploy-rs";
    vulnix = {
      url = "github:flyingcircusio/vulnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs-headplane = {
      url = "github:igor-ramazanov/nixpkgs/headplane-0.5.10";
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

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./parts/core.nix
        ./parts/packages.nix
        ./parts/devshells.nix
        ./parts/checks.nix
        ./parts/nixos-configurations.nix
        ./parts/deploy.nix
      ];
    };
}
