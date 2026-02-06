{ inputs, ... }:
let
  supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

  mkPkgsFrom = nixpkgsInput: system:
    import nixpkgsInput {
      inherit system;
      config.allowUnfree = true;
      crossSystem = if system == "aarch64-linux" then {
        config = "aarch64-unknown-linux-gnu";
        system = "aarch64-linux";
      } else null;
    };

  mkPkgs = system: mkPkgsFrom inputs.nixpkgs system;

  mkPkgsUnstable = system: mkPkgsFrom inputs.nixpkgs-unstable system;
in {
  systems = supportedSystems;

  _module.args = {
    inherit supportedSystems mkPkgs mkPkgsUnstable mkPkgsFrom;
  };
}
