{ config, pkgs, pkgs-unstable, lib, ... }:
let
  headscale_host = "oci-headscale";
  headscale_tld = "parawell.cloud";
  headscale_fqdn = "${headscale_host}.${headscale_tld}";
  timezone = "America/New_York";

  headplane_port = "3000";
  headplanePkg = pkgs.callPackage ../packages/headplane.nix {};

  settingsFormat = pkgs.formats.yaml {};
  headscaleConfig = settingsFormat.generate "headscale-settings.yaml" config.services.headscale.settings;
in {
  environment.etc."headscale/config.yaml".source = 
    lib.mkForce (settingsFormat.generate "headscale-config.yaml" config.services.headscale.settings);

  environment.systemPackages = (with pkgs; [
    headplanePkg
  ])
  ++ (with pkgs-unstable; [
  ]);

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
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
      headscale_oidc_client_secret = {
        owner = "headscale";
        group = "headscale";
        mode = "0400";
      };
      headplane = {
        owner = "headplane";
        group = "headplane";
        mode = "0400";
      };
    };
  };
  
  security.polkit.enable = true;
  security.acme = {
    acceptTerms = true;
    defaults.email = "parawell.erik@gmail.com";
    certs.${headscale_fqdn} = {
      dnsProvider = "namecheap";
      email = "parawell.erik@gmail.com";
      environmentFile = config.sops.secrets.lego.path;
      group = "nginx";
    };
  };

  services = {
    tailscale.enable = true;

    inadyn = {
      enable = true;
      settings = {
        allow-ipv6 = true;
        custom."namecheap" = {
          username = headscale_tld;
          include = config.sops.secrets.inadyn-parawell-cloud.path;
          ddns-server = "dynamicdns.park-your-domain.com";
          ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i";
          hostname = [ headscale_host ];
          ddns-response = "<ErrCount>0</ErrCount>";
        };
      };
    };

    headscale = {
      enable = true;
      address = "127.0.0.1";
      port = 8080;
      package = pkgs-unstable.headscale;
      settings = {
        server_url = "https://${headscale_fqdn}";
        dns.base_domain = "internal-${headscale_fqdn}";
        oidc = {
          issuer = "https://authentik.parawell.cloud/application/o/test-headscale/";
          client_id = "FylC3SexPmVQagmIx7mT1FrmXpzpjHdQzykXRfMK";
          client_secret_path = config.sops.secrets.headscale_oidc_client_secret.path;
          scope = [ "openid" "profile" "email" ];
          # extra_params = {
          #   domain_hint = "parawell.cloud";
          # };
          allowed_users = [ "parawell.erik@gmail.com" "ac130kire@gmail.com" "connor@connorgolden.me" "nedimazar@gmail.com" ];
          # allowed_domains = [ "parawell.cloud" ];
          strip_email_domain = true;
        };
      };
    };

    nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;

      virtualHosts.${headscale_fqdn} = {
        forceSSL = true;
        useACMEHost = headscale_fqdn;
        locations."/" = {
          proxyPass = "http://localhost:${toString config.services.headscale.port}";
          proxyWebsockets = true;
        };
        locations."/admin" = {
          proxyPass = "http://localhost:${headplane_port}/admin";
          proxyWebsockets = true;
        };
        locations."/.well-known/acme-challenge/" = {
          root = "/var/www/acme-challenge";
        };
      };
    };
  };

  systemd.services.headplane = {
    description = "Headplane Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${headplanePkg}/bin/headplane";
      WorkingDirectory = "${headplanePkg}";
      Restart = "always";
      User = "headplane";
      Group = "headplane";
      EnvironmentFile = config.sops.secrets.headplane.path;
      Environment = [
        "HOST=127.0.0.1"
        "PORT=${headplane_port}"
        "HEADSCALE_INTEGRATION=proc"
        "HEADSCALE_URL=https://${headscale_fqdn}"
        "DEBUG=true"
        "HEADSCALE_CONFIG_UNSTRICT=true"
      ];
    };
  };
  users.users.headplane = {
    isSystemUser = true;
    group = "headplane";
    home = "/var/lib/headplane";
    description = "Headplane Service User";
    shell = pkgs.bash;
  };
  users.groups.headplane = {};

  networking = {
    hostName = "oci-headscale-nix";
    nameservers = ["1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9"];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };
  };

  # Set your time zone.
  time.timeZone = timezone;
  system.stateVersion = "24.05";
}
