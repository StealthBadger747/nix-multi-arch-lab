{
  nix.settings = {
    substituters = [
      "https://nix-cache.zagato.internal.ucaia.com/zagato?priority=7"
    ];
    trusted-public-keys = [
      "zagato:hbCUH7+nZDI40nhwcQhsSYzf2SR4IDVxiexeWnprdq4="
    ];
  };
}
