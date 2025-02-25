{ config, pkgs, lib, ... }: {
  environment.systemPackages = with pkgs; [
    btop
    htop
    tmux
    ncdu
    git
    tree
    wget
    inetutils
    usbutils
    pciutils
    file
    openssl
    home-manager
    polkit
    cachix
    sops
  ];

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
    podman = {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  virtualisation.oci-containers.backend = "podman";

  # Disable unnecessary services and features
  hardware.pulseaudio.enable = false;
  services.pipewire.enable = false;
  hardware.bluetooth.enable = false;
  services.xserver.enable = false;
  documentation.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.man.enable = false;
  services.printing.enable = false;
  services.avahi.enable = false;

  networking = {
    nameservers = [ "1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with 'passwd'.
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

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    settings = {
      auto-optimise-store = true;
      trusted-users = [ "root" "erikp" ];
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
}
