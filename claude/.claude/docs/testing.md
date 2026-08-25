# Testing

## Assertion Style — Shouldly

```csharp
// Always use Shouldly
result.Success.ShouldBeTrue();
response.Name.ShouldBe("Expected");
items.Count.ShouldBe(3);
product.ShouldNotBeNull();
act.ShouldThrow<InvalidOperationException>();

// Never use xUnit Assert.*
```

## Mocking Style — NSubstitute

```csharp
var db = Substitute.For<IApplicationDbContext>();
var dateTime = Substitute.For<IDateTimeProvider>();
dateTime.UtcNow.Returns(new DateTimeOffset(2025, 1, 1, 0, 0, 0, TimeSpan.Zero));
```

## Test Project Analyzer Suppressions (CA1707 / CA1711)

The solution enforces `TreatWarningsAsErrors=true` solution-wide (`Directory.Build.props`), which turns two code-analysis warnings into build **errors** on test projects. Both fire on intentional xUnit idioms, not on real problems:

- **CA1707** (identifiers should not contain underscores) — test method names deliberately use underscores: `{MethodUnderTest}_Should_{ExpectedBehavior}_When_{Condition}`.
- **CA1711** (identifiers should not have an incorrect suffix) — xUnit collection-definition types end in `Collection`:

  ```csharp
  [CollectionDefinition("Database")]
  public sealed class DatabaseCollection : ICollectionFixture<IntegrationTestWebAppFactory>;
  ```

Silence them **per test project** in the test `.csproj` — scoped to test projects only:

```xml
<!-- {Feature}.Tests.csproj — intentional test idioms, scoped to test projects only -->
<PropertyGroup>
  <NoWarn>$(NoWarn);CA1707;CA1711</NoWarn>
</PropertyGroup>
```

- **Do NOT** add these to the shared `.editorconfig` — it applies solution-wide and would silence the rules in production code too.
- **Do NOT** disable `TreatWarningsAsErrors` to work around this — keep the build strict everywhere else.
- Keep the `$(NoWarn);` prefix so any inherited suppressions are preserved.

## Integration Test Auth Bypass

The `IntegrationTestWebAppFactory` replaces the authentication scheme with a test scheme that auto-authenticates:

```csharp
builder.ConfigureTestServices(services =>
{
    services.AddAuthentication("Test")
        .AddScheme<AuthenticationSchemeOptions, FakeAuthHandler>("Test", null);

    services.RemoveAll<IUserSession>();
    services.AddScoped<IUserSession>(_ => new FakeUserSession
    {
        UserId = "test-user-id",
        Email = "test@example.com",
        DisplayName = "Test User",
        Roles = ["Admin"],
        IsAuthenticated = true
    });
});
```

- `FakeAuthHandler` extends `AuthenticationHandler<AuthenticationSchemeOptions>` and always returns `AuthenticateResult.Success` with claims matching `FakeUserSession`.
- **Role claims** must be added individually — one `new Claim(ClaimTypes.Role, "...")` per role, matching the Entra ID `roles` claim.
- Tests that need a specific user/role override `IUserSession` per-test via the DI scope.
- **No real tokens are ever issued or validated in tests.**

## Integration Test Database — Connection String Injection

Point the app at the Testcontainers database by overriding the connection string as a **host
setting**. This is the one setup detail that silently breaks tests if you get it wrong.

```csharp
protected override void ConfigureWebHost(IWebHostBuilder builder)
{
    // Host configuration — sits ABOVE the app's appsettings.json, so this wins.
    builder.UseSetting("ConnectionStrings:DefaultConnection", _dbContainer.GetConnectionString());

    // ... ConfigureTestServices for auth bypass, mocks, etc.
}
```

- **Use `builder.UseSetting(...)`.** It writes to *host* configuration, which is layered above the
  app's `appsettings.json`.
