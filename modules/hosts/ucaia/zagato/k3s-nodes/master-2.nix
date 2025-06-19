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
  hostName = "zagatto-master-02";
in {
  imports = [
    ../default.nix
    ../proxmox-settings.nix
  ];

  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=B4:03:04:16:43:CB,bridge=vmbr0,firewall=1";
    };
  };

  networking = {
    hostName = hostName;
    interfaces = {
      enp6s18 = {
        ipv4 = {
          addresses = [{
            address = "10.0.4.202";
            prefixLength = 24;
          }];
        };
      };
    };
    defaultGateway = "10.0.4.1";
  };

  # K3s configuration for the second server node
  services.k3s = {
    enable = true;
    role = "server";
    token = "k3s-ucaia-cluster-token"; # Must match token from kube-master-1
    serverAddr = "https://10.0.4.201:6443"; # Address of the first server
  };

  # Open ports needed for K3s
  networking.firewall = {
    allowedTCPPorts = [
      6443    # Kubernetes API server
      2379    # etcd client API
      2380    # etcd peer API
      10250   # Kubelet API
    ];
    allowedUDPPorts = [
      8472    # Flannel VXLAN
    ];
  };
}
