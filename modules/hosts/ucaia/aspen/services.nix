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
        dhcp-range = "10.0.20.6,10.0.20.254,12h";
        dhcp-authoritative = true;
        dhcp-option = "option:router,10.0.20.1";
        # any PXE / Pixiecore lines here…
      };
    };

    pixiecore = {
      enable       = true;
      openFirewall = true;
      mode         = "boot";
      quick        = "xyz";       # ignored in "boot" mode
      dhcpNoBind   = true;        # leave DHCP to another server
      # listen       = "10.0.20.2";
      # port         = 8080;
      # statusPort   = 9090;
      kernel       = "/srv/tftp/bzImage";
      initrd       = "/srv/tftp/initrd";
      cmdLine      = "init=/init console=ttyS0,115200 netboot=true";
      debug        = true;
    };
  };


}
