{ config, lib, pkgs, ycotd-python-queue, ... }:

with lib;

let
  cfg = config.services.ycotd-python-queue;
in {
  options.services.ycotd-python-queue = {
    enable = mkEnableOption "YourCarOfTheDay email queue worker";
    environmentFile = mkOption {
      type = types.path;
      description = "Environment file for the service";
    };
  };

  config = mkIf cfg.enable {
    users.users.ycotd-email = {
      isSystemUser = true;
      group = "ycotd-email";
      description = "YourCarOfTheDay email queue worker";
    };
    users.groups.ycotd-email = {};

    systemd.services.ycotd-python-queue = {
      description = "YourCarOfTheDay email queue worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        User = "ycotd-email";
        Group = "ycotd-email";
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${ycotd-python-queue.packages.${pkgs.system}.default}/bin/ycotd-email-queue";
        Restart = "always";
      };
    };
  };
} 
