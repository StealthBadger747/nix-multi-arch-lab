# overseerr-nixarr-overlay.nix
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
with lib; let
  cfg = config.nixarr.overseerr;
  nixarr = config.nixarr;
  pkg = pkgs-unstable.overseerr;
in {
  options.nixarr.overseerr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Overseerr service.

        **Required options:** [`nixarr.enable`](#nixarr.enable)
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkg;
      description = "Overseerr package to use";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/overseerr";
      example = "/nixarr/.state/overseerr";
      description = ''
        The location of the state directory for the Overseerr service.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.overseerr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Overseerr web UI.";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Overseerr traffic through the VPN.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 5055;
      example = 5055;
      description = "Overseerr web UI port.";
    };

    user = mkOption {
      type = types.str;
      default = "overseerr";
      description = "User account under which Overseerr runs.";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Group under which Overseerr runs.";
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> nixarr.enable;
        message = ''
          The nixarr.overseerr.enable option requires the
          nixarr.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.overseerr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${cfg.group} = {};
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = false;
      };
    };

    systemd.services.overseerr = {
      description = "Overseerr Media Request Management";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        mkdir -p "${cfg.stateDir}"
        chown ${cfg.user}:${cfg.group} "${cfg.stateDir}"
        chmod 750 "${cfg.stateDir}"
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/overseerr";
        WorkingDirectory = "${cfg.package}/libexec/overseerr/deps/overseerr";
        Restart = "on-failure";
        RestartSec = "5s";
        
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.stateDir ];
      };

      environment = {
        PORT = toString cfg.port;
        NODE_ENV = "production";
        HOME = cfg.stateDir;
        CONFIG_DIRECTORY = cfg.stateDir;
      };
    };

    systemd.services.overseerr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.port;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.port}";
        };
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
