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

  # Enable userborn service (triggers useSystemdActivation in sops-nix)
  services.userborn.enable = true;

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

  # Extract SOPS age key from cloud-init metadata
  systemd.services.sops-extract-key = {
    description = "Extract SOPS age key from cloud-init";
    wantedBy = [ "sysinit.target" ];
    after = [ "cloud-final.service" ];
    wants = [ "cloud-final.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      # Wait for cloud-init to complete all phases
      ${pkgs.cloud-init}/bin/cloud-init status --wait
      
      if [ ! -f /var/lib/sops-nix/key.txt ]; then
        mkdir -p /var/lib/sops-nix
        ${pkgs.cloud-init}/bin/cloud-init query -f "{{ ds.meta_data.age_key }}" > /var/lib/sops-nix/key.txt
        chmod 600 /var/lib/sops-nix/key.txt
        echo "Age key extracted from cloud-init"
      fi
    '';
  };

  # K3s configuration for a worker node
  services.k3s = {
    enable = true;
    role = "agent";
    tokenFile = config.sops.secrets.k3s-cluster-token.path;
    serverAddr = "https://10.0.4.201:6443"; # Address of the first server
  };

  # Ensure K3s waits for the key extraction
  systemd.services.k3s = {
    after = [ "sops-extract-key.service" ];
    wants = [ "sops-extract-key.service" ];
  };

  # Make SOPS secrets depend on the key extraction service
  systemd.services.sops-install-secrets = {
    after = [ "sops-extract-key.service" ];
    requires = [ "sops-extract-key.service" ];
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
