{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yctod-email-queue;
in {
  options.services.yctod-email-queue = {
    enable = mkEnableOption "Your Car of the Day Email Queue Service";
    environmentFile = mkOption {
      type = types.path;
      description = "Path to environment file containing Redis and SMTP configuration";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.yctod-email-queue = {
      description = "Your Car of the Day Email Queue Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ycotd-email-processor}/bin/ycotd-email-processor";
        EnvironmentFile = cfg.environmentFile;
        Restart = "always";
        RestartSec = "10s";
      };
    };
  };
} 
