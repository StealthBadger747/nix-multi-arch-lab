{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: {

  # Required for Rook/Ceph
  boot.kernelModules = [ "rbd" ];

  # Required for Longhorn
  environment.systemPackages = [ pkgs.nfs-utils ];
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };

  # Disable the iscsid.socket unit to prevent conflicts with iscsid.service.
  # The openiscsi module in NixOS enables the service at boot (wantedBy=multi-user.target).
  # If the socket unit is also active, systemd may fail to start the service with:
  # "Socket service iscsid.service already active, refusing".
  # Disabling the socket lets the service manage itself directly.
  systemd.sockets.iscsid.enable = false;

  services.k3s.package = pkgs.k3s_1_36;

  # Limit journald disk usage to prevent root disk fill-up on 30GB master nodes.
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxFileSec=7day
    MaxRetentionSec=30day
  '';

  # Auto-cleanup disk space on k3s nodes so alerts don't wake anyone up.
  systemd.services.k3s-disk-cleanup = {
    description = "Clean up k3s/containerd disk cruft";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "k3s-disk-cleanup";
        runtimeInputs = with pkgs; [ coreutils gawk nix ];
        text = ''
          set -euo pipefail

          K3S_DATA_DIR="/var/lib/rancher/k3s/data"
          CONTAINERD_SOCK="/run/k3s/containerd/containerd.sock"

          log() {
            echo "[k3s-disk-cleanup] $*"
          }

          log "Starting cleanup on $(hostname) at $(date -Iseconds)"

          # Remove old k3s data directories, keeping the ones referenced by
          # 'current' and 'previous' symlinks.
          if [ -d "$K3S_DATA_DIR" ]; then
            CURRENT=$(readlink -f "$K3S_DATA_DIR/current" 2>/dev/null || true)
            PREVIOUS=$(readlink -f "$K3S_DATA_DIR/previous" 2>/dev/null || true)

            for dir in "$K3S_DATA_DIR"/*; do
              [ -d "$dir" ] || continue
              realdir=$(readlink -f "$dir")
              case "$realdir" in
                "$CURRENT"|"$PREVIOUS"|"$K3S_DATA_DIR/cni")
                  log "Keeping $dir"
                  continue
                  ;;
              esac
              log "Removing old k3s data dir: $dir"
              rm -rf "$dir"
            done
          fi

          # Prune unused containerd images via the k3s-bundled crictl.
          if [ -S "$CONTAINERD_SOCK" ] && [ -x "$K3S_DATA_DIR/current/bin/crictl" ]; then
            log "Pruning unused containerd images"
            "$K3S_DATA_DIR/current/bin/crictl" --runtime-endpoint "unix://$CONTAINERD_SOCK" rmi --prune || true
          else
            log "Containerd socket or crictl not available, skipping image prune"
          fi

          # If root is getting full, run an extra nix GC beyond the weekly timer.
          USAGE=$(df -P / | awk 'NR==2 {print $5}' | tr -d '%')
          if [ -n "$USAGE" ] && [ "$USAGE" -gt 75 ]; then
            log "Root disk usage is ''${USAGE}%, running nix-collect-garbage"
            nix-collect-garbage --delete-older-than 7d || true
          fi

          log "Cleanup completed at $(date -Iseconds)"
        '';
      });
    };
  };

  systemd.timers.k3s-disk-cleanup = {
    description = "Run k3s disk cleanup daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "4h";
      Persistent = true;
    };
  };

  networking = {
    nameservers = ["10.0.4.13" "1.1.1.1"];
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22      # SSH
        80      # HTTP
        443     # HTTPS
        6443    # Kubernetes API server
        2379    # etcd client API
        2380    # etcd peer API
        9100    # Prometheus node-exporter
        10250   # Kubelet API
        # Longhorn ports
        9500    # Longhorn Manager
        8000    # Longhorn Engine
      ];
      allowedUDPPorts = [
        8472    # Flannel VXLAN
      ];
      # vrrp is keepalived related
      extraInputRules = ''
        ip  protocol vrrp accept
        ip6 nexthdr   vrrp accept
        iifname "eth0" ip  protocol vrrp accept
        iifname "eth0" ip6 nexthdr   vrrp accept
      '';
    };
  };
}
