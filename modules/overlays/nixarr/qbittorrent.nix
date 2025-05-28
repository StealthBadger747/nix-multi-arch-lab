# qbittorrent-nixarr-overlay.nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.qbittorrent;
  nixarr = config.nixarr;
in {
  options.nixarr.qbittorrent = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the qBittorrent service.

        **Required options:** [`nixarr.enable`](#nixarr.enable)
      '';
    };

    package = mkPackageOption pkgs "qbittorrent-nox" {};

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/qbittorrent";
      example = "/nixarr/.state/qbittorrent";
      description = ''
        The location of the state directory for the qBittorrent service.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.qbittorrent.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for qBittorrent web UI and BitTorrent ports.";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route qBittorrent traffic through the VPN.
      '';
    };

    webUIPort = mkOption {
      type = types.port;
      default = 8080;
      example = 8080;
      description = "qBittorrent web UI port.";
    };

    btPort = mkOption {
      type = types.port;
      default = 32189;
      example = 32189;
      description = "qBittorrent BitTorrent protocol port.";
    };

    user = mkOption {
      type = types.str;
      default = "torrenter";
      description = "User account under which qBittorrent runs.";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Group under which qBittorrent runs.";
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> nixarr.enable;
        message = ''
          The nixarr.qbittorrent.enable option requires the
          nixarr.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.qbittorrent.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups = {
        torrenter = {};
        ${cfg.group} = {};
      };
      users = {
        torrenter = {
          isSystemUser = true;
          group = "torrenter";
        };
      } // lib.optionalAttrs (cfg.user != "torrenter") {
        ${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.stateDir;
          createHome = false;
        };
      };
    };

    systemd.services.qbittorrent = {
      description = "qBittorrent BitTorrent client";
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
        ExecStart = "${cfg.package}/bin/qbittorrent-nox";
        Restart = "on-failure";
        RestartSec = "5s";
        
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "off";
        ProtectHome = false;
        ReadWritePaths = [ cfg.stateDir ];
        
        IOSchedulingPriority = 7;
      };

      environment = {
        WEBUI_PORT = toString cfg.webUIPort;
        HOME = cfg.stateDir;
        XDG_CONFIG_HOME = cfg.stateDir;
        XDG_DATA_HOME = cfg.stateDir;
      };
    };

    systemd.services.qbittorrent.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.webUIPort;
          to = cfg.webUIPort;
        }
      ];
      openVPNPorts = [
        {
          port = cfg.btPort;
          protocol = "both";
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.webUIPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.webUIPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.webUIPort}";
        };
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.webUIPort cfg.btPort ];
      allowedUDPPorts = [ cfg.btPort ];
    };
  };
}
