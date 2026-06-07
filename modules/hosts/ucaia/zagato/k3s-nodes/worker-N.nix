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
  # Mount the whole k3s agent tree on the dedicated disk so kubelet emptyDir
  # and containerd content share the larger volume instead of the root disk.
  mountPoint = "/var/lib/rancher/k3s/agent";
  mountUnit  = "var-lib-rancher-k3s-agent.mount";
  diskId     = "scsi-0QEMU_QEMU_HARDDISK_CONTAINERD01";
  diskById   = "/dev/disk/by-id/${diskId}";
  devUnit    = "dev-disk-by\\x2did-${lib.replaceStrings ["-"] ["\\x2d"] diskId}.device";
in {
  imports = [
    ../default.nix
  ];

  # Customize the iPXE script to force DHCP and HTTP fetches from Aspen
  system.build.netbootIpxeScript = lib.mkForce (pkgs.writeTextDir "netboot.ipxe" ''
    #!ipxe
    # Use the cmdline variable to allow the user to specify custom kernel params
    # when chainloading this script from other iPXE scripts like netboot.xyz
    dhcp
    set base-url http://10.0.20.2
    kernel ${"$"}{base-url}/bzImage init=${config.system.build.toplevel}/init initrd=${"$"}{base-url}/initrd ${toString config.boot.kernelParams} ''${cmdline}
    initrd ${"$"}{base-url}/initrd
    boot
  '');

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

  # Disable console autologin from netboot-minimal defaults
  services.getty.autologinUser = lib.mkForce null;

  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPassword =
          "$6$518O2ct8O/.dFXC3$oGwdfF4bgrojKTwE7guwAgtwUaoJAHDJ0IQbrNlahFz75cyaD4ZZ8UHtLFDvrK2v74gu/rErHZJ6W9lMSxQVW.";
      };
      kubeadmin = {
        isNormalUser = true;
        group = "users";
        extraGroups = [ "wheel" ];
        description = "Kubernetes Administrator";
        hashedPassword =
          "$6$518O2ct8O/.dFXC3$oGwdfF4bgrojKTwE7guwAgtwUaoJAHDJ0IQbrNlahFz75cyaD4ZZ8UHtLFDvrK2v74gu/rErHZJ6W9lMSxQVW.";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvJ7EXvVEEar9mTg0Yy/hpsRisRtFPyKXHTpMNtigo7"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKOPFxVGGxI4wBUu1SIgWE6Sr7CSBHNZebXDpSHITxC9"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENMEKtS2wB5NlWSAtsoKTss1B0UcD/TeDbMJgVdUKXJ"
        ];
      };
      # Lock the temporary installer account so it cannot be used
      nixos = lib.mkForce {
        isNormalUser = true;
        hashedPassword = "!";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${mountPoint} 0755 root root -"
    "d ${mountPoint}/kubelet 0755 root root -"
    "d /var/lib/kubelet 0755 root root -"
  ];

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

  # CSI plugins mount /var/lib/kubelet in their containers, so keep kubelet state
  # visible there even though the data lives on the containerd disk.
  fileSystems."/var/lib/kubelet" = {
    device = "${mountPoint}/kubelet";
    fsType = "none";
    options = [
      "bind"
      "nofail"
      "x-systemd.after=${mountUnit}"
      "x-systemd.requires-mounts-for=${mountPoint}"
      "x-systemd.mount-timeout=20s"
    ];
  };

  systemd.services.wait-containerd-mount = {
    description = "Wait for containerd mount if disk present";
    wantedBy = [ "multi-user.target" ];
    wants = [ mountUnit ];
    after = [ mountUnit ];
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

  # Create a 2 GiB swap file on the persistent containerd disk. The worker runs
  # with tmpfs root and no swap by default, which causes OOM kills when pods
  # burst memory (e.g., immich machine-learning, ceph-csi). The containerd disk
  # is the only persistent writable space available, so we place the swap file
  # there. It is recreated only if missing or the wrong size.
  systemd.services.create-containerd-swap = {
    description = "Create swap file on containerd disk";
    wantedBy = [ "swap.target" "multi-user.target" ];
    after = [ mountUnit "wait-containerd-mount.service" ];
    requires = [ "wait-containerd-mount.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];
    script = ''
      set -euo pipefail
      SWAP_FILE="${mountPoint}/swapfile"
      SIZE_GIB=2
      SIZE_BYTES=$((SIZE_GIB * 1024 * 1024 * 1024))

      if [ ! -b '${diskById}' ]; then
        echo "No containerd disk present; skipping swap file creation"
        exit 0
      fi

      if [ -f "$SWAP_FILE" ]; then
        CURRENT_SIZE=$(stat -c %s "$SWAP_FILE" 2>/dev/null || echo 0)
        if [ "$CURRENT_SIZE" -eq "$SIZE_BYTES" ]; then
          echo "Swap file already exists with correct size"
          exit 0
        fi
        rm -f "$SWAP_FILE"
      fi

      mkdir -p "$(dirname "$SWAP_FILE")"
      dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((SIZE_GIB * 1024)) status=progress
      chmod 600 "$SWAP_FILE"
      mkswap "$SWAP_FILE"
      swapon "$SWAP_FILE" || true
    '';
  };

  swapDevices = [{
    device = "${mountPoint}/swapfile";
    priority = 10;
    options = [ "nofail" ];
  }];

  # Keep kubelet root-dir at /var/lib/kubelet so CSI staging paths match.
  # Aggressive image GC because the dedicated containerd disk is only 64 GiB
  # and can fill quickly with ML/CSI images; these thresholds keep imagefs
  # below 70% and trigger cleanup as soon as it hits 75%.
  services.k3s.extraFlags = [
    "--kubelet-arg=root-dir=/var/lib/kubelet"
    "--kubelet-arg=image-gc-low-threshold=70"
    "--kubelet-arg=image-gc-high-threshold=75"
    "--kubelet-arg=eviction-hard=imagefs.available<5%,nodefs.available<5%,memory.available<100Mi"
    "--kubelet-arg=eviction-soft=imagefs.available<10%,nodefs.available<10%,memory.available<200Mi"
    "--kubelet-arg=eviction-soft-grace-period=imagefs.available=1m,nodefs.available=1m,memory.available=1m"
    "--kubelet-arg=container-log-max-size=10Mi"
    "--kubelet-arg=container-log-max-files=2"
  ];

  # Limit journald on tmpfs-based netboot workers so logs do not exhaust RAM.
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    MaxFileSec=3day
    MaxRetentionSec=7day
  '';

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
