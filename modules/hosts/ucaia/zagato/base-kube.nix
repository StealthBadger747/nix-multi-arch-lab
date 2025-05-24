{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: {

  # Required for Rook/Ceph
  boot.kernelModules = [ "rbd" ];

  # Required for Longhorn
  environment.systemPackages = [ pkgs.nfs-utils ];
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };

  networking = {
    nameservers = ["10.0.4.12" "10.0.4.13" "1.1.1.1"];
    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443];
    };
  };
}
