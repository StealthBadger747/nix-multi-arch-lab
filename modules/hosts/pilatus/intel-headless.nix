{ config, lib, pkgs, ... }:
{
  # Intel graphics stack
  hardware.graphics = {
    enable = true;
    # VAAPI + QSV (VPL runtime) for Arc
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
    ];
  };

  hardware.enableRedistributableFirmware = true;

  boot.kernelParams = [
    "i915.enable_guc=3"
  ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
    LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
  };

  security.wrappers.intel_gpu_top = {
    source = "${pkgs.intel-gpu-tools}/bin/intel_gpu_top";
    owner = "root"; group = "root";
    capabilities = "cap_perfmon+ep";
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "modesetting" ];

  # Helpful tools / SDKs
  environment.systemPackages = with pkgs; [
    pciutils
    file
    gnumake
    gcc

    # Debug/verify GPU accel
    nvtopPackages.full
    libva-utils            # vainfo, etc.
    intel-gpu-tools        # intel_gpu_top, etc.
    clinfo                 # validate OpenCL
    ocl-icd                # OpenCL ICD loader (libOpenCL.so)
  ];

  users.users.erikp.extraGroups = [ "video" "render" ];

  nixpkgs.config.allowUnfree = true;
}
