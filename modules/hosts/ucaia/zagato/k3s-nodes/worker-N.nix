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

  # # SOPS configuration
  # sops = {
  #   defaultSopsFile = ../../../../../secrets/hosts/ucaia/zagato/k3s-secrets.yaml;
  #   defaultSopsFormat = "yaml";
  #   age.keyFile = "/run/age/age.key";
  #   age.generateKey = false;
  #   secrets = {
  #     k3s-cluster-token = {
  #       mode = "0400";
  #       restartUnits = [ "k3s.service" ];
  #     };
  #   };
  # };

  services.cloud-init.settings = lib.mkMerge [
    # You can override or extend any of the structured settings here.
    {
      bootcmd = [
        # 1) create the dir on the tmpfs
        "mkdir -p /run/k3s"

        # 2) pull 'age_key' out of your meta-data snippet
        "sh -c 'cloud-init query -f \"{{ ds.meta_data.age_key }}\" > /run/k3s/token'"
      ];

      runcmd = [
        # 3) lock it down
        "chmod 0400 /run/k3s/token"
      ];
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
