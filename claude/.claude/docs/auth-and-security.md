# Authentication & Authorization

## Authentication — OAuth 2.0 with Entra ID

The API is a **resource server** — it validates JWT bearer tokens issued by Microsoft Entra ID. It does **not** handle login flows.

### JWT Bearer Configuration

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        var entraConfig = builder.Configuration.GetSection("EntraId");
        string tenantId = entraConfig["TenantId"]!;
        options.Authority = entraConfig["Authority"];
        options.Audience = entraConfig["Audience"];
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidIssuers =
            [
                $"https://login.microsoftonline.com/{tenantId}/v2.0",
                $"https://sts.windows.net/{tenantId}/"
            ]
        };
        // Do NOT set RoleClaimType = "roles" — the default (ClaimTypes.Role) already
        // matches the mapped claim from v1.0 tokens. Setting it breaks IsInRole checks.
    });
```

**Important — issuer and role claim pitfalls:**

- **ValidIssuers**: Always accept both v1.0 (`sts.windows.net`) and v2.0 (`login.microsoftonline.com`) issuer formats. Which endpoint issues the token depends on `accessTokenAcceptedVersion` in the app registration manifest — not the authority URL.
- **RoleClaimType**: Do not set `RoleClaimType = "roles"`. The v1.0 JWT handler auto-maps the `roles` claim to `http://schemas.microsoft.com/ws/2008/06/identity/claims/role`. The default `RoleClaimType` (`ClaimTypes.Role`) already matches this mapped value.

### Authorization Policies

Authorization uses **Entra ID app roles** — not scopes. Define role-based policies:

```csharp
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("CanViewProducts", policy =>
        policy.RequireRole("Products.Read"));

    options.AddPolicy("CanCreateProducts", policy =>
        policy.RequireRole("Products.Write"));

    options.AddPolicy("AdminOnly", policy =>
        policy.RequireRole("Admin"));
});
```

### Endpoint Authorization

Apply policies in the endpoint `Configure()` method:

```csharp
public override void Configure()
{
    Get("/products/{id}");
    Policies("CanViewProducts");
}
```

- All endpoints are **authenticated by default**. Use `AllowAnonymous()` only for explicitly public endpoints (health checks, OpenAPI).
- Custom policy requirements and handlers live in `Api/Authorization/`.
- **Handlers (MediatR)** never perform authorization checks — that is the endpoint's responsibility.

## Debugging JWT Authentication

When auth fails silently (401 with no detail), add `JwtBearerEvents` to surface the exact failure:

```csharp
options.Events = new JwtBearerEvents
{
    OnAuthenticationFailed = context =>
    {
        Log.Error(context.Exception, "JWT authentication failed");
        return Task.CompletedTask;
    },
    OnChallenge = context =>
    {
        Log.Warning("JWT challenge: {Error} — {ErrorDescription}",
            context.Error, context.ErrorDescription);
        return Task.CompletedTask;
    },
    OnTokenValidated = context =>
    {
        Log.Debug("JWT validated for {Identity}",
            context.Principal?.Identity?.Name);
        return Task.CompletedTask;
    }
};
```

Also add Serilog minimum level overrides in `appsettings.Development.json`:

```json
"Serilog": {
  "MinimumLevel": {
    "Override": {
      "Microsoft.AspNetCore.Authentication": "Debug",
      "Microsoft.AspNetCore.Authorization": "Debug"
    }
  }
}
```
