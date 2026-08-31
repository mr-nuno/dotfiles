---
paths:
  - "**/Dockerfile*"
  - "**/*.dockerfile"
  - "**/docker-compose*.yml"
  - "**/docker-compose*.yaml"
  - "**/compose*.yml"
  - "**/nginx*.conf*"
  - "**/.dockerignore"
  - "**/entrypoint*.sh"
---

# Docker Style

- Build once, run anywhere
- Use environment variables in combination with nginx for runtime configuration
- Multi-stage builds: build stage with Node, serve stage with nginx
- Use a custom entrypoint script to derive env vars (e.g. base64-encoded auth) before starting nginx
- Use nginx template files (`/etc/nginx/templates/`) so env vars are substituted at container start — for a React SPA served by nginx, copy `~/.claude/templates/react-nginx.Dockerfile` (+ `react-nginx.nginx.conf.template`, `react-nginx.entrypoint.sh`)
- Always add a `.gitignore` that ignores `.env` / `.env.*` (keep a committed `.env.example`) — never commit real secrets. For .NET/Docker projects, copy `~/.claude/templates/dotnet-docker.gitignore`
