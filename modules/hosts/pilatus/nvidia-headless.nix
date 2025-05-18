{ config, pkgs, lib, ... }:

{
  boot.kernelParams = [ "nvidia_drm.fbdev=0" ];
  boot.initrd.kernelModules = [ "nvidia" "nvidia-uvm" "nvidia-drm" ];
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelModules = [ "nvidia" "nvidia-uvm" "nvidia-drm" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11.bin ];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = false;
    nvidiaPersistenced = true;
    powerManagement.enable = false;
    modesetting.enable = true;   # explicit, though it defaults to false
  };

  environment.systemPackages = with pkgs; [
    (config.boot.kernelPackages.nvidiaPackages.stable).bin
    cudatoolkit
    nvidia-container-toolkit
    nvtopPackages.nvidia
    # nvidia-x11 nvidia-settings  # optional in pure headless setups
    nvidia-vaapi-driver         # if you want VA-API wrappers
  ];

  services.xserver.enable = false;
}
