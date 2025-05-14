{ config, pkgs, lib, ... }:

{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  
  # Import only the APPS and BIGBOY pools
  boot.zfs.extraPools = [ "APPS" "BIGBOY" ];
  
  # Use device IDs for stable pool imports
  boot.zfs.devNodes = "/dev/disk/by-id";
  
  # Required hostId for ZFS
  # Generate a deterministic hostId based on hostname
  networking.hostId = builtins.substring 0 8 (
    builtins.hashString "md5" config.networking.hostName
  );
  
  # Create mount points for ZFS pools
  systemd.tmpfiles.rules = [
    "d /mnt/APPS 0755 root root -"
    "d /mnt/BIGBOY 0755 root root -"
  ];
}
