# Dockerfile — .NET Web API, 2-PROJECT layout: {Api} host + Core (multi-stage, Alpine, non-root).
# Core is a single library merging Application/Domain/Infrastructure as FOLDERS — same namespaces
# and same split DI methods (AddApplicationServices/AddInfrastructureServices) as the 4-project
# layout, just one library assembly. See "Solution layout variants" in .claude/docs/folder-structure.md.
#
# Build context = repo ROOT (so Directory.*.props + global.json are in scope).
#   docker build -t myapi --build-arg VERSION=1.2.3 -f src/MyApi/Dockerfile .
# Replace {Api} with your host project's name; the library project is named Core.

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

# --- Restore layer: copy solution/props + every referenced csproj first, so `restore` is
#     cached until dependencies change. (Directory.Packages.props is REQUIRED by Central
#     Package Management.) `dotnet restore` walks the ProjectReference graph, so BOTH the
#     host and Core csproj must be present or restore fails.
COPY ["Directory.Build.props", "Directory.Packages.props", "global.json", "./"]
COPY ["src/{Api}/{Api}.csproj", "src/{Api}/"]
COPY ["src/Core/Core.csproj", "src/Core/"]
RUN dotnet restore "src/{Api}/{Api}.csproj"

# --- Build layer: bring in the rest of the source and publish.
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
