# Dockerfile — .NET worker / BackgroundService, SINGLE-PROJECT layout (multi-stage, Alpine, non-root).
# For a small self-contained worker: one csproj holds everything (Application/, Domain/,
# Infrastructure/ as FOLDERS — same namespaces as the 4-project layout, just one assembly).
# No inbound HTTP surface unless the worker hosts a health endpoint.
# See "Solution layout variants" in .claude/docs/folder-structure.md.
#
# Build context = repo ROOT. Replace {Worker} with your single project's name.
#   docker build -t myworker --build-arg VERSION=1.2.3 -f src/MyWorker/Dockerfile .

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

# Restore layer (cached until deps change; Directory.Packages.props REQUIRED for CPM).
# One project → one COPY line.
COPY ["Directory.Build.props", "Directory.Packages.props", "global.json", "./"]
COPY ["src/{Worker}/{Worker}.csproj", "src/{Worker}/"]
RUN dotnet restore "src/{Worker}/{Worker}.csproj"

# Build layer.
COPY . .
ARG VERSION=1.0.0
RUN dotnet publish "src/{Worker}/{Worker}.csproj" \
    -c Release -o /app/publish --no-restore \
    /p:Version=${VERSION} /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app

# Culture-aware globalization. See https://github.com/dotnet/announcements/issues/20
RUN apk add --no-cache icu-libs
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8
# Culture-agnostic? Drop `apk add icu-libs` and set INVARIANT=true instead.

COPY --from=build /app/publish .
USER $APP_UID

# Only if the worker hosts a health/metrics endpoint:
# EXPOSE 8080
ENTRYPOINT ["dotnet", "{Worker}.dll"]
