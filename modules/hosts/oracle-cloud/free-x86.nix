{ config, pkgs, pkgs-unstable, lib, headplane, ... }:
let
  headscale_host = "oci-headscale";
  headscale_tld = "parawell.cloud";
  headscale_fqdn = "${headscale_host}.${headscale_tld}";
  timezone = "America/New_York";

  headplane_port = "3000";
  headplane_host = "127.0.0.1";

  settingsFormat = pkgs.formats.yaml { };
  headscaleConfig = settingsFormat.generate "headscale-settings.yaml"
    config.services.headscale.settings;
in {
  environment.etc."headscale/config.yaml".source = lib.mkForce
    (settingsFormat.generate "headscale-config.yaml"
      config.services.headscale.settings);

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
      headscale_oidc_client_secret = {
        owner = "headscale";
        group = "headscale";
        mode = "0400";
      };
      headplane_cookie_secret = {
        sopsFile = ../../../secrets/hosts/oracle-cloud/free-x86.yaml;
        owner = "headscale";
        group = "headscale";
        mode = "0400";
      };
      headplane_oidc_client_secret = {
        sopsFile = ../../../secrets/hosts/oracle-cloud/free-x86.yaml;
        owner = "headscale";
        group = "headscale";
        mode = "0400";
      };
      headplane_headscale_api_key = {
        sopsFile = ../../../secrets/hosts/oracle-cloud/free-x86.yaml;
        owner = "headscale";
        group = "headscale";
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

  time.timeZone = timezone;

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
          issuer =
            "https://authentik.parawell.cloud/application/o/test-headscale/";
          client_id = "FylC3SexPmVQagmIx7mT1FrmXpzpjHdQzykXRfMK";
          client_secret_path =
            config.sops.secrets.headscale_oidc_client_secret.path;
          scope = [ "openid" "profile" "email" ];
          # extra_params = {
          #   domain_hint = "parawell.cloud";
          # };
          allowed_users = [
            "parawell.erik@gmail.com"
            "ac130kire@gmail.com"
            "connor@connorgolden.me"
            "nedimazar@gmail.com"
          ];
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
          proxyPass =
            "http://127.0.0.1:${toString config.services.headscale.port}";
          proxyWebsockets = true;
        };
        locations."/admin" = {
          proxyPass = "http://127.0.0.1:${toString config.services.headplane.settings.server.port}";
          proxyWebsockets = true;
        };
        locations."/.well-known/acme-challenge/" = {
          root = "/var/www/acme-challenge";
        };
      };
    };

    headplane = {
      enable = true;
      agent = {
        enable = false;
      };
      settings = {
        server = {
          host = headplane_host;
          port = lib.toInt headplane_port;
          cookie_secret_path = config.sops.secrets.headplane_cookie_secret.path;
          cookie_secure = true;
        };
        agent = {
          enabled = false;
        };
        headscale = {
          url = "https://${headscale_fqdn}";
          # config_path = "${headscaleConfig}";
          # config_strict = false;
          config_path = "${(pkgs.formats.yaml {}).generate "headscale.yml" (
            lib.recursiveUpdate
            config.services.headscale.settings
            {
              acme_email = "/dev/null";
              tls_cert_path = "/dev/null";
              tls_key_path = "/dev/null";
              policy.path = "/dev/null";
              oidc.client_secret_path = "/dev/null";
            }
          )}";
          config_strict = true;
        };
        integration.proc.enabled = true;
        oidc = {
          issuer = "https://authentik.parawell.cloud/application/o/test-headscale/";
          client_id = "FylC3SexPmVQagmIx7mT1FrmXpzpjHdQzykXRfMK";
          client_secret_path = config.sops.secrets.headplane_oidc_client_secret.path;
          disable_api_key_login = false;
          token_endpoint_auth_method = "client_secret_basic";
          headscale_api_key_path = config.sops.secrets.headplane_headscale_api_key.path;
          redirect_uri = "https://${headscale_fqdn}/admin/oidc/callback";
          user_storage_file = "/var/lib/headplane/users.json";
        };
      };
    };
  };

  networking = {
    hostName = "oci-headscale-nix";
    nameservers = [ "1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };
  };

  system.stateVersion = "24.05";
}
