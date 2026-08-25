# Folder Structure

## Full Directory Tree

```
src/
  Api/
    Endpoints/
      Products/
        CreateProductEndpoint.cs
        GetProductEndpoint.cs
        GetProductsEndpoint.cs
    Middleware/
      GlobalExceptionHandlerMiddleware.cs
    Authorization/
      Policies.cs
    Extensions/
      ResultExtensions.cs
    DependencyInjection.cs
    Program.cs
  Application/
    Common/
      Interfaces/
        IApplicationDbContext.cs
        IDateTimeProvider.cs
        IUserSession.cs
      Models/
        ApiResponse.cs
        PagedRequest.cs
        PagedResponse.cs
    Features/
      Products/
        Dtos/                                  <- shared DTOs within the feature
          ProductSummaryDto.cs
        CreateProduct/
          CreateProductCommand.cs
          CreateProductResponse.cs
          CreateProductMappingExtensions.cs
        GetProduct/
          GetProductQuery.cs
          GetProductResponse.cs
        GetProducts/
          GetProductsQuery.cs
          GetProductsResponse.cs
    DependencyInjection.cs
  Domain/
    Common/
      AuditableEntity.cs
      IAggregateRoot.cs
      Enumeration.cs
    Order/                                   <- one folder per aggregate, named for the entity
      OrderAggregate.cs                      <- aggregate root, class OrderAggregate (: AuditableEntity, IAggregateRoot)
      OrderLine.cs                           <- child entity
      OrderId.cs                             <- StronglyTypedId
      OrderStatus.cs                         <- Enumeration
      Specifications/
        OrderByCustomerSpec.cs
  Infrastructure/
    Persistence/
      AppDbContext.cs
      Configurations/
      Migrations/
    Services/
      DateTimeProvider.cs
      UserSession.cs
    DependencyInjection.cs
tests/
  Api.IntegrationTests/
    Common/
      IntegrationTestWebAppFactory.cs
      BaseIntegrationTest.cs
      FakeAuthHandler.cs
      FakeUserSession.cs
      HttpClientExtensions.cs     <- helper to deserialize ApiResponse<T>
    Features/
      Products/
        CreateProductTests.cs
        GetProductTests.cs
```

## Solution Layout Variants

The tree above is the **canonical 4-project layout** (default). Two collapsed layouts are
also supported for smaller services. **The folders and namespaces are identical in every
layout** (`...Application.Common`, `...Domain.{Entity}`, `Domain/Common/`, …) — only the
number of `.csproj` assemblies changes. The `DependencyInjection.cs` extension methods
(`AddApplicationServices()` / `AddInfrastructureServices()` / `AddApiServices()`) also stay
**split** in every layout.

| Layout | Assemblies | Trade-off |
|---|---|---|
| **4-project** (default) | `Api` (or `Worker`) + `Application` + `Domain` + `Infrastructure` | Layer seams enforced at **compile time** by project-reference direction |
| **2-project** | `{Host}` + `Core` | One boundary kept (host ↔ Core); seams *inside* Core are convention-only |
| **1-project** | `{App}` | Simplest; all seams convention-only |

### 2-project (host + Core)

```
src/
  {Host}/                 <- Api or Worker; owns Program.cs, Endpoints/, DependencyInjection.cs (AddApiServices)
  Core/                   <- one library, all lower layers as FOLDERS (namespaces unchanged)
    Application/
      Common/{Interfaces,Models}/
      Features/{Feature}/...
      DependencyInjection.cs          <- AddApplicationServices (MediatR + validators)
    Domain/
      Common/{AuditableEntity,IAggregateRoot,Enumeration}.cs
      {Entity}/...
    Infrastructure/
      Persistence/{AppDbContext,Configurations,Migrations}/
      Services/{DateTimeProvider,UserSession}.cs
      DependencyInjection.cs          <- AddInfrastructureServices (store, external clients, hosted services)
```

### 1-project (everything in one)

```
src/
  {App}/                  <- single assembly; the folders below carry the same namespaces as the 4-project layout
    Endpoints/            <- (Api host) FastEndpoints
    Application/{Common,Features}/
    Domain/{Common,{Entity}}/
    Infrastructure/{Persistence,Services}/
    DependencyInjection.cs            <- keep AddApplicationServices() + AddInfrastructureServices() SEPARATE (do not merge into one catch-all)
    Program.cs
```

> Collapsing merges assemblies, not structure: keep the layer folders, the namespaces, and
> the split DI methods. The only thing lost is **compile-time** enforcement of the layer-seam
> rules (no vendor types in Application/Domain; depend on the seam, not the client) — those
> become convention-only. Prefer the 4-project layout when that enforcement matters. See the
> "Solution layout" subsection in `.claude/conventions/dotnet.md`.

## File Naming Patterns

- **Endpoints**: `src/Api/Endpoints/{Feature}/{Action}{Entity}Endpoint.cs`
- **Commands/Queries**: `src/Application/Features/{Feature}/{Action}{Entity}/{Action}{Entity}Command.cs` or `Query.cs`
- **Responses**: `src/Application/Features/{Feature}/{Action}{Entity}/{Action}{Entity}Response.cs`
- **Shared DTOs**: `src/Application/Features/{Feature}/Dtos/{Concept}Dto.cs`
- **Mapping**: `src/Application/Features/{Feature}/{Action}{Entity}/{Action}{Entity}MappingExtensions.cs`
- **Aggregates**: `src/Domain/{Entity}/` — one folder per aggregate (named for the entity), one file per class/enum (root, child entities, value objects, enumerations, the id). The root is `{Entity}Aggregate.cs` (class `{Entity}Aggregate`)
- **Specifications**: `src/Domain/{Entity}/Specifications/{Entity}By{Filter}Spec.cs`
- **Strongly Typed IDs**: `src/Domain/{Entity}/{Entity}Id.cs`
- **Entity Configurations**: `src/Infrastructure/Persistence/Configurations/{Entity}Configuration.cs`
