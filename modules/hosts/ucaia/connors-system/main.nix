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
  ];

  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.tmp.cleanOnBoot = true;

  security.polkit.enable = true;

  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  virtualisation.containers.enable = true;
  virtualisation = {
    docker = {
      enable = true;
    };
  };

  # Disable unnecessary services and features
  services.pulseaudio.enable = false;
  services.pipewire.enable = false;
  hardware.bluetooth.enable = false;
  services.xserver.enable = false;
  services.printing.enable = false;
  services.avahi.enable = false;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.connorgolden = {
    isNormalUser = true;
    group = "users";
    extraGroups = [ "wheel" ];
    description = "Connor Golden";
    hashedPassword =
      "$6$eFjt.8t8Da/iZ1TU$ZWND7XDe5R8h7Zir4P/afyKsCmShfDdGNN1tHGVCLDgcpXkQabcy9Q3S3B0LWHdV6WXz96K5LhL7uSXEAsDZd0";
    openssh.authorizedKeys.keys = [
    ];
  };
  users.users.erikp = {
    isNormalUser = true;
    group = "users";
    extraGroups = [ "wheel" ];
    description = "Erik Parawell";
    hashedPassword =
      "$6$518O2ct8O/.dFXC3$oGwdfF4bgrojKTwE7guwAgtwUaoJAHDJ0IQbrNlahFz75cyaD4ZZ8UHtLFDvrK2v74gu/rErHZJ6W9lMSxQVW.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvJ7EXvVEEar9mTg0Yy/hpsRisRtFPyKXHTpMNtigo7"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKOPFxVGGxI4wBUu1SIgWE6Sr7CSBHNZebXDpSHITxC9"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  networking = {
    hostName = "connor-proxmox-nix";
    nameservers = ["1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9"];
    firewall = {
      enable = true;
      trustedInterfaces = ["docker0"];
      allowedTCPPorts = [22 80 443];
    };
  };

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  programs.nix-ld = {
    enable = true;
    package = pkgs.nix-ld;
  };

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    settings = {
      auto-optimise-store = true;
      trusted-users = [ "root" "erikp" "connorgolden" ];
      experimental-features = [ "flakes" "nix-command" ];
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  system.stateVersion = "24.05";
}
