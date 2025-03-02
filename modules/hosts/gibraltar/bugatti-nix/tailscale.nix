{
  config,
  pkgs,
  ...
}: let
  hostname = "bugatti-nix";
  login_server = "https://headscale.parawell.cloud";
in {
  sops = {
    secrets = {
      tailscale-authkey = {
        owner = "root";
        group = "root";
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
