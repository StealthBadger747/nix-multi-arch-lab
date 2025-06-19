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
  hostName = "zagatto-master-01";
in {
  imports = [
    ../default.nix
    ../proxmox-settings.nix
  ];

  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=D8:D9:97:59:39:6A,bridge=vmbr0,firewall=1";
    };
  };

  networking = {
    hostName = hostName;
    interfaces = {
      enp6s18 = {
        ipv4 = {
          addresses = [{
            address = "10.0.4.201";
            prefixLength = 24;
          }];
        };
      };
    };
    defaultGateway = "10.0.4.1";
  };

  # K3s configuration for the first master node
  services.k3s = {
    enable = true;
    role = "server";
    token = "k3s-ucaia-cluster-token"; # Change this to a secure token in a real deployment
    clusterInit = true;
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
