# NixOS Homelab

A NixOS-based infrastructure configuration for managing multiple cloud and local (on-prem) servers using a declarative approach. This repository contains configurations for various servers running services including Headscale and Authentik.

## Overview

This project uses:
- NixOS for operating system configuration
- Flakes for reproducible builds and dependencies
- SOPS for secrets management
- Deploy-rs for deployment
- Podman for container management

## Infrastructure

### Automated PXE Booting
This repository features automated management of PXE boot assets. The `aspen` host is configured to serve netboot files for K3s workers.
- **Generation**: The [`flake.nix`](file://flake.nix#L234) defines a `k3s-worker-N-netboot-files` package that builds the kernel, initrd, and IPXE scripts.
- **Deployment**: During `aspen`'s activation (see [`services.nix`](file://modules/hosts/ucaia/aspen/services.nix#L65)), these artifacts are automatically built and installed into `/srv/tftp`.
- **Zero-Touch Updates**: Updating the worker image definition in the flake and deploying `aspen` automatically updates the netboot server, ensuring workers always boot the latest configuration.

### Oracle Cloud Infrastructure (OCI) Servers

#### OCI Headscale Server (x86_64)
- Runs Headscale VPN server
- Includes Headplane web UI
- NGINX reverse proxy with SSL
- Dynamic DNS updates via Inadyn
- OIDC authentication integration with Authentik

#### OCI Authentik Server (aarch64)
- Runs Authentik identity management
- Hosts FoundryVTT in Podman container
- NGINX reverse proxy with SSL
- Dynamic DNS updates via Inadyn
- Email notifications configured

### Local Infrastructure

#### Gibraltar
- Local development and testing environment
- Used for testing configurations before deployment

#### Pilatus
- Local server for additional services
- Part of the internal network infrastructure

#### Ucaia
- Additional local server
- Using as a starting point for migrating existing services to NixOS

## Setup Requirements

1. NixOS development environment
2. Oracle Cloud Infrastructure account
3. Age key for secrets encryption
4. Namecheap domain(s) for DNS
5. 1Password CLI (optional, for `sops-age-op` script)

## Getting Started

1. Clone the repository:
```bash
git clone git@github.com:StealthBadger747/nix-homelab.git
cd nix-homelab
```

2. Configure SOPS:
- Add your Age public keys to `.sops.yaml`
- Create necessary secret files using SOPS encryption

3. Update configurations:
- Modify host configurations in `modules/hosts/`
- Update common settings in `modules/configs/common.nix`
- Adjust firewall rules and other security settings as needed

4. Deploy:
- Enter a dev shell with `nix develop` and run:
```bash
deploy .#oci-headscale
deploy .#oci-authentik
# Add other hosts as needed
```

## Directory Structure

```
.
├── flake.nix           # Main flake configuration
├── modules/
│   ├── configs/        # Shared configurations
│   ├── hosts/          # Host-specific configurations
│   │   ├── oracle-cloud/  # OCI server configurations
│   │   ├── gibraltar/     # Offsite servers
│   │   ├── pilatus/       # Local server
│   │   └── ucaia/         # Additional local server
│   └── packages/       # Custom package definitions
├── scripts/            # Utility scripts
├── secrets/           # Encrypted secrets
└── .sops.yaml         # SOPS configuration
```

## Sops Usage

For additional information refer to https://github.com/Mic92/sops-nix

### Adding a target server to your sops config

For example I want to add bugatti server to my sops config:

```nix
$ nix-shell -p ssh-to-age --run 'ssh-keyscan 10.32.4.101 | ssh-to-age
# outputs the key
$ nano .sops.yaml # Add the key to the list and reference it properly
$ sops updatekeys secrets/hosts/gibraltar/bugatti-nix-secrets.yaml # Repeat for all files that are referenced by that key
```
