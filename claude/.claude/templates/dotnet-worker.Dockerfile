# Dockerfile — .NET worker / BackgroundService (multi-stage, Alpine, culture-aware, non-root).
# Same shape as dotnet-api.Dockerfile; the worker has no inbound HTTP surface unless it
# hosts a health endpoint. See .claude/conventions/dotnet.md, .claude/docs/ci-cd-docker.md.
#
# Build context = repo ROOT. Replace {Worker} with your real name; adjust the referenced
# project COPY lines below (Application / Domain / Infrastructure) to match what it references.
#   docker build -t myworker --build-arg VERSION=1.2.3 -f src/MyWorker/Dockerfile .

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

# Restore layer (cached until deps change; Directory.Packages.props REQUIRED for CPM).
# One COPY per referenced project — restore walks the whole ProjectReference graph, so
# every referenced csproj must be present or restore fails.
COPY ["Directory.Build.props", "Directory.Packages.props", "global.json", "./"]
COPY ["src/{Worker}/{Worker}.csproj", "src/{Worker}/"]
COPY ["src/Application/Application.csproj", "src/Application/"]
COPY ["src/Domain/Domain.csproj", "src/Domain/"]
COPY ["src/Infrastructure/Infrastructure.csproj", "src/Infrastructure/"]
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
