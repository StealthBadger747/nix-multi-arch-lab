{ config, pkgs, pkgs-unstable, lib, ... }:

{
  # Minimal NVIDIA driver configuration for headless Plex transcoding
  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [nvidia-vaapi-driver];
    };
    nvidia = {
      # Use the proprietary NVIDIA driver package - required for NVENC
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      # Use proprietary drivers for better transcoding performance
      open = false;
      # Enable persistent mode for better performance in server environments
      nvidiaPersistenced = true;
      powerManagement.enable = true;
    };
  };
  
  # Only load the necessary NVIDIA modules
  boot.kernelModules = [ "nvidia" "nvidia-uvm" ];
  # Blacklist nouveau to avoid conflicts
  boot.blacklistedKernelModules = [ "nouveau" ];
  
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11.bin ];
  
  services.xserver.videoDrivers = [ "nvidia" ];
}
