{ lib, pkgs, ... }:
let
  dataRoot = "/BIGBOY/seaweedfs";
  weed = "${pkgs.seaweedfs}/bin/weed";
  internalPorts = [ 8080 8181 8888 9333 18080 18333 18888 19333 33646 ];

  dropInternalPortCommands = lib.concatMapStringsSep "\n" (port:
    let portString = toString port;
    in ''
      iptables -C INPUT ! -i lo -p tcp --dport ${portString} -m comment --comment seaweedfs-internal -j DROP 2>/dev/null || \
        iptables -I INPUT 1 ! -i lo -p tcp --dport ${portString} -m comment --comment seaweedfs-internal -j DROP
      ip6tables -C INPUT ! -i lo -p tcp --dport ${portString} -m comment --comment seaweedfs-internal -j DROP 2>/dev/null || \
        ip6tables -I INPUT 1 ! -i lo -p tcp --dport ${portString} -m comment --comment seaweedfs-internal -j DROP
    ''
  ) internalPorts;

  removeInternalPortCommands = lib.concatMapStringsSep "\n" (port:
    let portString = toString port;
    in ''
      iptables -D INPUT ! -i lo -p tcp --dport ${portString} -m comment --comment seaweedfs-internal -j DROP 2>/dev/null || true
      ip6tables -D INPUT ! -i lo -p tcp --dport ${portString} -m comment --comment seaweedfs-internal -j DROP 2>/dev/null || true
    ''
  ) internalPorts;

  serverArgs = [
    "server"
    "-dir=${dataRoot}/volume"
    "-master.dir=${dataRoot}/master"
    "-volume.dir.idx=${dataRoot}/idx"
    "-ip.bind=0.0.0.0"
    "-volume.disk=hdd"
    "-volume.max=0"
    "-filer"
    "-filer.port=8888"
    "-s3"
    "-s3.port=8333"
    "-s3.port.iceberg=0"
  ];

  adminArgs = [
    "admin"
    "-master=localhost:9333"
    "-port=23646"
    "-dataDir=${dataRoot}/admin"
  ];

  prepareDataDirs = pkgs.writeShellScript "seaweedfs-prepare-data-dirs" ''
    set -eu
    ${pkgs.util-linux}/bin/mountpoint -q ${dataRoot}
    ${pkgs.coreutils}/bin/install -d -o seaweedfs -g seaweedfs -m 0750 \
      ${dataRoot}/master \
      ${dataRoot}/volume \
      ${dataRoot}/idx \
      ${dataRoot}/filer \
      ${dataRoot}/admin
  '';
in
{
  environment.systemPackages = [ pkgs.seaweedfs ];

  users.groups.seaweedfs = { };
  users.users.seaweedfs = {
    isSystemUser = true;
    group = "seaweedfs";
    home = dataRoot;
  };

  networking.firewall.allowedTCPPorts = [ 8333 23646 ];
  networking.firewall.extraCommands = dropInternalPortCommands;
  networking.firewall.extraStopCommands = removeInternalPortCommands;

  systemd.services.seaweedfs = {
    description = "SeaweedFS backup target";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "zfs-mount.service" ];
    unitConfig.RequiresMountsFor = [ dataRoot ];

    serviceConfig = {
      ExecStartPre = "+${prepareDataDirs}";
      ExecStart = "${weed} ${lib.concatStringsSep " " serverArgs}";
      User = "seaweedfs";
      Group = "seaweedfs";
      Restart = "on-failure";
      RestartSec = "5s";
      WorkingDirectory = "${dataRoot}/filer";
      StateDirectory = "seaweedfs";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dataRoot ];
    };
  };

  systemd.services.seaweedfs-admin = {
    description = "SeaweedFS admin UI";
    wantedBy = [ "multi-user.target" ];
    wants = [ "seaweedfs.service" ];
    after = [ "seaweedfs.service" ];
    unitConfig.RequiresMountsFor = [ dataRoot ];

    serviceConfig = {
      ExecStartPre = "+${prepareDataDirs}";
      ExecStart = "${weed} ${lib.concatStringsSep " " adminArgs}";
      EnvironmentFile = "/etc/seaweedfs/admin.env";
      User = "seaweedfs";
      Group = "seaweedfs";
      Restart = "on-failure";
      RestartSec = "5s";
      WorkingDirectory = dataRoot;
      StateDirectory = "seaweedfs-admin";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dataRoot ];
    };
  };
}
