{ config, pkgs, pkgs-unstable, lib, nixarr, ... }:
let
  host = "pilatus";
  tld = "parawell.cloud";
  fqdn = "${host}.${tld}";
  timezone = "America/Los_Angeles";
in {
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./pc24/zfs.nix
    ./pc24/nfs.nix
    ./palworld.nix
    # ../../overlays/nixarr/qbittorrent.nix
    ../../overlays/nixarr/overseerr.nix
  ];

  environment.systemPackages = (with pkgs; [
      attic-client
      pipx
    ]) ++ 
    ( with pkgs-unstable; [
      claude-code
      direnv
      nh
    ]
  );

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    secrets = {
      inadyn-parawell-cloud = {
        owner = "inadyn";
        group = "inadyn";
        mode = "0400";
        restartUnits = [ "inadyn.service" ];
      };
      airvpn-san-jose-imai-conf = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
      palworld-admin-password = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
      palworld-server-password = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };

  boot.kernel.sysctl = {
    "net.ipv6.bindv6only" = "0";
  };

  security.polkit.enable = true;
  time.timeZone = timezone;

  services = {
    tailscale.enable = true;

    inadyn = {
      enable = true;
      settings = {
        allow-ipv6 = true;
        custom."namecheap" = {
          username = tld;
          include = config.sops.secrets.inadyn-parawell-cloud.path;
          ddns-server = "dynamicdns.park-your-domain.com";
          ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i";
          hostname = [ host ];
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

      virtualHosts.${fqdn} = {
        locations."/" = {
          root = "/var/www/html";  # Default root directory, update as needed
        };
        locations."/.well-known/acme-challenge/" = {
          root = "/var/www/acme-challenge";
        };
      };
    };

    plex = {
      enable = true;
      dataDir = "/APPS/plex/config/Library/Application Support";
      package = pkgs-unstable.plex;
      group = "media";
      openFirewall = true;
    };

    flaresolverr = {
      enable = true;
      # package = pkgs-unstable.flaresolverr;
      openFirewall = true;
    };
    tor = {
      enable = true;

      # this is the critical switch that prevents SOCKSPort 0
      client.enable = true;

      # configure the SOCKS listener
      client.socksListenAddress = {
        addr = "127.0.0.1";
        port = 9050;
        IsolateSOCKSAuth = true;
      };

      settings = {
        SocksPolicy = [
          "accept 127.0.0.1"
          "reject *"
        ];
      };
    };

  };

  systemd.tmpfiles.rules = [
    "d /BIGBOY/proxmox-backups 0750 root root -"
    "d /BIGBOY/pbs 0750 root root -"
    "d /BIGBOY/pbs/etc 0750 root root -"
    "d /BIGBOY/pbs/logs 0750 root root -"
    "d /BIGBOY/pbs/lib 0750 root root -"
  ];

  virtualisation.oci-containers.containers.pbs = {
    image = "docker.io/ayufan/proxmox-backup-server:latest";
    autoStart = true;
    ports = [
      "8007:8007/tcp"
    ];
    environment = {
      TZ = timezone;
    };
    volumes = [
      "/BIGBOY/proxmox-backups:/backups"
      "/BIGBOY/pbs/etc:/etc/proxmox-backup"
      "/BIGBOY/pbs/logs:/var/log/proxmox-backup"
      "/BIGBOY/pbs/lib:/var/lib/proxmox-backup"
    ];
  };

  

  nixarr = {
    enable = true;
    mediaUsers = [ "plex" "jellyfin" "erikp" ];
    mediaDir = "/BIGBOY/nixarr/media";
    vpn = {
      enable = true;
      wgConf = config.sops.secrets.airvpn-san-jose-imai-conf.path;
      openTcpPorts = [ 12931 ];
      openUdpPorts = [ 12931 ];
    };
    radarr = {
      enable = true;
      package = pkgs-unstable.radarr;
      stateDir = "/APPS/arr-apps/radarr";
      openFirewall = true;
    };
    sonarr = {
      enable = true;
      package = pkgs-unstable.sonarr;
      stateDir = "/APPS/arr-apps/sonarr";
      openFirewall = true;
    };
    lidarr = {
      enable = true;
      package = pkgs-unstable.lidarr;
      stateDir = "/APPS/arr-apps/lidarr";
      openFirewall = true;
    };
    prowlarr = {
      enable = true;
      package = pkgs-unstable.prowlarr;
      # stateDir = "/APPS/arr-apps/prowlarr";
      openFirewall = true;
    };
    qbittorrent = {
      enable = true;
      package = pkgs-unstable.qbittorrent-nox;
      stateDir = "/APPS/arr-apps/qbittorrent";
      openFirewall = true;
      vpn.enable = true;
      uiPort = 10095;
      peerPort = 12931;
    };
    
    overseerr = {
      enable = true;
      stateDir = "/APPS/arr-apps/overseerr";
      openFirewall = true;
    };
    jellyfin = {
      enable = true;
      package = pkgs-unstable.jellyfin;
      stateDir = "/APPS/jellyfin";
      openFirewall = true;
    };
  };

  networking = {
    hostName = "pilatus-nix";
    nameservers = [ "1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 8007 ];
    };
  };

  system.stateVersion = "24.05";
}
