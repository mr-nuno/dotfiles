# Configuration

## SDK Pinning

A `global.json` is maintained at the solution root:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  }
}
```

## Dependency Injection Registration

Each project has a `DependencyInjection.cs` with an `IServiceCollection` extension method. `Program.cs` calls all three:

```csharp
builder.Services
    .AddApplicationServices()
    .AddInfrastructureServices(builder.Configuration)
    .AddApiServices();
```

- **`Application/DependencyInjection.cs`** — registers MediatR (assembly scanning), FluentValidation validators
- **`Infrastructure/DependencyInjection.cs`** — registers `AppDbContext` / `IApplicationDbContext`, `IDateTimeProvider`, `IUserSession`, EF Core
- **`Api/DependencyInjection.cs`** — registers FastEndpoints, health checks, authorization policies, OpenAPI + Scalar

## Program.cs — Middleware Ordering

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((ctx, cfg) => cfg.ReadFrom.Configuration(ctx.Configuration));

builder.Services
    .AddApplicationServices()
    .AddInfrastructureServices(builder.Configuration)
    .AddApiServices();

var app = builder.Build();

app.UseSerilogRequestLogging(options =>
{
    options.GetLevel = (httpContext, _, _) =>
        httpContext.Request.Path.StartsWithSegments("/health")
            ? Serilog.Events.LogEventLevel.Verbose
            : Serilog.Events.LogEventLevel.Information;
});
app.UseMiddleware<GlobalExceptionHandlerMiddleware>();
app.UseAuthentication();
app.UseAuthorization();
app.UseFastEndpoints();

// Health checks — Kubernetes-style liveness and readiness probes
var healthOptions = new HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        string version = Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "0.0.0";
        var response = new { status = report.Status.ToString(), version };
        await JsonSerializer.SerializeAsync(context.Response.Body, response, cancellationToken: context.RequestAborted);
    }
};
app.MapHealthChecks("/health/live", healthOptions).AllowAnonymous();
app.MapHealthChecks("/health/ready", healthOptions).AllowAnonymous();

// Development only — OpenAPI doc + Scalar UI
if (app.Environment.IsDevelopment())
{
    app.UseSwaggerGen();                    // serves /swagger/{documentName}/swagger.json
    app.MapScalarApiReference(options =>
    {
        options.OpenApiRoutePattern = "/swagger/{documentName}/swagger.json";
    });                                     // serves /scalar/v1
}

app.Run();
```

This ordering is strict. Serilog request logging wraps everything. Exception handler catches unhandled errors. Auth runs before endpoints. Health checks are mapped after FastEndpoints and are anonymous.

**Scalar + FastEndpoints.Swagger integration**: `MapScalarApiReference()` defaults to reading from ASP.NET Core's built-in OpenAPI route (`/openapi/v1.json`), which FastEndpoints does **not** use. You **must** set `OpenApiRoutePattern` to `/swagger/{documentName}/swagger.json` so Scalar finds the NSwag-generated document.

## appsettings.json Structure

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Database=AppDb;User=sa;Password=Your_password123;TrustServerCertificate=true"
  },
  "EntraId": {
    "TenantId": "",
    "ClientId": "",
    "Authority": "https://login.microsoftonline.com/{tenant-id}/v2.0",
    "Audience": "api://{client-id}"
  },
  "Serilog": {
    "Using": ["Serilog.Sinks.Console", "Serilog.Sinks.Seq"],
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.AspNetCore": "Warning",
        "Microsoft.EntityFrameworkCore": "Warning"
      }
    },
    "WriteTo": [
      { "Name": "Console" },
      {
        "Name": "Seq",
        "Args": {
          "serverUrl": "http://localhost:5341"
        }
      }
    ],
    "Enrich": ["FromLogContext", "WithMachineName", "WithThreadId"]
  }
}
```

- Connection string key is always `ConnectionStrings:DefaultConnection`
- Entra ID config lives under `EntraId` section
- Serilog is fully configured in appsettings — no C# configuration beyond `ReadFrom.Configuration()`
- Environment overrides go in `appsettings.{Environment}.json`

## Health Checks

Kubernetes-style health check endpoints:

- **`/health/live`** — liveness probe (is the process running?)
- **`/health/ready`** — readiness probe (is the app ready to serve traffic?)

Register in `Api/DependencyInjection.cs`:

```csharp
services.AddHealthChecks();
```

Response format:

```json
{ "status": "Healthy", "version": "1.2.3" }
```

- Both endpoints are **anonymous** — health probes must work without authentication
- Serilog request logging is set to `Verbose` for `/health` paths to avoid log spam
- Add database health checks to readiness probe when needed: `services.AddHealthChecks().AddSqlServer(connectionString)`

## .editorconfig

Key rules enforced by `.editorconfig` at the solution root:

- `indent_style = space`, `indent_size = 4`
- `dotnet_sort_system_directives_first = true`
- `csharp_style_namespace_declarations = file_scoped`
- `csharp_prefer_primary_constructors = true`
- `csharp_style_var_for_built_in_types = true` (prefer `var` for all locals — built-in and complex alike)
