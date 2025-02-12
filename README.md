# NixOS Homelab

A NixOS-based infrastructure configuration for managing multiple cloud servers using a declarative approach. This repository contains configurations for Oracle Cloud Infrastructure (OCI) instances running various services including Headscale, Authentik, and FoundryVTT.

## Overview

This project uses:
- NixOS for operating system configuration
- Flakes for reproducible builds and dependencies
- SOPS for secrets management
- Deploy-rs for deployment
- Podman for container management

## Infrastructure

### OCI Headscale Server (x86_64)
- Runs Headscale VPN server
- Includes Headplane web UI
- NGINX reverse proxy with SSL
- Dynamic DNS updates via Inadyn
- OIDC authentication integration with Authentik

### OCI Authentik Server (aarch64)
- Runs Authentik identity management
- Hosts FoundryVTT in Podman container
- NGINX reverse proxy with SSL
- Dynamic DNS updates via Inadyn
- Email notifications configured

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
```bash
deploy .#oci-headscale
deploy .#oci-authentik
```

## Directory Structure

```
.
├── flake.nix           # Main flake configuration
├── modules/
│   ├── configs/        # Shared configurations
│   ├── hosts/          # Host-specific configurations
│   └── packages/       # Custom package definitions
├── scripts/            # Utility scripts
├── secrets/           # Encrypted secrets
└── .sops.yaml         # SOPS configuration
```

## Features

### Security
- SSH key-based authentication only
- Firewall enabled by default
- HTTPS with automatic certificate management
- Secrets management using SOPS
- No password authentication allowed

### Networking
- Tailscale/Headscale VPN integration
- Dynamic DNS updates
- NGINX reverse proxy
- Cloudflare DNS integration

### Services
- Headscale VPN server with web UI
- Authentik identity provider
- FoundryVTT game server
- Container management with Podman
