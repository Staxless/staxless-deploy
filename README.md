<div align="center">

# Staxless Deploy

**Deploy Simple. Scale Smarter.**

[![License](https://img.shields.io/badge/license-proprietary-8B7EC8?style=flat-square)](https://staxless.com)
[![GitHub Actions](https://img.shields.io/badge/github_actions-reusable-2088FF?style=flat-square)](https://docs.github.com/en/actions)
[![Terraform](https://img.shields.io/badge/terraform-required-7B42BC?style=flat-square)](https://terraform.io)

Reusable GitHub Actions workflows for deploying Staxless applications to Docker Swarm clusters.

</div>

---

## Features

- **One-Command Deploy** - Full infrastructure provisioning + service deployment
- **Rolling Updates** - Zero-downtime updates with automatic rollback
- **Multi-Cloud Ready** - DigitalOcean today, AWS tomorrow
- **Docker Swarm** - Production cluster with manager/worker topology
- **Secret Management** - Secure Docker secrets via SSH, no plaintext
- **Health Checks** - Automated replica verification after every deploy

---

## Quick Start

Add this to your repo as `.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  workflow_dispatch:
    inputs:
      action:
        type: choice
        options: [update-services, initial-deploy, add-service, destroy]
      services:
        type: string
        default: 'all'
      service_name:
        type: string
        default: ''
      confirm_destroy:
        type: string
        default: ''

jobs:
  update:
    if: inputs.action == 'update-services'
    uses: staxless/staxless-deploy/.github/workflows/update-services.yml@v1
    with:
      services: ${{ inputs.services }}
    secrets: inherit

  initial:
    if: inputs.action == 'initial-deploy'
    uses: staxless/staxless-deploy/.github/workflows/initial-deploy.yml@v1
    with:
      domain: yourdomain.com
    secrets: inherit

  add:
    if: inputs.action == 'add-service'
    uses: staxless/staxless-deploy/.github/workflows/add-service.yml@v1
    with:
      service_name: ${{ inputs.service_name }}
    secrets: inherit

  destroy:
    if: inputs.action == 'destroy'
    uses: staxless/staxless-deploy/.github/workflows/destroy.yml@v1
    with:
      confirm: ${{ inputs.confirm_destroy }}
    secrets: inherit
```

---

## Workflows

| Workflow | Description |
|----------|-------------|
| `initial-deploy.yml` | Full infrastructure provisioning + service deployment |
| `update-services.yml` | Rolling updates with automatic rollback |
| `add-service.yml` | Deploy a new service to an existing stack |
| `destroy.yml` | Graceful shutdown + infrastructure teardown |

---

## Required Secrets

| Secret | Required For | Description |
|--------|-------------|-------------|
| `SSH_PRIVATE_KEY` | All | SSH key for droplet access |
| `DIGITALOCEAN_TOKEN` | All | DO API token |
| `DO_SPACES_ACCESS_KEY` | initial-deploy, destroy | Terraform state storage |
| `DO_SPACES_SECRET_KEY` | initial-deploy, destroy | Terraform state storage |
| `SSH_FINGERPRINT` | initial-deploy, destroy | SSH key fingerprint in DO |
| `MANAGER_IP` | update, add-service, destroy | Manager node public IP |
| `DOMAIN` | destroy | Domain name |

---

## Configuration

Create `.staxless.yml` in your repo root to customize defaults:

```yaml
cloud:
  provider: digitalocean
  region: nyc3

infrastructure:
  manager_size: s-2vcpu-4gb
  worker_size: s-2vcpu-4gb
  worker_count: 2

deployment:
  stack_name: staxless
  compose_file: docker/compose/docker-compose.prod.yml
  bake_file: docker/docker-bake.hcl
  registry: ghcr.io
```

---

## Project Structure

```
staxless-deploy/
├── .github/workflows/          # Reusable workflows
│   ├── initial-deploy.yml      # Full infra + services
│   ├── update-services.yml     # Rolling updates
│   ├── add-service.yml         # New service deployment
│   └── destroy.yml             # Teardown
├── actions/                    # Composite actions
│   ├── setup-ssh/              # SSH key + known_hosts
│   ├── setup-tools/            # Terraform, doctl, jq
│   ├── terraform-provision/    # Provision infrastructure
│   ├── terraform-destroy/      # Destroy infrastructure
│   ├── init-swarm/             # Swarm init + worker join
│   ├── registry-login/         # GHCR / DO / ECR login
│   ├── build-images/           # docker buildx bake
│   ├── create-secrets/         # Docker Swarm secrets
│   ├── deploy-stack/           # docker stack deploy
│   ├── rolling-update/         # Zero-downtime updates
│   ├── health-check/           # Replica verification
│   └── graceful-shutdown/      # Scale down + leave swarm
├── infrastructure/
│   ├── digitalocean/           # Terraform configs
│   └── aws/                    # Future provider
├── scripts/                    # Shell scripts
│   ├── deployment/             # Build, deploy, health
│   └── infrastructure/         # Terraform, MongoDB
└── defaults/                   # Default tfvars
```

---

## Architecture

```
Consumer Repo                    staxless-deploy
├── docker/                      ├── .github/workflows/    (4 reusable workflows)
│   ├── compose/                 ├── actions/              (12 composite actions)
│   ├── docker-bake.hcl          ├── infrastructure/       (Terraform per provider)
│   └── dockerfiles/             ├── scripts/              (Shell scripts)
├── microservices/               └── defaults/             (Default configs)
├── .staxless.yml
└── .github/workflows/deploy.yml
```

---

## Multi-Cloud

The `infrastructure/` directory supports multiple cloud providers. Each provider must output the same Terraform contract:

- `manager_ip` / `manager_private_ip`
- `worker_ips` / `worker_private_ips`
- `all_node_ips`
- `vpc_id`

Currently supported: **DigitalOcean**. AWS skeleton included for future use.

---

## Links

- [Staxless](https://staxless.com)
- [CLI Documentation](https://github.com/Staxless/staxless-cli)
- [Report Issues](https://github.com/Staxless/staxless-deploy/issues)

---

<div align="center">

Made with care by [Staxless](https://staxless.com)

</div>
