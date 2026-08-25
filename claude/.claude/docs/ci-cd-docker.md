# CI/CD & Docker

## CI/CD

Two pipeline definitions are maintained — **GitHub Actions** and **Azure Pipelines** — with identical behavior.

### Triggers & Strategy

- **On push / PR to `main`**: build + run unit & integration tests only
- **On semantic version tag (`*.*.*`)**: build + run unit & integration tests + build Docker image + push to `ghcr.io`

### GitHub Actions (`.github/workflows/ci.yml`)

```yaml
# Trigger: push/PR to main, tags *.*.*
# Steps:
#   1. Checkout
#   2. Setup .NET
#   3. Restore, Build, Test (unit + integration via Testcontainers)
#   4. (tag only) Log in to ghcr.io, build & push Docker image
#      Image: ghcr.io/<owner>/<repo>:<tag>
```

- Uses `docker/login-action` with `GITHUB_TOKEN` for ghcr.io auth
- Uses `docker/build-push-action` for building and pushing, with `build-args: VERSION=${{ github.ref_name }}` to embed the git tag as the assembly version
- Image tag is the git tag directly (e.g., tag `1.2.3` -> image tag `1.2.3`) + `latest`
- Integration tests run in CI using Docker-in-Docker (Testcontainers manages the SQL Server container)

### Azure Pipelines (`azure-pipelines.yml`)

```yaml
# Trigger: main branch, tags *.*.*
# Steps:
#   1. Use .NET SDK task
#   2. Restore, Build, Test (unit + integration via Testcontainers)
#   3. (tag only) Docker build & push to ghcr.io
#      Uses a Docker service connection for ghcr.io
```

- Uses `Docker@2` task for build and push, with `arguments: '--build-arg VERSION=$(Build.SourceBranchName)'` to embed the git tag as the assembly version
- Tag condition: `startsWith(variables['Build.SourceBranch'], 'refs/tags/')`
- Integration tests require Docker agent capability (Testcontainers needs Docker socket)

### Docker Image

- Registry: `ghcr.io`
- Image name: `ghcr.io/<owner>/<repo>`
- Tags: git tag used directly as image tag (e.g., `1.2.3`) + `latest`
- Multi-stage `Dockerfile`: restore -> build -> publish -> runtime image (`mcr.microsoft.com/dotnet/aspnet:10.0`)
- **Assembly versioning**: The `Dockerfile` accepts a `VERSION` build arg (default `1.0.0`) and passes it to `dotnet publish` via `/p:Version=${VERSION}`. CI pipelines pass the git tag as the version.

## Docker

Copy the matching Dockerfile from `.claude/templates/` (renamed to `Dockerfile` — **the
destination differs per archetype**, see the table) plus `docker.dockerignore` (rename to
`.dockerignore`). All are multi-stage, Alpine, run as the non-root `$APP_UID`, take
`ARG VERSION=1.0.0` for assembly versioning, and are **culture-aware** (`icu-libs` +
`INVARIANT=false`; a commented toggle shrinks to invariant if the app is culture-agnostic).

| Template | Copy to | Build context | Use for |
|---|---|---|---|
| `dotnet-api.Dockerfile` | `src/{Api}/Dockerfile` | repo root | .NET Web API (path `docker-compose.yml` expects) |
| `dotnet-worker.Dockerfile` | `src/{Worker}/Dockerfile` | repo root | .NET `BackgroundService` / worker |
| `dotnet-spa-bff.Dockerfile` | `Dockerfile` (repo root) | repo root (sibling `frontend/` + `backend/`) | React SPA served by the .NET BFF from `wwwroot` (single image) |
| `react-nginx.Dockerfile` (+ `react-nginx.nginx.conf.template`, `react-nginx.entrypoint.sh`) | `frontend/Dockerfile` | frontend app dir | React SPA served by nginx |

> The .NET templates copy `Directory.Packages.props` / `Directory.Build.props` **before**
> `dotnet restore` — required for Central Package Management, and it keeps the restore layer cached.

### Solution-layout variants

The four Dockerfiles above assume the **4-project** layout (their restore layers copy `{Host}`
+ `Application` + `Domain` + `Infrastructure`). For a **collapsed layout** (see the "Solution
layout variants" section of `.claude/docs/folder-structure.md`), copy the matching variant
instead — the **copy-to destination is unchanged**, so `docker-compose.yml` (`dockerfile:
src/{Api}/Dockerfile`) works either way. Only the restore layer differs.

| Template | Copy to | Layout | Restore layer copies |
|---|---|---|---|
| `dotnet-api-single.Dockerfile` | `src/{Api}/Dockerfile` | 1-project API | `{Api}` |
| `dotnet-api-core.Dockerfile` | `src/{Api}/Dockerfile` | 2-project API | `{Api}` + `Core` |
| `dotnet-worker-single.Dockerfile` | `src/{Worker}/Dockerfile` | 1-project worker | `{Worker}` |
| `dotnet-worker-core.Dockerfile` | `src/{Worker}/Dockerfile` | 2-project worker | `{Worker}` + `Core` |

For a **BFF on a collapsed layout**, there is no separate file (a BFF is inherently
frontend + backend): copy `dotnet-spa-bff.Dockerfile` and trim its restore layer to
`{Api}` + `Core` (2-project) or just `{Api}` (1-project) — the header comment notes this.

- `docker-compose.yml` — API + SQL Server + Seq for local development. Copy from
  `.claude/templates/docker-compose.yml`, plus `env.example` → `.env.example` (committed;
  developers copy it to `.env`, which is gitignored). Config/secrets are read from `.env`
  (`env_file`), and the SQL Server healthcheck gates the API's `depends_on`.

- Seq UI: `http://localhost:8081` (no login required — authentication disabled for local dev)
- Seq requires `SEQ_FIRSTRUN_NOAUTHENTICATION=true` for passwordless local access
- API logs sent to Seq via `http://seq:5341` (Docker internal network)
- Scalar API docs: `http://localhost:5000/scalar/v1` (Development only)
- Passwords in docker-compose are **local dev placeholders only** — never used in production
