{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ycotd-python-queue;
in {
  options.services.ycotd-python-queue = {
    enable = mkEnableOption "Your Car of the Day Python Email Queue Service";

    package = mkPackageOption pkgs "ycotd-python-queue" {
      default = pkgs.ycotd-python-queue;
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Path to environment file containing Redis and SMTP configuration";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "ycotd-python-queue package not found. Make sure the overlay is properly configured.";
      }
    ];

    users.users.ycotd-email = {
      isSystemUser = true;
      group = "ycotd-email";
      description = "Your Car of the Day Email Queue Service";
      home = "/var/lib/ycotd-email";
      createHome = true;
    };

    users.groups.ycotd-email = {};

    systemd.services.ycotd-python-queue = {
      description = "Your Car of the Day Python Email Queue Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/ycotd-email-queue";
        EnvironmentFile = cfg.environmentFile;
        Restart = "always";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "ycotd-email";
        Group = "ycotd-email";
        WorkingDirectory = "/var/lib/ycotd-email";
        StateDirectory = "ycotd-email";
        StateDirectoryMode = "0750";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
} 
