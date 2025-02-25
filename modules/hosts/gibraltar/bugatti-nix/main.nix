{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: {
  environment.systemPackages = with pkgs; [
    alejandra
    btop
    htop
    tmux
    git
    tree
    wget
    inetutils
    usbutils
    pciutils
    file
    openssl
    cachix
    nix-ld-rs
    wireguard-go
    wireguard-tools
    speedtest-go
    speedtest-cli
    fast-cli
    sops
    nmap
    jq
    busybox
  ];

  programs.nix-ld = {
    enable = true;
    package = pkgs.nix-ld-rs;
  };

  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  networking = {
    hostName = "bugatti-proxmox-nix";
    nameservers = ["1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9"];
    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443];
    };
  };

  # Set your time zone.
  time.timeZone = "Europe/Gibraltar";

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = lib.mkDefault "--delete-older-than 90d";
    };
  };

  system.stateVersion = "24.05";
}
