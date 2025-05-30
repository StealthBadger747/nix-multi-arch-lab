{ config, lib, pkgs, ... }:
{
  fileSystems."/export/share-stash" = {
    device = "/BIGBOY/JBOD/stash";
    options = [ "bind" ];
  };

  networking.firewall.allowedTCPPorts = [ 2049 ];

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
   /export/share-stash  10.16.0.30(rw,insecure,no_subtree_check) 100.64.0.20(rw,insecure,no_subtree_check)
  '';
}
