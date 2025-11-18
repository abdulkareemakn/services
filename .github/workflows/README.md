# GitHub Actions Workflow - Service Deployment

This directory contains the GitHub Actions workflow for automatically deploying services to a VPS.

## Workflow: Deploy Services to VPS

### Overview

The `deploy-services.yml` workflow automatically detects changes to Docker Compose files and redeploys the affected services on your VPS via SSH.

### How It Works

1. **Trigger**: The workflow runs on every push to the `main` branch that includes changes to Docker Compose files
2. **Detection**: It identifies which `docker-compose*.yml` or `docker-compose*.yaml` files have changed
3. **Deployment**: For each changed service:
   - Copies the updated compose file to the VPS
   - Pulls the latest Docker images
   - Deploys the service using `docker compose up -d`
   - Cleans up old unused images

### Required GitHub Secrets

You must configure the following secrets in your GitHub repository settings:

| Secret Name | Description | Example |
|------------|-------------|---------|
| `SSH_PRIVATE_KEY` | Private SSH key for accessing the VPS | Contents of your `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` |
| `VPS_HOST` | IP address or hostname of your VPS | `192.168.1.100` or `vps.example.com` |
| `VPS_USER` | SSH username for the VPS | `root` or `deploy` |
| `VPS_DEPLOY_PATH` | (Optional) Base path on VPS where services are deployed | `/opt/services` (default) |

### Setting Up GitHub Secrets

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each of the required secrets listed above

### Generating SSH Keys

If you don't have an SSH key pair, generate one:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/deploy_key
```

Then copy the public key to your VPS:

```bash
ssh-copy-id -i ~/.ssh/deploy_key.pub user@vps_host
```

Copy the private key contents for the `SSH_PRIVATE_KEY` secret:

```bash
cat ~/.ssh/deploy_key
```

### Directory Structure

The monorepo should follow this structure:

```
services/
├── service1/
│   └── docker-compose.yml
├── service2/
│   └── docker-compose.yaml
├── service3/
│   └── docker-compose.production.yml
└── .github/
    └── workflows/
        └── deploy-services.yml
```

Each service should be in its own directory with its Docker Compose file.

### VPS Setup Requirements

Your VPS must have:

1. **Docker and Docker Compose installed**
2. **SSH access configured** for the user specified in `VPS_USER`
3. **The deploy path created** (e.g., `/opt/services`)
4. **Proper permissions** for the SSH user to run Docker commands

#### Installing Docker on VPS (Ubuntu/Debian)

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group (to run docker without sudo)
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt-get update
sudo apt-get install docker-compose-plugin
```

### Usage Example

1. Create a new service directory with a Docker Compose file:

```bash
mkdir -p my-app
cat > my-app/docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    restart: unless-stopped
EOF
```

2. Commit and push to main:

```bash
git add my-app/docker-compose.yml
git commit -m "Add my-app service"
git push origin main
```

3. The workflow will automatically:
   - Detect the change to `my-app/docker-compose.yml`
   - Copy it to your VPS at `${VPS_DEPLOY_PATH}/my-app/`
   - Run `docker compose up -d` to deploy the service

### Workflow Output

The workflow provides a deployment summary showing:
- Which compose files changed
- Which services were deployed
- Deployment status for each service

### Troubleshooting

#### Workflow fails with "Permission denied (publickey)"

- Verify that `SSH_PRIVATE_KEY` secret contains the correct private key
- Ensure the corresponding public key is in `~/.ssh/authorized_keys` on the VPS
- Check that the `VPS_USER` has SSH access to the VPS

#### Service fails to deploy

- Check that Docker and Docker Compose are installed on the VPS
- Verify the `VPS_USER` has permission to run Docker commands
- Review the workflow logs for specific error messages

#### No deployment triggered

- Ensure changes were pushed to the `main` branch
- Verify that you modified a `docker-compose*.yml` or `docker-compose*.yaml` file
- Check the "Actions" tab in GitHub to see if the workflow ran

### Security Best Practices

1. **Use a dedicated deploy user** on your VPS with limited permissions
2. **Restrict SSH key usage** to only what's necessary
3. **Use SSH key passphrase** if possible (note: not compatible with GitHub Actions)
4. **Regularly rotate** SSH keys
5. **Monitor** deployment logs for suspicious activity
6. **Use .env files** for sensitive configuration (not committed to git)
