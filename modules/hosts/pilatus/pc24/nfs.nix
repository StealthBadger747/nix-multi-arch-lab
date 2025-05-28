{ config, lib, pkgs, ... }:
{
  fileSystems."/export/share-stash" = {
    device = "/BIGBOY/stash";
    options = [ "bind" ];
  };

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /export/share-stash  10.16.0.30(rw,insecure,no_subtree_check)
  '';
}