- **Do NOT use `builder.ConfigureAppConfiguration(...)` to override the connection string.** Under
  `WebApplicationFactory`'s minimal-hosting model the app's own `appsettings.json` is applied *after*
  those callbacks and silently wins. The app then connects to the appsettings server (wrong
  host/password) and every test fails with **`Login failed for user 'sa'`** — even though your
  Testcontainers connection string is perfectly correct. This failure looks like a Testcontainers
  or password bug but is purely config precedence; it can cost hours. Always use `UseSetting`.
- **`EnsureCreatedAsync()` vs `master`.** `MsSqlContainer.GetConnectionString()` targets `master`,
  which already exists — so `EnsureCreated` sees a database and creates **no** schema. If you use
  `EnsureCreatedAsync()` (rather than `MigrateAsync()`), inject a connection string that names a
  dedicated, non-existent database (e.g. `Database=TestDb`) so the schema is actually created.

## Testcontainers — MsSqlBuilder API

**The parameterless `MsSqlBuilder()` constructor is obsolete.** Always pass the image as a constructor parameter:

```csharp
// Correct — pass image as constructor parameter
private readonly MsSqlContainer _dbContainer = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest")
    .Build();

// Wrong — parameterless constructor is obsolete and will be removed
private readonly MsSqlContainer _dbContainer = new MsSqlBuilder()
    .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
    .Build();
```

## Respawn — v7 DbConnection API

**Respawn v7+ requires `DbConnection`, not a connection string.** Both `CreateAsync` and `ResetAsync` take `DbConnection`:

```csharp
// Correct — use DbConnection
await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();

var respawner = await Respawner.CreateAsync(connection, new RespawnerOptions
{
    DbAdapter = DbAdapter.SqlServer
});

await respawner.ResetAsync(connection);

// Wrong — passing connection string directly (Respawn v6 API, no longer compiles)
var respawner = await Respawner.CreateAsync(connectionString, ...);
await respawner.ResetAsync(connectionString);
```

## Integration Test HttpClient Pattern

Tests use `HttpClient` from `WebApplicationFactory` and deserialize into `ApiResponse<T>` via a shared extension:

```csharp
public static class HttpClientExtensions
{
    public static async Task<ApiResponse<T>> GetApiAsync<T>(this HttpClient client, string url, CancellationToken ct = default)
    {
        var response = await client.GetAsync(url, ct);
        var content = await response.Content.ReadAsStringAsync(ct);
        return JsonSerializer.Deserialize<ApiResponse<T>>(content, JsonOptions)!;
    }

    public static async Task<ApiResponse<T>> PostApiAsync<T>(this HttpClient client, string url, object body, CancellationToken ct = default)
    {
        var response = await client.PostAsJsonAsync(url, body, ct);
        var content = await response.Content.ReadAsStringAsync(ct);
        return JsonSerializer.Deserialize<ApiResponse<T>>(content, JsonOptions)!;
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };
}

// Usage in test:
var response = await client.PostApiAsync<CreateProductResponse>("/products", command);
response.Success.ShouldBeTrue();
response.Data!.Name.ShouldBe("Test Product");
```

### Asserting on validation errors — property names are camelCased

FastEndpoints camelCases validation error property names to match the serialized JSON field name, so a rule on a `Price` property comes back as `Property == "price"` (lowercase), **not** `"Price"`. This is correct product behaviour (see `.claude/docs/api-response-pattern.md`, "FastEndpoints Validation -> ApiResponse Integration"). Assert on the property name **case-insensitively**:

```csharp
var response = await client.PostApiAsync<CreateProductResponse>("/products", invalidCommand);
response.Success.ShouldBeFalse();
response.ValidationErrors!
    .ShouldContain(e => string.Equals(e.Property, "price", StringComparison.OrdinalIgnoreCase));

// Do NOT assert e.Property == "Price" — a case-sensitive expectation here is a test bug, not a product bug.
```

(The `HttpClientExtensions` above already set `PropertyNameCaseInsensitive = true`, but that only affects *deserialization* of the envelope — it does not change the `Property` **value**, which stays camelCased.)
