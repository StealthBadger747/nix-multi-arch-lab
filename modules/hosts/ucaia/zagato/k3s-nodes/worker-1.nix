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
  hostName = "zagato-worker-01";
in {
  imports = [
    ../default.nix
    ../proxmox-settings.nix
  ];

  proxmox = {
    filenameSuffix = hostName;
    qemuConf = {
      name = hostName;
      net0 = "virtio=D2:A8:F3:12:B9:E4,bridge=vmbr0,firewall=1";
    };
  };

  # Enable cloud-init network configuration
  services.cloud-init.network.enable = true;

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../../../../secrets/hosts/ucaia/zagato/k3s-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    secrets = {
      k3s-cluster-token = {
        mode = "0400";
        restartUnits = [ "k3s.service" ];
      };
    };
  };

  systemd.services.cloud-init = {
    unitConfig = {
      # Don't let cloud-init failure affect other services
      StartLimitBurst = 0;
    };
    serviceConfig = {
      # Make the service succeed even if cloud-init exits with code 1
      SuccessExitStatus = [ 0 1 ];
    };
  };

  # inject *only* your Age-key logic; everything else (hostname, SSH keys,
  # filesystem resize, modules, etc.) is handled by the module’s defaults
  services.cloud-init.settings = lib.mkMerge [
    # You can override or extend any of the structured settings here.
    {
      bootcmd = [
        # 1) create the persistent directory
        "mkdir -p /var/lib/sops-nix"

        # 2) pull 'age_key' out of your meta-data snippet
        "sh -c 'cloud-init query -f \"{{ ds.meta_data.age_key }}\" > /var/lib/sops-nix/key.txt'"
        
        # 3) set proper permissions
        "chmod 600 /var/lib/sops-nix/key.txt"
      ];
    }
  ];

  # Systemd service to ensure cloud-init completes before SOPS services
  systemd.services.sops-key-provision = {
    description = "Wait for cloud-init and provision SOPS keys";
    after = [ "cloud-init.target" ];
    wants = [ "cloud-init.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.cloud-init}/bin/cloud-init status --wait";
      ExecStart = "${pkgs.bash}/bin/bash -c 'while [ ! -f /var/lib/sops-nix/key.txt ]; do sleep 1; done'";
      TimeoutStartSec = 300;
    };
    
    wantedBy = [ "multi-user.target" ];
  };

  # K3s configuration for a worker node
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.sops.secrets.k3s-cluster-token.path;
    serverAddr = "https://10.0.4.201:6443"; # Address of the first server
  };

  # Ensure K3s waits for the key provisioning
  systemd.services.k3s = {
    after = [ "sops-key-provision.service" ];
    wants = [ "sops-key-provision.service" ];
  };

  # Make SOPS secrets depend on the key provisioning service
  systemd.services.sops-install-secrets = {
    after = [ "sops-key-provision.service" ];
    wants = [ "sops-key-provision.service" ];
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
