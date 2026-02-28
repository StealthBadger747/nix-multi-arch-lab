{ self, inputs, ... }:
{
  flake.deploy.nodes = {
    oci-authentik = {
      hostname = "150.136.213.118";
      sshUser = "erikp";
      fastConnection = true;
      autoRollback = false;
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."aarch64-linux".activate.nixos
          self.nixosConfigurations.oci-authentik;
        magicRollback = true;
        remoteBuild = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    oci-headscale = {
      hostname = "129.153.154.190";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.oci-headscale;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    pc24-proxmox = {
      hostname = "100.64.0.46";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.pc24-proxmox;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    gib-bugatti = {
      hostname = "100.64.0.28";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.bugatti-proxmox-nix;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    giulia = {
      hostname = "10.0.4.33";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.giulia-proxmox;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    aspen = {
      hostname = "10.0.20.2";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.aspen-proxmox;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    zagato-master-01 = {
      hostname = "10.0.20.11";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.k3s-master-1;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    zagato-master-02 = {
      hostname = "10.0.20.12";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.k3s-master-2;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    zagato-master-03 = {
      hostname = "10.0.20.13";
      sshUser = "erikp";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
          self.nixosConfigurations.k3s-master-3;
        magicRollback = true;
        sshOpts = [
          "-o" "StrictHostKeyChecking=no"
          "-o" "UserKnownHostsFile=/dev/null"
        ];
      };
    };

    # zagato-worker-01 = {
    #   hostname = "10.0.4.214";
    #   sshUser = "erikp";
    #   profiles.system = {
    #     user = "root";
    #     path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
    #       self.nixosConfigurations.k3s-worker-1;
    #     magicRollback = false;
    #     sshOpts = [
    #       "-o" "StrictHostKeyChecking=no"
    #       "-o" "UserKnownHostsFile=/dev/null"
    #     ];
    #   };
    # };

    # zagato-worker-02 = {
    #   hostname = "10.0.20.15";
    #   sshUser = "erikp";
    #   profiles.system = {
    #     user = "root";
    #     path = inputs.deploy-rs.lib."x86_64-linux".activate.nixos
    #       self.nixosConfigurations.k3s-worker-2;
    #     magicRollback = false;
    #     sshOpts = [
    #       "-o" "StrictHostKeyChecking=no"
    #       "-o" "UserKnownHostsFile=/dev/null"
    #     ];
    #   };
    # };
  };
}
