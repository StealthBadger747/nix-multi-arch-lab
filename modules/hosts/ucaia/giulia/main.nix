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


}
