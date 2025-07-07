{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {  
  # Set the disk size to 30GiB
  virtualisation.diskSize = 30720;

  proxmox = {
    qemuConf = {
      cores = 4;
      memory = 4096;
      virtio0 = "local-zfs:vm-9999-disk-0";
    };
  };

  # File systems configuration for Proxmox VMs
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    autoResize = true;
    fsType = "ext4";
  };

  boot.loader.grub.device = "/dev/vda";
}
