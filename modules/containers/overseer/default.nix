{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "overseerr";
  category = "services";
  image = "ghcr.io/sct/overseerr:1.34.0@sha256:4f38f58d68555004d3f487a4c5cbe2823e6a0942d946a25a2d9391d8492240a4";
  user = "kah";
  group = "media";
  port = 5055;
  appFolder = "/var/lib/${app}";
in
{
  options.mySystem.${category}.${app} = {
    enable = mkEnableOption "${app}";
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${user} = {
      isSystemUser = true;
      group = group;
      home = appFolder;
      createHome = false;
    };

    users.groups.${group} = {};

    systemd.tmpfiles.rules = [
      "d ${appFolder}/ 0750 ${user} ${group} -"
    ];

    virtualisation.oci-containers.containers = config.lib.mySystem.mkContainer {
      inherit app image;
      user = "568";
      group = "568";
      env = { LOG_LEVEL = "info"; };
      volumes = [
        "${appFolder}:/app/config:rw"
      ];
    };
  };
}
