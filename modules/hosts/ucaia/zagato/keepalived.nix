{ config, pkgs, lib, ... }:
let
  k3sReadyzScript = pkgs.writeShellScriptBin "k3s-readyz-check" ''
    #!/bin/sh
    exec ${pkgs.curl}/bin/curl --silent --fail \
      --cacert /var/lib/rancher/k3s/server/tls/server-ca.crt \
      --cert   /var/lib/rancher/k3s/server/tls/client-admin.crt \
      --key    /var/lib/rancher/k3s/server/tls/client-admin.key \
      https://127.0.0.1:6443/readyz >/dev/null
  '';
in {
  services.keepalived = {
    enable = true;

    extraGlobalDefs = ''
      use_symlink_paths true
      script_user root
      enable_script_security
      max_auto_priority
    '';

    vrrpScripts = {
      chk_apiserver = {
        script   = "${k3sReadyzScript}/bin/k3s-readyz-check";
        interval = 2;
        timeout  = 1;
        rise     = 2;
        fall     = 2;
        user     = "root";
      };
    };

    vrrpInstances = {
      K3S_API = {
        state = "BACKUP";
        interface = "eth0";
        virtualRouterId = 51;
        # priority = 150; # Can be set individually on nodes
        virtualIps = [ { addr = "10.0.20.5/24"; } ];
        trackScripts = [ "chk_apiserver" ];

        # Put keepalived directives not modeled by the module here
        extraConfig = ''
          advert_int 1
          preempt_delay 5
        '';
      };
    };
  };
}
