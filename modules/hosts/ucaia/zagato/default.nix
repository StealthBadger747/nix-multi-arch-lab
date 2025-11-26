{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: {

  nix.settings = {
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
  };

  imports = [
    ./base-kube.nix
  ];

  environment.systemPackages = with pkgs; [
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
    sops
    nmap
    jq
    busybox
    neofetch
  ];

  boot.tmp.cleanOnBoot = true;
  # boot.kernelParams = [
  #   "mitigations=off"
  # ];

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
      "$6$e75Jf/dlhJJ.dF49$9vAbUWwYqrGqtT4I/T6ycHvEM6Z23n9Z3jKunoXwdBVS5rXhWW6VEGRohQCvltPS9lP8t0PL6bLMzWGIEAW.n/";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENMEKtS2wB5NlWSAtsoKTss1B0UcD/TeDbMJgVdUKXJ"
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

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  programs.nix-ld = {
    enable = true;
    package = pkgs.nix-ld-rs;
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
