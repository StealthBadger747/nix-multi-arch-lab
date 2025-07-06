{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: {
  sops = {
    defaultSopsFile = ../../../../secrets/hosts/gibraltar/bugatti-nix-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
  };


  environment.systemPackages = (with pkgs; [
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
    wireguard-go
    wireguard-tools
    speedtest-go
    speedtest-cli
    fast-cli
    sops
    nmap
    jq
    busybox
    neofetch
  ]) ++ ( with pkgs-unstable; [
    claude-code
  ]);

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

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
