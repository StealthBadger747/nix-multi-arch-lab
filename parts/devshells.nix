{ inputs, mkPkgs, mkPkgsUnstable, ... }:
{
  perSystem = { system, ... }:
    let
      pkgs = mkPkgs system;
      pkgs-unstable = mkPkgsUnstable system;
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = (with pkgs; [
          jq
          age
          sops
          nano
          nh
          bashInteractive
        ]) ++ (with pkgs-unstable; [
          inputs.deploy-rs.packages.${system}.default
        ]);

        shellHook = ''
          echo "OCI CLI version: $(oci --version)"
          echo "Opentofu version: $(tofu version)"
          echo "Available image builders:"
          echo " - nix build .#oci-aarch64-image       # For Oracle Cloud (aarch64)"
          echo " - nix build .#proxmox-x86-linux-image # For Proxmox (x86_64)"

          # Add the script to PATH
          export PATH="$PWD/scripts:$PATH"
          # - 'op://vault/title', 'op://vault/title/field', or 'op://vault/title/section/field'
          export EDITOR=nano
          # alias sops='sops-age-op -k "op://Private/personal_remote_machines/private key" '
          # export SOPS_AGE_KEY="$(op read op://Private/age_key/password)"
        '';
      };
    };
}
