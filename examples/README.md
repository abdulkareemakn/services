# Examples

This directory contains example service configurations to help you get started.

## Available Examples

### nginx-example

A simple nginx web server example demonstrating:
- Basic Docker Compose setup
- Port mapping
- Volume mounting
- Environment variables
- Restart policies

## Using These Examples

### As a Template

Copy an example to create your own service:

```bash
cp -r examples/nginx-example my-new-service
cd my-new-service
# Edit docker-compose.yml for your needs
```

### Testing Locally

Test any example locally before deploying:

```bash
cd examples/nginx-example
docker compose up -d
docker compose logs -f
docker compose down
```

### Deploying

Once you push changes to `main`, the workflow will automatically deploy to your VPS:

```bash
git add my-new-service/
git commit -m "Add my new service"
git push origin main
```

## Best Practices

1. **Keep services isolated** - Each service should be in its own directory
2. **Use specific image tags** - Avoid `latest` in production
3. **Set restart policies** - Use `unless-stopped` or `always`
4. **Document your services** - Add a README.md in each service directory
5. **Use environment variables** - For configuration that may change
6. **Test locally first** - Always test with `docker compose up` before pushing

## Service Structure

Each service directory should follow this structure:

```
my-service/
├── docker-compose.yml      # Required: Compose configuration
├── README.md               # Recommended: Service documentation
├── .env.example            # Optional: Example environment variables
└── config/                 # Optional: Configuration files
    └── app.conf
```

## Adding More Examples

Feel free to add more example services that demonstrate:
- Database services (PostgreSQL, MySQL, MongoDB)
- Application stacks (LAMP, MEAN, etc.)
- Monitoring tools (Prometheus, Grafana)
- CI/CD tools
- Custom applications
