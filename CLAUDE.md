# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Kubernetes home operations repository using Talos Linux as the OS, Flux for GitOps, and a declarative infrastructure approach. The cluster runs on 3 bare-metal nodes in a home lab environment.

**Template Source**: This repository is based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template), a opinionated template for deploying a Talos Kubernetes cluster with integrated GitOps via Flux.

**Reference Implementation**: For examples and patterns, see [onedr0p/home-ops](https://github.com/onedr0p/home-ops), which demonstrates a production implementation of this template.
- A local clone is available at `../onedr0p-home-ops` for quick reference when implementing new applications or troubleshooting patterns
- Particularly useful for HelmRelease configurations, app-template usage patterns, and networking setups

## Key Technologies

- **Talos Linux**: Immutable Kubernetes OS running on bare-metal nodes
- **Flux CD**: GitOps operator for managing cluster state
- **Cilium**: CNI and network policy enforcement
- **SOPS + Age**: Secret encryption for Git
- **Helmfile**: Bootstrap Helm releases before Flux takes over
- **Task**: Task runner (Taskfile.yaml)
- **mise**: Development tool version management

## Repository Structure

- `talos/`: Talos Linux configuration
  - `talconfig.yaml`: Main Talos cluster configuration
  - `talenv.yaml`: Talos and Kubernetes versions
  - `patches/`: Node-specific and global Talos patches
  - `clusterconfig/`: Generated Talos configs (not committed)
- `kubernetes/`: Kubernetes manifests
  - `apps/`: Application deployments organized by namespace
  - `bootstrap/`: Initial Helm releases (Cilium, CoreDNS, Cert-Manager, Flux)
  - `flux/`: Flux Kustomizations and configurations
  - `components/`: Shared components and secrets
- `scripts/`: Bootstrap and helper scripts
- `.taskfiles/`: Task definitions for common operations
- `config.yaml`: Cluster configuration (nodes, networking, Cloudflare)

## Common Commands

### Cluster Management

```bash
# Force Flux to reconcile from Git
task reconcile

# Generate Talos configuration from talconfig.yaml
task talos:generate-config

# Apply Talos config to a specific node
task talos:apply-node IP=192.168.42.33

# Upgrade Talos on a node
task talos:upgrade-node IP=192.168.42.33

# Upgrade Kubernetes version
task talos:upgrade-k8s

# Bootstrap Talos cluster (initial setup)
task bootstrap:talos

# Bootstrap apps into cluster (after Talos is running)
task bootstrap:apps
```

### Development Workflow

```bash
# List all available tasks
task --list

# Install development tools (installs kubectl, flux, talosctl, etc.)
mise install

# Validate Kubernetes manifests
kubeconform kubernetes/

# Decrypt SOPS secret
sops -d path/to/file.sops.yaml

# Encrypt a file with SOPS
sops -e file.yaml > file.sops.yaml

# Reset cluster nodes to maintenance mode (destructive)
task talos:reset
```

### Accessing the Cluster

- Kubeconfig: `./kubeconfig`
- Talosconfig: `./talos/clusterconfig/talosconfig`
- Environment variables are automatically set by mise (see `.mise.toml`)
- All tools (kubectl, flux, talosctl, etc.) are managed by mise via aqua

## Architecture Patterns

### Application Deployment

Applications are deployed using a two-tier Flux Kustomization structure:

```
kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml                    # Flux Kustomization (namespace-level, points to app/)
└── app/
    ├── helmrelease.yaml       # Flux HelmRelease resource
    ├── kustomization.yaml     # Kustomize file (lists resources)
    ├── externalsecret.yaml    # External Secrets (optional)
    └── pvc.yaml               # Storage claims (optional)
```

The namespace-level `ks.yaml` references the `app/` directory and enables SOPS decryption and variable substitution. Most applications use the `bjw-s/app-template` Helm chart for standardization.

### HelmRelease Pattern

Applications reference Helm charts using `chartRef` with `OCIRepository` kind for OCI-based charts, or `chart` field for traditional Helm repositories. The bjw-s app-template is commonly used via OCI:

```yaml
chartRef:
  kind: OCIRepository
  name: app-template
```

### Secret Management

- Secrets are encrypted with SOPS using Age encryption
- Pattern: `*.sops.yaml` files throughout the repository
- Age public key is in `config.yaml`
- Age private key is in `age.key` (not committed)
- SOPS rules in `.sops.yaml` define encryption patterns
- Common secrets: `kubernetes/components/common/sops/cluster-secrets.sops.yaml`
- Flux decrypts secrets automatically using the `sops-age` secret

### Networking

- Cilium provides CNI with kube-proxy replacement
- L2 announcements for LoadBalancer services (no external load balancer needed)
- VIP addresses allocated from node network (192.168.42.0/24)
- Gateway API used for ingress routing (Envoy)
- Internal and external ingress classes with separate VIPs

### Bootstrap Process

1. Talos is bootstrapped first using `task bootstrap:talos`
   - Generates machine configs from `talconfig.yaml`
   - Applies configs to nodes
   - Bootstraps etcd on first controller
   - Generates kubeconfig
2. Apps are bootstrapped using `task bootstrap:apps` (via `scripts/bootstrap-apps.sh`)
   - Creates namespaces for each directory in `kubernetes/apps/`
   - Applies SOPS secrets (GitHub deploy key, cluster secrets, age key)
   - Applies CRDs (external-dns, gateway-api, prometheus-operator)
   - Runs helmfile (`kubernetes/bootstrap/helmfile.yaml`) to install in order:
     - Cilium → CoreDNS → Cert-Manager → Flux Operator → Flux Instance
3. Flux takes over and syncs from Git repository
   - `cluster-meta` Kustomization applies Helm/OCI repositories
   - `cluster-apps` Kustomization deploys all applications

## Important Configuration Files

- `config.yaml`: Central configuration for cluster setup (node IPs, VIPs, domain, Cloudflare)
- `talconfig.yaml`: Talos cluster configuration
- `talenv.yaml`: Talos and Kubernetes versions for upgrades
- `.renovaterc.json5`: Renovate bot configuration for automated updates
  - Auto-merges patch updates for Docker, Helm, GitHub releases, and Actions
  - Custom regex managers for annotated dependencies in YAML
  - Groups related packages (Talos, Flux, Cert-Manager, etc.)

## Talos Configuration

The cluster uses `talhelper` to template Talos configurations. Key points:

- 3 controller nodes (no separate worker nodes): k8s-bee-s1, k8s-bee-s2, k8s-min-s3
- Static IP addressing (192.168.42.33-35) with VIP for kube-apiserver (192.168.42.32)
- Cilium CNI (Flannel disabled via `cniConfig.name: none`)
- Global patches applied to all nodes (in `talos/patches/`)
- Per-node patches for disk configuration (in `talos/patches/<node-name>/`)
- Machine configs generated from `talconfig.yaml` + `talenv.yaml`
- Talos and Kubernetes versions are managed in `talenv.yaml` (renovate-tracked)
- Factory images from factory.talos.dev with custom schematics per node

## Flux Configuration

Flux is deployed via Flux Operator and manages:

- Helm repositories and OCI repositories (`kubernetes/flux/meta/repos/`)
- All application deployments (`kubernetes/apps/`)
- Two main Kustomizations:
  - `cluster-meta`: Flux repositories and infrastructure
  - `cluster-apps`: All applications with SOPS decryption enabled

## Renovate Integration

Renovate automatically updates:

- Docker container images in HelmReleases
- Helm chart versions
- GitHub Actions
- GitHub releases
- Custom regex-based dependencies (annotated with `# renovate:` comments)

Updates are semantic-committed with version changes in commit messages.

## When Working on This Repository

- **Secrets**: Never commit unencrypted secrets. Use SOPS: `sops -e file.yaml > file.sops.yaml`
- **SOPS rules**: Files matching patterns in `.sops.yaml` are auto-encrypted (talos and kubernetes dirs)
- **App structure**: Follow the two-tier structure (namespace `ks.yaml` + `app/` directory) when adding applications
- **Flux sync**: Use `task reconcile` to force Flux to pull Git changes immediately
- **IP ranges**:
  - Nodes: 192.168.42.33-35
  - Kube API VIP: 192.168.42.32
  - Internal ingress: 192.168.42.80
  - External ingress: 192.168.42.81
  - k8s_gateway: 192.168.42.67
  - Service LoadBalancers use Cilium L2 announcements from node network
- **Talos changes**: Always run `task talos:generate-config` to validate before applying
- **Renovate**: Annotate dependencies with `# renovate:` comments for automatic updates
- **HelmRelease pattern**: Use `chartRef` with `OCIRepository` kind for OCI charts, `chart` field for traditional Helm repos
