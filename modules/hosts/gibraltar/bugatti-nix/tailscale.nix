{
  config,
  pkgs,
  ...
}: let
  hostname = "bugatti-nix";
  login_server = "https://headscale.parawell.cloud";
in {
  sops = {
    defaultSopsFile = ../../../../secrets/hosts/gibraltar/bugatti-nix-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    secrets = {
      tailscale-authkey = {
        owner = "tailscale";
        group = "tailscale";
        mode = "0400";
      };
    };
  };

  environment.systemPackages = with pkgs; [tailscale];

  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = [
      "--accept-routes=false"
      "--hostname=${hostname}"
      "--login-server=${login_server}"
    ];
    authKeyFile = config.sops.secrets.tailscale-authkey.path;
  };
}
