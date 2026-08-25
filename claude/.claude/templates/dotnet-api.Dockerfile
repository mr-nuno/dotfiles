# Dockerfile — .NET Web API (multi-stage, Alpine, culture-aware, non-root).
# See .claude/conventions/dotnet.md and .claude/docs/ci-cd-docker.md.
#
# Build context = repo ROOT (so Directory.*.props + global.json are in scope).
#   docker build -t myapi --build-arg VERSION=1.2.3 -f src/MyApi/Dockerfile .
# Replace {Api} with your real project name. The referenced Clean Architecture projects
# (Application / Domain / Infrastructure) are spelled out in the restore layer below —
# rename/add COPY lines to match whatever your {Api} project actually references.

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

# --- Restore layer: copy ONLY solution/props + csproj first, so `restore` is cached
#     until dependencies actually change. (Directory.Packages.props is REQUIRED by
#     Central Package Management — restore fails without it.)
#     One COPY per referenced project — `dotnet restore` walks the whole ProjectReference
#     graph, so EVERY referenced csproj must be present or restore fails.
COPY ["Directory.Build.props", "Directory.Packages.props", "global.json", "./"]
COPY ["src/{Api}/{Api}.csproj", "src/{Api}/"]
COPY ["src/Application/Application.csproj", "src/Application/"]
COPY ["src/Domain/Domain.csproj", "src/Domain/"]
COPY ["src/Infrastructure/Infrastructure.csproj", "src/Infrastructure/"]
RUN dotnet restore "src/{Api}/{Api}.csproj"

# --- Build layer: now bring in the rest of the source and publish.
COPY . .
ARG VERSION=1.0.0
RUN dotnet publish "src/{Api}/{Api}.csproj" \
    -c Release -o /app/publish --no-restore \
    /p:Version=${VERSION} /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app

# Culture-aware globalization (dates/sorting/casing for a real culture, e.g. sv-SE).
# See https://github.com/dotnet/announcements/issues/20
RUN apk add --no-cache icu-libs
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8
# To shrink a genuinely culture-agnostic app: drop the `apk add icu-libs` line above
# and set `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true` instead.

COPY --from=build /app/publish .

# Run as the non-root user baked into the aspnet image.
USER $APP_UID

EXPOSE 8080
# Optional health probe (endpoint must AllowAnonymous):
# HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["dotnet", "{Api}.dll"]
