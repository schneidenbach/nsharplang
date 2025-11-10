# Web API CI/CD Example

This example shows how to set up CI/CD for a N# ASP.NET Core Web API with Docker deployment.

## Structure

```
web-api/
├── .github/
│   └── workflows/
│       ├── build.yml         # Build and test
│       ├── docker.yml        # Build and push Docker images
│       └── deploy.yml        # Deploy to staging/production
├── src/
│   └── Program.nl            # API code
├── Dockerfile                # Production Docker image
├── docker-compose.yml        # Local development
├── project.yml               # N# project configuration
└── README.md
```

## Quick Start

### 1. Copy Workflows and Docker Files

```bash
mkdir -p .github/workflows
cp ../../ci-templates/github-actions/build.yml .github/workflows/
cp ../../ci-templates/docker/Dockerfile.webapi ./Dockerfile
cp ../../ci-templates/docker/docker-compose.yml ./
cp ../../ci-templates/docker/.dockerignore ./
```

Create `docker.yml` workflow (see below).

### 2. Configure GitHub Secrets

Add to your repository settings → Secrets and variables → Actions:

- `DOCKER_USERNAME` - Your Docker Hub username
- `DOCKER_PASSWORD` - Your Docker Hub password or access token
- `NUGET_API_KEY` - Your NuGet.org API key (optional, for packages)

### 3. Update Dockerfile

Edit `Dockerfile` to replace `YourApp` with your actual app name from `project.yml`:

```dockerfile
# Change this line:
ENTRYPOINT ["dotnet", "YourApp.dll"]

# To your actual assembly name:
ENTRYPOINT ["dotnet", "MyWebApi.dll"]
```

### 4. Push to GitHub

```bash
git add .
git commit -m "Add CI/CD with Docker support"
git push
```

## Docker Workflow

Create `.github/workflows/docker.yml`:

```yaml
name: Docker Build and Push

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

env:
  REGISTRY: docker.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        username: ${{ secrets.DOCKER_USERNAME }}
        password: ${{ secrets.DOCKER_PASSWORD }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
          type=sha

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        file: ./Dockerfile
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## Local Development with Docker

### Run locally

```bash
docker-compose up
```

Your API will be available at http://localhost:8080

### Rebuild after code changes

```bash
docker-compose up --build
```

## Deployment

### Deploy to Azure Container Instances

Add `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Azure

on:
  push:
    tags: [ 'v*' ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}

    - name: Deploy to Azure Container Instances
      uses: azure/aci-deploy@v1
      with:
        resource-group: myapp-rg
        dns-name-label: myapp-${{ github.run_number }}
        image: ${{ secrets.DOCKER_USERNAME }}/${{ github.repository }}:${{ github.ref_name }}
        registry-username: ${{ secrets.DOCKER_USERNAME }}
        registry-password: ${{ secrets.DOCKER_PASSWORD }}
        name: myapp
        location: 'eastus'
        ports: 8080
```

### Deploy to Kubernetes

Create `k8s/deployment.yml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: yourusername/yourrepo:latest
        ports:
        - containerPort: 8080
        env:
        - name: ASPNETCORE_ENVIRONMENT
          value: "Production"
---
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: myapp
```

Deploy with:

```bash
kubectl apply -f k8s/deployment.yml
```

## Health Checks

Add a health check endpoint to your API (in Program.nl):

```nsharp
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
```

The Dockerfile includes a health check that pings this endpoint.

## Best Practices

1. **Multi-stage builds**: Dockerfile uses multi-stage build for smaller images
2. **Non-root user**: Container runs as non-root for security
3. **Layer caching**: Dependencies are restored in a separate layer
4. **Health checks**: Include health endpoint for orchestrators
5. **Environment variables**: Configure via environment, not hardcoded

## Monitoring

### Add Application Insights

In `project.yml`:

```yaml
dependencies:
  - Microsoft.ApplicationInsights.AspNetCore: "2.21.0"
```

In `Program.nl`:

```nsharp
builder.Services.AddApplicationInsightsTelemetry()
```

### Logging

Use structured logging:

```nsharp
app.Logger.LogInformation("API started on {Port}", 8080)
```

## Troubleshooting

### Docker build fails

- Check that N# CLI is available in the build stage
- Verify project.yml and .csproj are copied before restore
- Ensure all source files are copied before build

### Container exits immediately

- Check logs: `docker logs <container-id>`
- Verify ENTRYPOINT points to correct DLL
- Ensure all dependencies are in the final stage

### Port conflicts

Change ports in docker-compose.yml:

```yaml
ports:
  - "9090:8080"  # Host:Container
```
