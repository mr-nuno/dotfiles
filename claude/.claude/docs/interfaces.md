# Interface Definitions

## IApplicationDbContext

```csharp
public interface IApplicationDbContext
{
    DbSet<Product> Products { get; }
    // add DbSet<T> per entity
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
```

- Exposes `DbSet<T>` properties for each entity and `SaveChangesAsync` returning `Task<int>`.
- `AppDbContext` implements this interface. Handlers depend on `IApplicationDbContext`, never on `AppDbContext`.
- Registered as **scoped** in DI.

## IDateTimeProvider

```csharp
public interface IDateTimeProvider
{
    DateTimeOffset UtcNow { get; }
}
```

- Single read-only property. Returns `DateTimeOffset.UtcNow` in production.
- Registered as **singleton** in DI.

## IUserSession

```csharp
public interface IUserSession
{
    string UserId { get; }
    string Email { get; }
    string DisplayName { get; }
    IReadOnlyList<string> Roles { get; }
    bool IsAuthenticated { get; }
}
```

- Implemented in `Infrastructure/Services/UserSession.cs` by reading claims from `IHttpContextAccessor`.
- `UserId` maps to the `oid` or `sub` claim from the Entra ID JWT.
- `Email` maps to the `email` or `preferred_username` claim.
- `Roles` maps to the `roles` claim.
- Registered as **scoped** in DI.
