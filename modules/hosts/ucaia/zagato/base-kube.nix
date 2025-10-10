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

  networking = {
    nameservers = ["10.0.4.12" "10.0.4.13" "1.1.1.1"];
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
