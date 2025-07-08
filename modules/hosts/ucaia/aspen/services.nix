{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  pkgs-unstable,
  ...
}: {
  services = {
    dnsmasq = {
      enable = true;
      settings = {
        interface = "eth0";

        # Disable DNS server (port 53) - only do DHCP/TFTP
        port = 0;
        
        # DHCP configuration
        dhcp-range = "10.0.20.20,10.0.20.254,12h";
        dhcp-authoritative = true;

        # TFTP configuration
        enable-tftp = true;
        tftp-root = "/srv/tftp";
        tftp-secure = true;
        
        # PXE boot options
        # Option 66: TFTP server name
        dhcp-option = [
          "option:router,10.0.20.1"
          "option:dns-server,10.0.20.1"
          "option:tftp-server,10.0.20.1"
        ];
        
        # PXE boot filename (option 67)
        dhcp-boot = "boot.ipxe";
        
        # Alternative: More specific PXE configuration
        # You can also use conditional booting based on client architecture
        # dhcp-match = "set:bios,option:client-arch,0";
        # dhcp-match = "set:efi32,option:client-arch,6";
        # dhcp-match = "set:efi64,option:client-arch,7";
        # dhcp-match = "set:efi64,option:client-arch,9";
        # dhcp-boot = [
        #   "tag:bios,pxelinux.0"
        #   "tag:efi32,bootia32.efi"
        #   "tag:efi64,bootx64.efi"
        # ];
      };
    };

    pixiecore = {
      enable       = true;
      openFirewall = true;
      mode         = "boot";
      dhcpNoBind   = true;
      kernel       = "/srv/tftp/bzImage";
      initrd       = "/srv/tftp/initrd";
      cmdLine      = "init=/init console=ttyS0,115200 netboot=true";
      debug        = true;
    };
  };

  # Ensure TFTP directory exists and has proper permissions
  system.activationScripts.tftp-setup = ''
    mkdir -p /srv/tftp
    chmod 755 /srv/tftp
    chown -R dnsmasq:dnsmasq /srv/tftp
  '';

  # Open firewall ports for TFTP and DHCP
  networking.firewall = {
    allowedUDPPorts = [ 
      67   # DHCP
      68   # DHCP
      69   # TFTP
      4011 # PXE
    ];
  };
}
