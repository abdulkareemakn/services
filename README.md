# Services Monorepo

This repository contains Docker Compose configurations for various services, with automated deployment to a VPS.

## Overview

This is a monorepo that manages multiple services using Docker Compose. When changes are pushed to the `main` branch, a GitHub Actions workflow automatically detects which services have been modified and redeploys them to a VPS via SSH.

## Quick Start

### 1. Add a New Service

Create a new directory for your service with a Docker Compose file:

```bash
mkdir my-service
cd my-service
```

Create a `docker-compose.yml` file:

```yaml
version: '3.8'
services:
  app:
    image: your-image:latest
    ports:
      - "8080:80"
    restart: unless-stopped
```

### 2. Commit and Push

```bash
git add my-service/
git commit -m "Add my-service"
git push origin main
```

The GitHub Actions workflow will automatically deploy your service to the VPS!

## Repository Structure

```
services/
├── service1/
│   └── docker-compose.yml
├── service2/
│   └── docker-compose.yml
└── .github/
    └── workflows/
        ├── deploy-services.yml    # Deployment workflow
        └── README.md              # Workflow documentation
```

## Setup

### First-Time Setup

**New to this repository?** Follow the [Quick Setup Guide (SETUP.md)](SETUP.md) for step-by-step instructions.

### Prerequisites

- A VPS with Docker and Docker Compose installed
- SSH access to the VPS
- GitHub repository with Actions enabled

### Configuration

You need to configure the following GitHub repository secrets:

- `SSH_PRIVATE_KEY` - Private SSH key for VPS access
- `VPS_HOST` - IP address or hostname of your VPS
- `VPS_USER` - SSH username for the VPS
- `VPS_DEPLOY_PATH` - (Optional) Base deployment path on VPS (default: `/opt/services`)

For detailed setup instructions, see [SETUP.md](SETUP.md) or [.github/workflows/README.md](.github/workflows/README.md)

## How It Works

1. You push changes to Docker Compose files on the `main` branch
2. GitHub Actions detects which compose files changed
3. Changed files are copied to the VPS
4. Services are redeployed using `docker compose up -d`
5. Old images are cleaned up

## Features

- ✅ Automatic detection of changed compose files
- ✅ Selective deployment of only modified services
- ✅ SSH-based secure deployment
- ✅ Support for multiple services in a single push
- ✅ Deployment summary in workflow output
- ✅ Automatic image cleanup

## Documentation

- [Quick Setup Guide (SETUP.md)](SETUP.md) - Step-by-step setup instructions
- [Workflow Documentation](.github/workflows/README.md) - Detailed workflow information
- [Examples](examples/README.md) - Example service configurations
- [Troubleshooting](.github/workflows/README.md#troubleshooting) - Common issues and solutions

## Security

- SSH keys are stored as GitHub secrets
- Only the `main` branch triggers deployments
- Each service runs in isolation using Docker
- See [Security Best Practices](.github/workflows/README.md#security-best-practices) for more information