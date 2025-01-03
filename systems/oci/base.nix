{ config, pkgs, lib, ... }:
let
  authentik_host = "authentik";
  authentik_tld = "parawell.cloud";
  authentik_fqdn = "${authentik_host}.${authentik_tld}";
in {

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

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    secrets = {
      inadyn = {
        owner = "inadyn";
        group = "inadyn";
        mode = "0400";
        restartUnits = [ "inadyn.service" ];
      };
      lego = {
        owner = "acme";
        group = "acme";
        mode = "0400";
      };
      authentik = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
      };
    };
  };

  security.polkit.enable = true;
  security.acme = {
    acceptTerms = true;
    defaults.email = "parawell.erik@gmail.com";
    certs.${authentik_fqdn} = {
      dnsProvider = "namecheap";
      email = "parawell.erik@gmail.com";
      environmentFile = config.sops.secrets.lego.path;
      group = "nginx";
    };
  };

  services = {
    tailscale = {
      enable = true;
      useRoutingFeatures = "both";
    };
    
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    inadyn = {
      enable = true;
      settings = {
        allow-ipv6 = true;
        custom."namecheap" = {
          username = authentik_tld;
          include = config.sops.secrets.inadyn.path;
          ddns-server = "dynamicdns.park-your-domain.com";
          ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i";
          hostname = [ authentik_host ];
          ddns-response = "<ErrCount>0</ErrCount>";
        };
      };
    };

    nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;

      virtualHosts.${authentik_fqdn} = {
        forceSSL = true;
        useACMEHost = "authentik.parawell.cloud";
        locations."/" = {
          proxyPass = "http://localhost:9000";
          # proxyPass = "http://localhost:${toString config.services.authentik.port}";
          proxyWebsockets = true;
        };
      };
    };

    authentik = {
      enable = true;
      # The environmentFile needs to be on the target host!
      # Best use something like sops-nix or agenix to manage it
      environmentFile = config.sops.secrets.authentik.path;
      settings = {
        email = {
          host = "mail.privateemail.com";
          port = 465;
          username = "system-alerts@parawell.cloud";
          use_tls = false;
          use_ssl = true;
          from = "system-alerts@parawell.cloud";
        };
        disable_startup_analytics = true;
        avatars = "initials";
      };
    };
  };
  users.users.authentik = {
    isSystemUser = true;
    group = "authentik";
    home = "/var/lib/authentik";
    description = "Authentik Worker User";
    shell = pkgs.bash;
  };
  users.groups.authentik = {};

  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      # Required for containers under podman-compose to be able to talk to each other.
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {
    # headplane = {
    #   image = "ghcr.io/tale/headplane:latest";
    #   autoStart = true;
    #   ports = [ "3000:3000" ];
    #   environment = {
    #     HEADSCALE_URL = "http://headscale:8080";
    #     COOKIE_SECRET = "your_cookie_secret"; # Replace with a secure secret
    #     ROOT_API_KEY = "your_root_api_key";   # Replace with a secure API key
    #     DOCKER_SOCK = "unix:///run/user/${toString config.users.users.erikp.uid}/podman/podman.sock";
    #     # OIDC_CLIENT_ID = "headscale";
    #     # OIDC_ISSUER = "https://sso.example.com";
    #     # OIDC_CLIENT_SECRET = "super_secret_client_secret"; # Replace with your client secret
    #     # DISABLE_API_KEY_LOGIN = "true";
    #     COOKIE_SECURE = "false";
    #     HOST = "0.0.0.0";
    #     PORT = "3000";
    #   };
    #   volumes = [
    #     "/path/to/your/config:/etc/headplane" # Adjust the path as needed
    #   ];
    # };
    # container-name = {
    #   image = "container-image";
    #   autoStart = true;
    #   environment = {
    #     DOCKER_SOCK = "unix:///run/user/${toString config.users.users.erikp.uid}/podman/podman.sock";
    #   };
    #   ports = [ "127.0.0.1:1234:1234" ];
    # };
  };

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
    hostName = "oci-authentik-nix";
    nameservers = ["1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9"];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.erikp = {
    isNormalUser = true;
    group = "users";
    extraGroups = [ "wheel" ];
    description = "Erik Parawell";
    hashedPassword = "$6$518O2ct8O/.dFXC3$oGwdfF4bgrojKTwE7guwAgtwUaoJAHDJ0IQbrNlahFz75cyaD4ZZ8UHtLFDvrK2v74gu/rErHZJ6W9lMSxQVW.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvJ7EXvVEEar9mTg0Yy/hpsRisRtFPyKXHTpMNtigo7"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuxLorajNSQsnpoFC0VnB30hqLsmegYijg6fL6gxBXn"
    ];
  };
  users.users.salima = {
    isNormalUser = true;
    group = "users";
    extraGroups = [ "wheel" ];
    description = "Salima Parawell";
    hashedPassword = "$6$518O2ct8O/.dFXC3$oGwdfF4bgrojKTwE7guwAgtwUaoJAHDJ0IQbrNlahFz75cyaD4ZZ8UHtLFDvrK2v74gu/rErHZJ6W9lMSxQVW.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuxLorajNSQsnpoFC0VnB30hqLsmegYijg6fL6gxBXn" 
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
      experimental-features = ["flakes" "nix-command"];
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
