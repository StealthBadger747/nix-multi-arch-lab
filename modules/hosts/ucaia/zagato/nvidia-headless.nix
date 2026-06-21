{ config, lib, pkgs, ... }:
{

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  # NVIDIA + Containers (generates CDI specs for Docker/Podman)
  hardware.nvidia-container-toolkit.enable = true;

  # CUDA and tools needed by k3s's bundled containerd to find the NVIDIA runtime.
  environment.systemPackages = with pkgs; [
    pciutils
    file

    gnumake
    gcc

    cudaPackages.cudatoolkit

    nvidia-container-toolkit
    runc
  ];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    #
    # Kept on proprietary for this headless compute node: the open modules are
    # officially recommended for Ampere, but there are still intermittent
    # nvidia-uvm / CUDA initialization issues reported on NixOS (e.g.
    # nixpkgs#334180). Proprietary remains the safer default for server/CUDA
    # workloads until that stabilizes.
    open = false;

    # Keep the GPU awake in headless mode (replaces the old nvidia-smi hack).
    nvidiaPersistenced = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # k3s bundles its own containerd; the nvidia-container-toolkit module only
  # configures Docker/Podman. We must register the nvidia runtime explicitly
  # with k3s's containerd. k3s 1.31.6+ uses containerd 2.0 / config version 3.
  systemd.services.k3s-nvidia-containerd-setup = {
    description = "Configure k3s containerd for NVIDIA runtime";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    requiredBy = ["k3s.service"];
    before = ["k3s.service"];
    script = ''
      mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
      cat <<'EOF' > /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl
{{ template "base" . }}

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  privileged_without_host_devices = false

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nvidia.options]
  BinaryName = "${lib.getExe' pkgs.nvidia-container-toolkit "nvidia-container-runtime"}"
  SystemdCgroup = true
EOF
    '';
  };

}
