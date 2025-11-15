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
  hostName = "zagato-master-01";
in {
  imports = [
    ../default.nix
    ../proxmox-settings.nix
    ../keepalived.nix
  ];

services.keepalived.vrrpInstances.K3S_API = {
  priority = 152;
};

  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=D8:D9:97:59:39:6A,bridge=vmbr0,tag=20,firewall=1";
    };
  };

  # Enable cloud-init network configuration
  services.cloud-init.network.enable = true;

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../../../../secrets/hosts/ucaia/zagato/k3s-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    secrets = {
      k3s-cluster-token = {
        mode = "0400";
        restartUnits = [ "k3s.service" ];
      };
    };
  };

  # K3s configuration for the first master node
  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets.k3s-cluster-token.path;
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
