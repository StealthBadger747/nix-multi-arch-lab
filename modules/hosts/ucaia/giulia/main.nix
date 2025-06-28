{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: let
  hostName = "giulia";
in {
  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=B0:50:D9:A3:F8:10,bridge=vmbr0,firewall=1";
    };
  };

  # Enable cloud-init network configuration
  services.cloud-init.network.enable = true;

  virtualisation.containers.enable = true;
  virtualisation = {
    docker = {
      enable = true;
    };
  };

  environment.systemPackages = (with pkgs; [
      # stuff here
    ]) ++ 
    ( with pkgs-unstable; [
      # stuff here
    ]
  );

  fileSystems."/media-server" = {
    device = "/dev/disk/by-uuid/f7265bb9-aa58-45f8-8a93-fdfa7d3d3727";
    autoResize = true;
    fsType = "ext4";
  };

}
