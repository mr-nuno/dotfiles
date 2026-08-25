# Global Instructions

## Git — Always

- **NEVER push directly to `main` or `develop`** — always create a branch first
- **NEVER commit directly to `main` or `develop`** — all changes go through pull requests
- Before any git push, verify you are on a feature/fix/chore branch, not `main` or `develop`
- Conventional Commits: `feat`, `fix`, `refactor`, `chore`, `test`, `docs`, `style`
- Never include any claude references in commits or pull requests

### Commit message examples

- `feat: new endpoint for fetching pets`
- `fix: added validation to add pet`
- `chore: updated readme`

## .NET Web API Projects

For .NET Web API projects, see `conventions/dotnet.md` for standard conventions and patterns.

**Exception**: Projects that define their own complete .NET conventions in their project-level CLAUDE.md (e.g., the claude-api-workbench) should use their own conventions — ignore `conventions/dotnet.md` for those projects.

### DO NOT

- **DO NOT upgrade MediatR past `12.5.0`.** Version 13.0.0 and later require a paid commercial license (LuckyPennySoftware). `12.5.0` is the last release under the free Apache-2.0 license.

## React projects

For React projects, see `conventions/react.md` for standard conventions and patterns.

## Architecture reference (`docs/`)

Deep-dive docs the .NET conventions link into:

- `docs/folder-structure.md` — directory tree & naming.
- `docs/configuration.md` — Program.cs, appsettings, DI, health checks.
- `docs/interfaces.md` — core interfaces & claim mappings.
- `docs/domain-entities.md` — aggregates, entities, StronglyTypedId, enumerations.
- `docs/responses-and-mapping.md` — response records, DTO tiers, pagination.
- `docs/api-response-pattern.md` — `ApiResponse`, `ResultExtensions`, endpoints.
- `docs/auth-and-security.md` — JWT bearer, policies, endpoint auth.
- `docs/resilience-and-caching.md` — HttpClient resilience & caching.
- `docs/testing.md` — assertions, Testcontainers, Respawn.
- `docs/ci-cd-docker.md` — pipelines, Docker, docker-compose.

## Scaffolding templates (`templates/`)

Reusable root files for standing up a new .NET Web API / React project live in `templates/`
(`Directory.Build.props`, `Directory.Packages.props`, `global.json`, `dotnet.editorconfig`,
`docker-compose.yml`, the `dotnet-*`/`react-nginx` Dockerfiles, `.gitignore`/`.dockerignore`,
`env.example`). Copy the ones you need into the project root and replace any `{Api}`/`{Worker}`/
`{App}` placeholders.

## Working style

- **Docker**: build once / run anywhere; multi-stage builds; runtime config via env vars +
  nginx templates. See `rules/code-docker.md`.
- **Terminal**: prefix any question or clarification request with a ❓ emoji.
  See `rules/terminal-session.md`.
