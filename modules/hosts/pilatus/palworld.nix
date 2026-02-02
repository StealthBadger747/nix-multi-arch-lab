{ config, ... }:
let
  timezone = config.time.timeZone or "UTC";
in {
  systemd.tmpfiles.rules = [
    "d /APPS/PalWorld 0750 erikp users -"
  ];

  sops.templates."palworld.env" = {
    content = ''
      ADMIN_PASSWORD=${config.sops.placeholder."palworld-admin-password"}
      SERVER_PASSWORD=${config.sops.placeholder."palworld-server-password"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
  };

  virtualisation.oci-containers.containers.palworld = {
    image = "docker.io/thijsvanloef/palworld-server-docker:latest";
    autoStart = true;
    ports = [
      "8211:8211/udp"
      "27015:27015/udp"
      "8212:8212/tcp"
    ];
    environmentFiles = [
      config.sops.templates."palworld.env".path
    ];
    environment = {
      PUID = "1000";
      PGID = "100";
      PORT = "8211";
      PLAYERS = "16";
      MULTITHREADING = "true";
      REST_API_ENABLED = "true";
      REST_API_PORT = "8212";
      TZ = timezone;
      COMMUNITY = "false";
      SERVER_NAME = "palworld-server-docker by Thijs van Loef";
      SERVER_DESCRIPTION = "palworld-server-docker by Thijs van Loef";
      CROSSPLAY_PLATFORMS = "(Steam,Xbox,PS5,Mac)";
    };
    volumes = [
      "/APPS/PalWorld:/palworld"
    ];
    extraOptions = [
      "--stop-timeout=30"
    ];
  };

  networking.firewall = {
    allowedUDPPorts = [ 8211 27015 ];
    allowedTCPPorts = [ 8212 ];
  };
}
