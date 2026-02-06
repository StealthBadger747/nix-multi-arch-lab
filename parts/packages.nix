{ self, mkPkgs, ... }:
{
  perSystem = { system, ... }:
    let
      pkgs = mkPkgs system;
      configs = self.nixosConfigurations;
      mkSystemImage = { name, expectedSystem, config, buildAttr }:
        if system == expectedSystem
        then config.config.system.build.${buildAttr}
        else pkgs.runCommand name { } ''
          echo "This package can only be built on ${expectedSystem} systems"
          exit 1
        '';
    in {
      packages = {
        oci-aarch64-image = mkSystemImage {
          name = "oci-aarch64-image";
          expectedSystem = "aarch64-linux";
          config = configs.oci-aarch64-base;
          buildAttr = "OCIImage";
        };

        proxmox-x86-linux-image = mkSystemImage {
          name = "proxmox-x86-linux-image";
          expectedSystem = "x86_64-linux";
          config = configs.proxmox-base;
          buildAttr = "VMA";
        };

        pc24-proxmox-image = mkSystemImage {
          name = "pc24-proxmox-image";
          expectedSystem = "x86_64-linux";
          config = configs.pc24-proxmox;
          buildAttr = "VMA";
        };

        zagato-proxmox-image = mkSystemImage {
          name = "zagato-proxmox-image";
          expectedSystem = "x86_64-linux";
          config = configs.zagato-proxmox;
          buildAttr = "VMA";
        };

        giulia-proxmox-image = mkSystemImage {
          name = "giulia-proxmox-image";
          expectedSystem = "x86_64-linux";
          config = configs.giulia-proxmox;
          buildAttr = "VMA";
        };

        aspen-proxmox-image = mkSystemImage {
          name = "aspen-proxmox-image";
          expectedSystem = "x86_64-linux";
          config = configs.aspen-proxmox;
          buildAttr = "VMA";
        };

        k3s-master-1-image = mkSystemImage {
          name = "k3s-master-1-image";
          expectedSystem = "x86_64-linux";
          config = configs.k3s-master-1;
          buildAttr = "VMA";
        };

        k3s-master-2-image = mkSystemImage {
          name = "k3s-master-2-image";
          expectedSystem = "x86_64-linux";
          config = configs.k3s-master-2;
          buildAttr = "VMA";
        };

        k3s-master-3-image = mkSystemImage {
          name = "k3s-master-3-image";
          expectedSystem = "x86_64-linux";
          config = configs.k3s-master-3;
          buildAttr = "VMA";
        };

        k3s-worker-1-image = mkSystemImage {
          name = "k3s-worker-1-image";
          expectedSystem = "x86_64-linux";
          config = configs.k3s-worker-1;
          buildAttr = "VMA";
        };

        k3s-worker-2-image = mkSystemImage {
          name = "k3s-worker-2-image";
          expectedSystem = "x86_64-linux";
          config = configs.k3s-worker-2;
          buildAttr = "VMA";
        };

        k3s-worker-N-netboot-image = mkSystemImage {
          name = "k3s-worker-N-netboot-image";
          expectedSystem = "x86_64-linux";
          config = configs.k3s-worker-N;
          buildAttr = "netbootIpxeScript";
        };

        k3s-worker-N-netboot-files =
          if system == "x86_64-linux"
          then pkgs.runCommand "k3s-worker-N-netboot-files" { } ''
            mkdir -p $out
            cp ${configs.k3s-worker-N.config.system.build.kernel}/bzImage $out/bzImage
            cp ${configs.k3s-worker-N.config.system.build.netbootRamdisk}/initrd $out/initrd
            cp ${configs.k3s-worker-N.config.system.build.netbootIpxeScript}/netboot.ipxe $out/netboot.ipxe
          ''
          else pkgs.runCommand "k3s-worker-N-netboot-files" { } ''
            echo "This package can only be built on x86_64-linux systems"
            exit 1
          '';
      };
    };
}
