# Dockerfile — React SPA served by a .NET BFF from wwwroot (single image, same-origin, no nginx).
# See .claude/conventions/dotnet.md, .claude/rules/code-docker.md, .claude/docs/ci-cd-docker.md.
#
# Build context = repo ROOT. Assumes sibling `frontend/` (Vite React) and `backend/` (.NET) dirs.
#   docker build -t myapp --build-arg VERSION=1.2.3 .
# Replace {Api} and project paths with your real names.
#
# This is the 4-project layout. For a COLLAPSED layout (see "Solution layout variants" in
# .claude/docs/folder-structure.md) trim the backend restore layer below to {Api} + Core
# (2-project) or just {Api} (1-project) — no separate BFF template exists for those.

# 1) Build the React SPA.
FROM node:24-alpine AS frontend
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build              # outputs to /frontend/dist

# 2) Publish the .NET API, then drop the SPA into wwwroot.
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS backend
WORKDIR /src
# Restore layer (Directory.Packages.props REQUIRED for CPM).
# One COPY per referenced project — restore walks the whole ProjectReference graph, so
# every referenced csproj must be present or restore fails.
COPY ["backend/Directory.Build.props", "backend/Directory.Packages.props", "backend/global.json", "./"]
COPY ["backend/src/{Api}/{Api}.csproj", "src/{Api}/"]
COPY ["backend/src/Application/Application.csproj", "src/Application/"]
COPY ["backend/src/Domain/Domain.csproj", "src/Domain/"]
COPY ["backend/src/Infrastructure/Infrastructure.csproj", "src/Infrastructure/"]
RUN dotnet restore "src/{Api}/{Api}.csproj"
COPY backend/ .
ARG VERSION=1.0.0
RUN dotnet publish "src/{Api}/{Api}.csproj" \
    -c Release -o /app --no-restore \
    /p:Version=${VERSION} /p:UseAppHost=false
COPY --from=frontend /frontend/dist /app/wwwroot

# 3) Runtime.
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app

# Culture-aware globalization. See https://github.com/dotnet/announcements/issues/20
RUN apk add --no-cache icu-libs
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8
# Culture-agnostic? Drop `apk add icu-libs` and set INVARIANT=true instead.

COPY --from=backend /app ./
USER $APP_UID

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "{Api}.dll"]
