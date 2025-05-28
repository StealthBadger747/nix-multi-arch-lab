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
    ../../overlays/nixarr/qbittorrent.nix
  ];

  environment.systemPackages = with pkgs; [
    attic-client
  ];

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
      lego = {
        owner = "acme";
        group = "acme";
        mode = "0400";
      };
      airvpn-san-jose-imai-conf = {
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
  security.acme = {
    acceptTerms = true;
    defaults.email = "parawell.erik@gmail.com";
    certs.${fqdn} = {
      dnsProvider = "namecheap";
      email = "parawell.erik@gmail.com";
      environmentFile = config.sops.secrets.lego.path;
      group = "nginx";
    };
  };

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
        forceSSL = true;
        useACMEHost = fqdn;
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
      package = pkgs-unstable.flaresolverr;
      openFirewall = true;
    };
  };

  nixarr = {
    enable = true;
    mediaUsers = [ "plex" "erikp" ];
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
      webUIPort = 10095;
      btPort = 12931;
    };
  };

  networking = {
    hostName = "pilatus-nix";
    nameservers = [ "1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };
  };

  system.stateVersion = "24.05";
}
