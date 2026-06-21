{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  hostName = "zagato-worker-01";
in {
  imports = [
    ../default.nix
    ../proxmox-settings.nix
    ../nvidia-headless.nix
  ];

  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=D2:A8:F3:12:B9:E4,bridge=vmbr0,tag=20,firewall=1";
    };
  };

  # Enable cloud-init network configuration
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  # Enable userborn service (triggers useSystemdActivation in sops-nix)
  services.userborn.enable = true;

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../../../../secrets/hosts/ucaia/zagato/k3s-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    secrets = {
      k3s-cluster-token = {
        mode = "0400";
        restartUnits = [ "k3s.service" ];
      };
    };
  };

  # Extract SOPS age key from cloud-init metadata
  systemd.services.sops-extract-key = {
    description = "Extract SOPS age key from cloud-init";
    wantedBy = [ "sysinit.target" ];
    after = [ "cloud-final.service" ];
    wants = [ "cloud-final.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      # Wait for cloud-init to complete all phases.
      ${pkgs.cloud-init}/bin/cloud-init status --wait

      # Refresh the key on every run so a stale key from an image or previous
      # cloud-init configuration cannot survive indefinitely. Write and
      # validate it before atomically replacing the active key.
      ${pkgs.coreutils}/bin/install -d -m 0700 /var/lib/sops-nix
      tmp="$(${pkgs.coreutils}/bin/mktemp /var/lib/sops-nix/key.txt.XXXXXX)"
      trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT

      ${pkgs.cloud-init}/bin/cloud-init query -f "{{ ds.meta_data.age_key }}" > "$tmp"
      ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
      ${pkgs.age}/bin/age-keygen -y "$tmp" > /dev/null
      ${pkgs.coreutils}/bin/mv -f "$tmp" /var/lib/sops-nix/key.txt

      trap - EXIT
      echo "Age key refreshed from cloud-init"
    '';
  };

  # Advertise the NVIDIA RTX A2000 GPU to Kubernetes.
  # Note: these labels mark the node; the nvidia.com/gpu *resource* is only
  # exposed once the NVIDIA k8s-device-plugin DaemonSet is running in the cluster.
  services.k3s.extraFlags = [
    "--node-label=nvidia.com/gpu.present=true"
    "--node-label=nvidia.com/gpu.product=NVIDIA-RTX-A2000"
    "--node-label=nvidia.com/gpu.count=1"
  ];

  # K3s configuration for a worker node
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.sops.secrets.k3s-cluster-token.path;
    serverAddr = "https://10.0.20.11:6443"; # Address of the first server
  };

  # Ensure K3s waits for the key extraction
  systemd.services.k3s = {
    after = [ "sops-extract-key.service" ];
    wants = [ "sops-extract-key.service" ];
  };

  # Make SOPS secrets depend on the key extraction service
  systemd.services.sops-install-secrets = {
    after = [ "sops-extract-key.service" ];
    requires = [ "sops-extract-key.service" ];
  };

  # Open ports needed for K3s worker node
  networking.firewall = {
    allowedTCPPorts = [
      10250   # Kubelet API
    ];
    allowedUDPPorts = [
      8472    # Flannel VXLAN
    ];
  };
}
