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
  fsLabel    = "containerd";
  mountPoint = "/var/lib/rancher/k3s/agent/containerd";
  diskById   = "/dev/disk/by-id/scsi-QEMU_QEMU_HARDDISK_CONTAINERD01";
  devUnit    = "dev-disk-by\\x2did-scsi\\x2dQEMU_QEMU_HARDDISK_CONTAINERD01.device";
in {
  imports = [
    ../default.nix
  ];

  # Cloud init and proxmox integration
  networking.useNetworkd = true;
  services = {
    cloud-init = {
      enable = true;
      network.enable = true;
    };
    sshd.enable = true;
    qemuGuest.enable = true;
  };

  # Disable the static hostname generation
  networking.hostName = lib.mkForce "";

  systemd.tmpfiles.rules = [ "d ${mountPoint} 0755 root root -" ];

  systemd.services.mkfs-containerd = {
    description = "Format containerd disk (ephemeral)";
    wants     = [ devUnit ];
    after     = [ devUnit ];
    wantedBy  = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.e2fsprogs pkgs.util-linux pkgs.coreutils ];
    script = ''
      set -euo pipefail
      DISK='${diskById}'
      if [ ! -b "$DISK" ]; then
        echo "mkfs-containerd: $DISK not present; skipping."
        exit 0
      fi
      mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1,nodiscard -L ${fsLabel} "$DISK"
    '';
  };

  systemd.mounts = [
    {
      what    = "LABEL=${fsLabel}";
      where   = mountPoint;
      type    = "ext4";
      options = "noatime,x-systemd.device-timeout=5s,nofail";
      requires = [ "mkfs-containerd.service" ];
      after    = [ "mkfs-containerd.service" devUnit ];
      unitConfig.JobTimeoutSec = "20s";
    }
  ];

  systemd.services.wait-containerd-mount = {
    description = "Wait for containerd mount if disk present";
    wantedBy = [ "multi-user.target" ];
    wants = [ "var-lib-rancher-k3s-agent-containerd.mount" ];
    after = [ "var-lib-rancher-k3s-agent-containerd.mount" ];
    serviceConfig = { 
      Type = "oneshot"; 
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux ];
    script = ''
      set -euo pipefail
      if [ ! -b '${diskById}' ]; then
        echo "No containerd disk present, continuing without mount"
        exit 0
      fi
      
      for i in {1..20}; do
        if mountpoint -q '${mountPoint}'; then
          echo "Containerd mount ready"
          exit 0
        fi
        sleep 1
      done
      
      echo "Containerd disk present but mount failed" >&2
      exit 1
    '';
  };

  systemd.services.k3s.wants = [ "wait-containerd-mount.service" ];
  systemd.services.k3s.after = [ "wait-containerd-mount.service" ];

  services.cloud-init.settings = lib.mkMerge [
    # You can override or extend any of the structured settings here.
    {
      bootcmd = [
        # 1) create the dir on the tmpfs
        "mkdir -p /run/k3s"

        # 2) pull 'age_key' out of your meta-data snippet
        "sh -c 'cloud-init query -f \"{{ ds.meta_data.k3s_token }}\" > /run/k3s/token'"
      ];

      runcmd = [
        # 3) lock it down
        "chmod 0400 /run/k3s/token"
      ];

      # Let cloud-init manage hostname
      preserve_hostname = false;
    }
  ];

  # K3s configuration for a worker node
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = "/run/k3s/token";
    serverAddr = "https://10.0.20.11:6443"; # Address of the first server
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
