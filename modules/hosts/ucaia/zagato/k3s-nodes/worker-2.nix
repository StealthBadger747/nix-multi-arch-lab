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

  # Enable cloud-init network configuration
  services.cloud-init.network.enable = true;

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../../../../secrets/hosts/ucaia/zagato/k3s-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "/run/age/age.key";
    age.generateKey = false;
    secrets = {
      k3s-cluster-token = {
        mode = "0400";
        restartUnits = [ "k3s.service" ];
      };
    };
  };

  # inject *only* your Age-key logic; everything else (hostname, SSH keys,
  # filesystem resize, modules, etc.) is handled by the module’s defaults
  services.cloud-init.settings = lib.mkMerge [
    # You can override or extend any of the structured settings here.
    {
      bootcmd = [
        # 1) create the dir on the tmpfs
        "mkdir -p /run/age"

        # 2) pull 'age_key' out of your meta-data snippet
        "sh -c 'cloud-init query -f \"{{ ds.meta_data.age_key }}\" > /run/age/age.key'"
      ];

      runcmd = [
        # 3) lock it down
        "chmod 0400 /run/age/age.key"
      ];
    }
  ];

  # K3s configuration for a worker node
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.sops.secrets.k3s-cluster-token.path;
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
