# Nginx Example Service

This is an example service demonstrating the repository structure.

## Files

- `docker-compose.yml` - Docker Compose configuration for nginx
- `README.md` - This file

## Usage

This service will be automatically deployed to your VPS when you push changes to the `docker-compose.yml` file on the `main` branch.

### Local Testing

You can test this service locally:

```bash
cd examples/nginx-example
docker compose up -d
```

Visit http://localhost:8080 to see the nginx welcome page.

### Stopping the Service

```bash
docker compose down
```

## Customization

Modify the `docker-compose.yml` file to:
- Change the port mapping
- Add custom nginx configuration
- Mount custom HTML files
- Configure environment variables
