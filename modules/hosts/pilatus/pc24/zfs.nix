{ config, lib, pkgs, ... }:
let
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{
  # Note this might jump back and forth as kernels are added or removed.
  boot.kernelPackages = latestKernelPackage;

  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  
  # Import pools
  boot.zfs.extraPools = [ "APPS" "BIGBOY" ];
  
  # Use device IDs for stable pool imports
  boot.zfs.devNodes = "/dev/disk/by-id";
  
  # # Required hostId for ZFS
  networking.hostId = "3ab7c58a";
  
  # L2ARC tuning - adjust parameters for the 1TB SSD cache (WDC drive)
  boot.kernelParams = [
    # Increase ARC max size to reasonable level (4GB RAM)
    "zfs.zfs_arc_max=4294967296"
    # L2ARC tuning parameters - optimal for SSD cache
    "zfs.l2arc_write_max=67108864"    # 64MB max write size per interval
    "zfs.l2arc_write_boost=134217728" # Initial 128MB write boost 
  ];
  
  # Create mount points for ZFS pools if needed
  systemd.tmpfiles.rules = [
    "d /mnt/APPS 0755 root root -"
    "d /mnt/BIGBOY 0755 root root -"
  ];
}
