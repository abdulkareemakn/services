# Quick Setup Guide

This guide will help you quickly set up the automated deployment system.

## Prerequisites

- ✅ A VPS with SSH access
- ✅ Docker and Docker Compose installed on the VPS
- ✅ GitHub repository with Actions enabled

## Step-by-Step Setup

### 1. Prepare Your VPS

SSH into your VPS and run:

```bash
# Install Docker (if not already installed)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose plugin
sudo apt-get update
sudo apt-get install docker-compose-plugin

# Create deployment directory
sudo mkdir -p /opt/services
sudo chown $USER:$USER /opt/services

# Logout and login again for group changes to take effect
exit
```

### 2. Generate SSH Key Pair

On your local machine:

```bash
# Generate SSH key for GitHub Actions
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_deploy_key -N ""

# Copy public key to VPS
ssh-copy-id -i ~/.ssh/github_deploy_key.pub user@your-vps-ip

# Test the connection
ssh -i ~/.ssh/github_deploy_key user@your-vps-ip "echo 'Connection successful!'"
```

### 3. Configure GitHub Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add:

| Name | Value |
|------|-------|
| `SSH_PRIVATE_KEY` | Contents of `~/.ssh/github_deploy_key` (entire file) |
| `VPS_HOST` | Your VPS IP address (e.g., `192.168.1.100`) |
| `VPS_USER` | Your SSH username (e.g., `ubuntu`, `root`, `deploy`) |
| `VPS_DEPLOY_PATH` | `/opt/services` (or your preferred path) |

To get the private key content:
```bash
cat ~/.ssh/github_deploy_key
```

Copy the entire output including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`.

### 4. Test Your Setup

Create a test service:

```bash
# Clone your repository
git clone https://github.com/your-username/services.git
cd services

# Create a test service
mkdir -p test-service
cat > test-service/docker-compose.yml << 'EOF'
version: '3.8'
services:
  hello:
    image: hello-world
    container_name: test-hello
EOF

# Commit and push to main
git add test-service/
git commit -m "Add test service"
git push origin main
```

### 5. Verify Deployment

1. Go to the **Actions** tab in your GitHub repository
2. You should see the "Deploy Services to VPS" workflow running
3. Once completed, SSH into your VPS and verify:

```bash
ssh user@your-vps-ip
cd /opt/services/test-service
docker compose ps
```

You should see the hello-world container that ran.

### 6. Add Your Real Services

Now you can add your actual services:

```bash
# Create a new service directory
mkdir -p my-app
cd my-app

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    restart: unless-stopped
EOF

# Commit and push
cd ..
git add my-app/
git commit -m "Add my-app service"
git push origin main
```

## Troubleshooting

### "Permission denied (publickey)"
- Verify the SSH_PRIVATE_KEY secret contains the complete private key
- Ensure the public key is in `~/.ssh/authorized_keys` on the VPS
- Check that the VPS_USER has SSH access

### "docker: command not found"
- Ensure Docker is installed on the VPS
- Verify the user is in the docker group: `groups $USER`
- Try `sudo docker` if permissions are the issue

### Service doesn't start
- Check logs on VPS: `docker compose logs`
- Verify port availability: `netstat -tuln | grep <port>`
- Review the GitHub Actions workflow logs

### Changes not triggering workflow
- Ensure you're pushing to the `main` branch
- Verify the file is named `docker-compose*.yml` or `docker-compose*.yaml`
- Check the Actions tab to see if the workflow is enabled

## Next Steps

- Read the [main README](../README.md) for more information
- Check out [examples](../examples/) for service templates
- Review [workflow documentation](.github/workflows/README.md) for advanced usage

## Security Reminders

🔒 **Never commit**:
- SSH private keys
- Passwords or API tokens
- `.env` files with secrets

✅ **Always**:
- Use GitHub Secrets for sensitive data
- Regularly rotate SSH keys
- Monitor deployment logs
- Keep Docker images updated
