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
  hostName = "zagato-worker-02";
in {
  imports = [
    ../default.nix
    ../proxmox-settings.nix
  ];

  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=E5:F8:1A:3D:65:B7,bridge=vmbr0,firewall=1";
    };
  };

  networking = {
    hostName = hostName;
    interfaces = {
      ens18 = {
        ipv4 = {
          addresses = [{
            address = "10.0.4.212";
            prefixLength = 24;
          }];
        };
      };
    };
    defaultGateway = "10.0.4.1";
  };

  # K3s configuration for a worker node
  services.k3s = {
    enable = true;
    role = "agent";
    token = "k3s-ucaia-cluster-token"; # Must match token from master nodes
    serverAddr = "https://10.0.4.201:6443"; # Address of the first server
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
