{ config, pkgs, lib, ... }:
let
  authentik_host = "authentik";
  authentik_tld = "parawell.cloud";
  authentik_fqdn = "${authentik_host}.${authentik_tld}";
  authentik_port = 9000;
  foundry_host = "foundry";
  foundry_tld = "weconverse.net";
  foundry_fqdn = "${foundry_host}.${foundry_tld}";
  foundry_port = 30000;
  timezone = "America/New_York";
in {
  # imports = [
  #   (import ../../../ycotd-python-queue).nixosModules.ycotd-python-queue
  # ];

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
      inadyn-weconverse-net = {
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
      foundryvtt = {
        owner = "erikp";
        group = "users";
        mode = "0400";
        restartUnits = [ "podman-foundryvtt.service" ];
      };
      oci-aarch64-wireguard-private-key = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      ycotd-email = {
        sopsFile = ../../../secrets/hosts/oracle-cloud/free-aarch64.yaml;
        owner = "ycotd-email";
        group = "ycotd-email";
        mode = "0400";
        restartUnits = [ "ycotd-python-queue.service" ];
      };
      attic-env = {
        sopsFile = ../../../secrets/hosts/oracle-cloud/free-aarch64.yaml;
        owner = "atticd";
        group = "atticd";
        mode = "0400";
        restartUnits = [ "atticd.service" ];
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
    certs.${foundry_fqdn} = {
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

    atticd = {
      enable = true;
      user = "atticd";
      group = "atticd";
      environmentFile = config.sops.secrets.attic-env.path;
      settings = {
        listen = "100.64.0.31:8080";
        database = {
          url = "sqlite:///var/lib/atticd/db.sqlite";
        };
        storage = {
          type = "local";
          path = "/var/lib/atticd/storage";
        };
      };
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
        custom."namecheap-parawell" = {
          username = "parawell.cloud";
          include = config.sops.secrets.inadyn-parawell-cloud.path;
          ddns-server = "dynamicdns.park-your-domain.com";
          ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i";
          hostname = [ authentik_host ];
          ddns-response = "<ErrCount>0</ErrCount>";
        };
        custom."namecheap-weconverse" = {
          username = "weconverse.net";
          include = config.sops.secrets.inadyn-weconverse-net.path;
          ddns-server = "dynamicdns.park-your-domain.com";
          ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i";
          hostname = [ foundry_host ];
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
        useACMEHost = authentik_fqdn;
        locations."/" = {
          # proxyPass = "http://localhost:9000";
          # proxyPass = "http://localhost:${toString config.services.authentik.port}";
          proxyPass = "http://localhost:${toString authentik_port}";
          proxyWebsockets = true;
        };
      };
      virtualHosts.${foundry_fqdn} = {
        forceSSL = true;
        useACMEHost = foundry_fqdn;
        locations."/" = {
          proxyPass = "http://localhost:${toString foundry_port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
      virtualHosts."_" = {
        default = true;
        locations."/" = {
          return = "404";
          # Or serve a custom 404 page:
          # root = "/var/www/error-pages";
          # tryFiles = "/404.html =404";
        };
      };
    };

    authentik = {
      enable = true;
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

    ycotd-python-queue = {
      enable = true;
      environmentFile = config.sops.secrets.ycotd-email.path;
    };
  };
  users.users.authentik = {
    isSystemUser = true;
    group = "authentik";
    home = "/var/lib/authentik";
    description = "Authentik Worker User";
    shell = pkgs.bash;
  };
  users.groups.authentik = { };
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
    home = "/var/lib/atticd";
    description = "Attic Server User";
    shell = pkgs.bash;
  };
  users.groups.atticd = { };

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
    foundryvtt = {
      image = "docker.io/felddy/foundryvtt@sha256:1bfeaf21c2cfd5f8657c2e559901a729e2b0a5368fbf425b1d7a865dd1b7e816";
      autoStart = true;
      ports = [ "127.0.0.1:${toString foundry_port}:30000" ];
      environmentFiles = [ config.sops.secrets.foundryvtt.path ];
      volumes = [ "/var/lib/foundryvtt:/data" ];
      environment = {
        CONTAINER_PRESERVE_CONFIG = "false";
        FOUNDRY_HOSTNAME = foundry_fqdn;
        FOUNDRY_PROXY_SSL = "true";
        FOUNDRY_PROXY_PORT = "443";
        FOUNDRY_COMPRESS_WEBSOCKET = "true";
        FOUNDRY_MINIFY_STATIC_FILES = "true";
        FOUNDRY_IP_DISCOVERY = "false";
        FOUNDRY_UPNP = "false";
        FOUNDRY_TELEMETRY = "true";
        TIMEZONE = timezone;
      };
      extraOptions = ["--no-healthcheck"];
    };
  };

  networking = {
    hostName = "oci-authentik-nix";
    nameservers = [ "1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 8080 ];
      allowedUDPPorts = [ 51820 ];
    };

    # Wireguard stuff
    nat.enable = true;
    nat.externalInterface = "enp0s6";
    nat.internalInterfaces = [ "wg0" ];
    wireguard.enable = false;

    wireguard.interfaces = {
      wg0 = {
        ips = [ "10.100.0.1/24" ];
        listenPort = 51820;

        # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
        # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
        postSetup = ''
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o enp0s6 -j MASQUERADE
        '';

        # This undoes the above command
        postShutdown = ''
          ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o enp0s6 -j MASQUERADE
        '';
        privateKeyFile = config.sops.secrets.oci-aarch64-wireguard-private-key.path;

        peers = [
          # List of allowed peers.
          # { # Bugatti Nix
          #   publicKey = "{john doe's public key}";
          #   allowedIPs = [ "10.100.0.2/32" ];
          # }
        ];
      };
    };
  };

  time.timeZone = timezone;

  users.users.salima = {
    isNormalUser = true;
    group = "users";
    extraGroups = [ "wheel" ];
    description = "Salima Parawell";
    hashedPassword =
      "$6$518O2ct8O/.dFXC3$oGwdfF4bgrojKTwE7guwAgtwUaoJAHDJ0IQbrNlahFz75cyaD4ZZ8UHtLFDvrK2v74gu/rErHZJ6W9lMSxQVW.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuxLorajNSQsnpoFC0VnB30hqLsmegYijg6fL6gxBXn"
    ];
  };

  system.stateVersion = "24.05";
}
