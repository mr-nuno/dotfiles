# .NET Web API Conventions

## Applicability

- **New projects**: Follow these conventions strictly.
- **Existing/legacy projects**: Treat as preferred conventions. Adopt incrementally
  in new code and refactors. Do not rewrite working code solely to conform.
  When the project uses different libraries (e.g., minimal APIs instead of
  FastEndpoints, Moq instead of NSubstitute), follow the project's established
  patterns. These conventions only apply where there is no conflicting
  project-level convention.

## New Project Bootstrap

**Step 0 — before writing any code**, copy the ready-made root files from `.claude/templates/`
into the new repo root, then adapt each:

1. `global.json` → bump `version` to the installed .NET 10 SDK (`dotnet --version`).
2. `Directory.Build.props` → `<Nullable>enable</Nullable>`, `LangVersion`, `ImplicitUsings`, `EnforceCodeStyleInBuild`, `TreatWarningsAsErrors` (relax with `<WarningsNotAsErrors>` if needed).
3. `Directory.Packages.props` → Central Package Management. Keep `MediatR 12.5.0` and `StronglyTypedId 1.0.0-beta08` pinned; run `dotnet list package` (outdated) and bump the rest.
4. `dotnet.editorconfig` → save as `.editorconfig`.
5. `dotnet-docker.gitignore` → save as `.gitignore`.
6. Docker: copy the matching Dockerfile to its **archetype-specific destination** — `dotnet-api` → `src/{Api}/Dockerfile`, `dotnet-worker` → `src/{Worker}/Dockerfile`, `dotnet-spa-bff` → root `Dockerfile`, `react-nginx` → `frontend/Dockerfile` (build contexts differ; the API path is what `docker-compose.yml` expects). Also copy `docker.dockerignore` → `.dockerignore`, `docker-compose.yml` (API + SQL Server + Seq), and `env.example` → `.env.example`. Replace the `{Api}`/`{Worker}` placeholders with your project names; each Dockerfile's restore layer already lists the referenced `Application`/`Domain`/`Infrastructure` projects (adjust those `COPY` lines to match your actual references — restore needs every referenced csproj present). For a **collapsed layout** (see "Solution Layout" below) copy the matching variant instead — `dotnet-api-single` / `dotnet-worker-single` (1-project) or `dotnet-api-core` / `dotnet-worker-core` (2-project, host + `Core`); the destination path is unchanged. See `.claude/docs/ci-cd-docker.md`.

All are committed to source control (never gitignored). Only after these exist should you
scaffold the `Api`/`Application`/`Domain`/`Infrastructure` projects and start on features.

## Tech Stack

- **.NET 10** (LTS)
- **FastEndpoints** — endpoint routing, request/response binding
- **MediatR** (`12.5.0`) — CQRS command/query dispatching within vertical slices. Pinned to 12.5.0, the last version under Apache 2.0 license (v13+ is commercially licensed)
- **EF Core** — ORM with SQL Server
- **FluentValidation** — request validation (integrated via FastEndpoints)
- **Ardalis.Result** — result pattern for service/handler returns
- **Ardalis.Specification** — encapsulate common/reusable EF Core queries
- **StronglyTypedId** (`1.0.0-beta08`, source generator) — type-safe entity IDs with auto-generated JSON converters
- **Serilog** — structured logging (Console + Seq sinks), configured via `appsettings.json`
- **NSubstitute** — mocking/stubbing in unit tests
- **Shouldly** — fluent assertion library
- **xUnit** — unit and integration testing
- **Testcontainers** — real SQL Server for integration tests
- **FastEndpoints.Swagger** — NSwag-based OpenAPI document generation (serves at `/swagger/{documentName}/swagger.json`)
- **Scalar** — modern API documentation UI (serves at `/scalar/v1`, configured to read from FastEndpoints.Swagger route)
- **Docker / docker-compose** — containerized development and deployment

## Architecture & Conventions

### Folder Structure

Vertical slice layout: `Api/Endpoints/`, `Application/Features/`, `Domain/{Entity}/`, `Infrastructure/Persistence/`. Each project has its own `DependencyInjection.cs`. Tests mirror the feature structure.

Domain is organized by **aggregate**: one folder per aggregate named for the entity (`Domain/{Entity}/`, e.g. `Domain/Order/`) directly under `Domain/`, one file per class/enum. The aggregate root lives in `{Entity}Aggregate.cs` as class `{Entity}Aggregate`; the namespace is `...Domain.{Entity}`. The `Aggregate` suffix on the root type avoids the type-vs-namespace collision — type `OrderAggregate` in namespace `...Domain.Order` (no namespace segment matches the type name).

> See `.claude/docs/folder-structure.md` for the full directory tree and file naming patterns.

### Solution Layout

The **4-project** split (`Api`/`Worker` + `Application` + `Domain` + `Infrastructure`) is the
default. Two collapsed layouts are also supported for smaller services:

- **2-project** — `{Host}` (Api or Worker) + a single `Core` library holding
  `Application`/`Domain`/`Infrastructure` as folders.
- **1-project** — everything in one `{App}` project, layers as folders.

**In every layout the folders, namespaces, and DI methods stay the same** — only the assembly
count changes. Invariants that must survive a collapse:

- Keep the namespaces (`...Application.Common`, `...Domain.{Entity}` with the `{Entity}Aggregate`
  suffix). Namespaces are assembly-independent, so they do not change.
- Keep `AddApplicationServices()` and `AddInfrastructureServices()` as **separate** DI methods
  even inside one assembly — the split-DI rule below applies regardless of project count.
- Keep the folder discipline: interfaces in `Application/Common/Interfaces/`, implementations
  in `Infrastructure/Services/` (and `Persistence/`).

The only thing a collapse loses is **compile-time** enforcement of the layer-seam rules (no
vendor types in Application/Domain; depend on the seam, not the concrete client) — they become
convention-only. Choose the 4-project layout when that enforcement matters. Pick the matching
Dockerfile per layout (see `.claude/docs/ci-cd-docker.md`).

> See `.claude/docs/folder-structure.md` for the 2-project and 1-project directory trees.

### Configuration & Middleware

- `global.json` pins to .NET 10 SDK with `rollForward: latestFeature` — copy from `.claude/templates/global.json` (bump `version` to your installed 10.0.x SDK; `latestFeature` then allows same-major feature-band roll-forward)
- `.editorconfig` enforces file-scoped namespaces, primary constructors, and `var` instead of explicit types — copy from `.claude/templates/dotnet.editorconfig`
- `Directory.Build.props` at the repo root centralizes `<Nullable>enable</Nullable>`, `LangVersion`, `ImplicitUsings`, and `EnforceCodeStyleInBuild` (makes `.editorconfig` style rules fail the build) — copy from `.claude/templates/Directory.Build.props`
- `Directory.Packages.props` at the repo root enables Central Package Management — all package versions live here (projects reference packages without a `Version`), including the pinned `MediatR 12.5.0` and `StronglyTypedId 1.0.0-beta08`. Copy from `.claude/templates/Directory.Packages.props`
- `CancellationToken` parameters are always named `ct`
- DI registration: `AddApplicationServices()` + `AddInfrastructureServices()` + `AddApiServices()`
- Middleware ordering is strict: Serilog → ExceptionHandler → Auth → FastEndpoints → HealthChecks → Scalar (dev only)
- **Scalar must use** `OpenApiRoutePattern = "/swagger/{documentName}/swagger.json"` — FastEndpoints does not use the ASP.NET default `/openapi/v1.json`
- Connection string key: `ConnectionStrings:DefaultConnection`
- Serilog configured entirely in `appsettings.json` — no C# config beyond `ReadFrom.Configuration()`

> See `.claude/docs/configuration.md` for Program.cs, appsettings.json, DI registration, and health check setup code.

### Interfaces

- `IApplicationDbContext` — `DbSet<T>` per entity + `SaveChangesAsync`. Scoped. Handlers depend on this, never `AppDbContext`.
- `IDateTimeProvider` — `DateTimeOffset UtcNow`. Singleton. Never call `DateTimeOffset.UtcNow` directly.
- `IUserSession` — `UserId`, `Email`, `DisplayName`, `Roles`, `IsAuthenticated`. Scoped. Maps from Entra ID JWT claims.

> See `.claude/docs/interfaces.md` for full interface definitions and claim mappings.

### Aggregates & Encapsulation

- Model the domain as **aggregates**; mark roots with the `IAggregateRoot` marker interface (`Domain/Common/`). Other aggregates reference a root **by id, never by object reference**.
- **No anemic domains.** State changes go through the aggregate root: properties are `{ get; private set; }` (or `init` for set-once data) — **no public setters**. Mutate via intent-revealing methods (`order.AddLine(...)`, `session.End()`), not property assignment.
- Methods that can break an invariant return `Ardalis.Result` — `Result.Conflict(...)` for state/transition violations (→ 409), `Result.Invalid(...)` (→ 400). Throw only for true programming errors, never for expected rule violations.
- Expose collections as `IReadOnlyList<T>`/`IReadOnlyCollection<T>`; mutate only through root methods. Construction goes through a constructor/factory yielding a valid root, plus a `private`/`protected` parameterless ctor for the ORM.
- Reference/lookup data that is only ever read may stay a plain data holder — don't manufacture behavior for genuinely read-only models.

> See `.claude/docs/domain-entities.md` for the `IAggregateRoot` marker and a rich aggregate-root example.

### Entity & Audit Conventions

- Entities inherit `AuditableEntity` (no `Id` property — each entity defines its own strongly typed ID)
- `AppDbContext.SaveChangesAsync` auto-populates audit fields — handlers never set them manually
- Strongly typed IDs use `[StronglyTypedId] public partial struct` — generates `New()`, `Empty`, JSON converter, equality
- IDs serialize as **flat Guid strings** in JSON — never `{ "value": "..." }`. No manual converter registration needed.
- EF Core value conversions must be configured manually in `IEntityTypeConfiguration<T>`
- Specifications live in `Domain/{Entity}/Specifications/`, named `{Entity}By{Filter}Spec`. Use `WithSpecification()` against `DbSet<T>` — no repositories.

> See `.claude/docs/domain-entities.md` for AuditableEntity, entity examples, StronglyTypedId, EF conversion, and specification code.

### Enumerations

- Domain enums use a hand-rolled `Enumeration` base class in `Domain/Common/` — no external dependency
- Subclasses inherit `Enumeration(int id, string name)` with `public static readonly` members and a private constructor
- Built-in: `GetAll<T>()`, `FromId<T>(int)`, `FromName<T>(string)`
- Located in the aggregate folder `Domain/{Entity}/`
- EF Core value conversions configured manually in `IEntityTypeConfiguration<T>` — store by `Id` (int)
- Support behavior via methods/properties on the subclass (e.g. state transition validation)

> See `.claude/docs/domain-entities.md` for Enumeration base class and usage examples.

### Responses, Mapping & Vertical Slices

- Response records are positional records using strongly typed IDs
- Mapping uses **manual static extension methods** co-located with the feature — no AutoMapper/Mapperly/Mapster
- DTOs follow three tiers: Tier 1 (co-located per endpoint), Tier 2 (`Features/{Feature}/Dtos/`), Tier 3 (`Application/Common/Dtos/`)
- **Each request file in Core contains the record, `Handler` inner class, and `Validator` inner class — never a separate top-level handler class**
- Validators inherit `AbstractValidator<T>` (pure FluentValidation, not `FastEndpoints.Validator<T>`) — always use `.WithMessage()` on each rule
- For endpoints that use a **separate request type** (not the command/query directly), also add a standalone `Validator<TRequest>` in `Api/Endpoints/` for HTTP-level validation of the request record
- Pagination: offset-based, default 20, max 100. Return `ApiResponse<PagedResponse<T>>`

> See `.claude/docs/responses-and-mapping.md` for response records, mapping extensions, DTO tiers, vertical slice, and pagination code.

### API Response Pattern

- All endpoints return `ApiResponse<T>` envelope — never raw DTOs
- `ResultExtensions.ToApiResponse()` and `.ToHttpStatusCode()` map `Ardalis.Result<T>` — never inline the switch
- Supported result statuses: `Ok` (200), `NotFound` (404), `Invalid` (400), `Conflict` (409) — use `Result.Conflict()` for state transition violations
- **Ambiguous `ValidationError`**: fully qualify `{Namespace}.Application.Common.Models.ValidationError` in `ResultExtensions.cs` (replace `{Namespace}` with the project's root namespace)
- FastEndpoints validation override returns `ApiResponse<object>` on failure (configured in `UseFastEndpoints()`)
- `GlobalExceptionHandlerMiddleware` returns generic error — never leaks stack traces
- Body-less POST commands use `EndpointWithoutRequest<TResponse>` to avoid `TypeInitializationException`

> See `.claude/docs/api-response-pattern.md` for ApiResponse definition, ResultExtensions, validation override, endpoint examples, and body-less POST.

### FastEndpoints — Response Send Methods

In FastEndpoints v7+, response methods are accessed via the **`Send` property** on the endpoint — **not** as direct instance methods like `SendAsync()` or `SendOkAsync()`.

Use `Endpoint<TRequest, TResponse>` (with explicit response type) so `Send` is strongly typed:

```csharp
public class MyEndpoint : Endpoint<MyRequest, MyResponse>
{
    public override async Task HandleAsync(MyRequest req, CancellationToken ct)
    {
        await Send.OkAsync(new MyResponse { ... }, ct);
    }
}
```

| Method | HTTP Status | Use Case |
|---|---|---|
| `Send.OkAsync(response, ct)` | 200 | GET, PUT, DELETE success |
| `Send.ResponseAsync(response, statusCode, ct)` | Any | Custom status code (e.g. 201 for creation) |
| `Send.NoContentAsync(ct)` | 204 | DELETE with no body |
| `Send.NotFoundAsync(ct)` | 404 | Resource not found |
| `Send.ErrorsAsync(statusCode, ct)` | 400/422 | After calling `AddError()` |

- `Send.CreatedAtAsync()` expects a route URL as the first argument. For simple 201 responses, use `Send.ResponseAsync(response, 201, ct)`.
- **Never** use `HttpContext.Response.WriteAsJsonAsync()` or `HttpContext.Response.SendAsync()` — always use `Send.*`.

### Authentication & Authorization

- Resource server only — validates Entra ID JWT bearer tokens, never handles login flows
- Authorization uses **Entra ID app roles** via policies — never check raw claims/roles directly
- All endpoints authenticated by default. `AllowAnonymous()` only for health checks and OpenAPI.
- Authorization belongs in the endpoint `Configure()` — MediatR handlers never perform auth checks.

> See `.claude/docs/auth-and-security.md` for JWT bearer config, policy definitions, and endpoint authorization code.

### API Routes

- Routes are unversioned: `/resource` (e.g., `/products`) — no `/api/` and no `/v{n}/` prefix
- Do not version in the URL path; if versioning is ever needed, prefer header/media-type negotiation

### Logging — Serilog

- Configured entirely in `appsettings.json`. Sinks: Console + Seq.
- Use `Serilog.Log.ForContext<T>()` as a static field — never inject `ILogger<T>`
- Structured log templates: `Log.Information("Created {ProductId}", id)` — never string interpolation
- Log levels: `Information` for success, `Warning` for expected failures, `Error` for unhandled exceptions
- `/health` paths logged at `Verbose` to suppress probe noise

### Resilience & Caching

- External HTTP calls use `AddStandardResilienceHandler()` (Polly v8) — retry, circuit breaker, timeout
- Response caching uses `IMemoryCache` with configurable TTL — decorator over the raw client
- Handlers inject the cached interface, never the raw client

> See `.claude/docs/resilience-and-caching.md` for HttpClient resilience and caching code.

### Testing

- **xUnit** + **Shouldly** (never `Assert.*`) + **NSubstitute** (never Moq/FakeItEasy)
- **Testcontainers** with real SQL Server — never SQLite or EF InMemory
- **Respawn v7+** — uses `DbConnection` (not connection strings) for `CreateAsync`/`ResetAsync`
- **MsSqlBuilder** — pass image as constructor parameter: `new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest")`
- Test naming: `{MethodUnderTest}_Should_{ExpectedBehavior}_When_{Condition}`
- Integration tests use `WebApplicationFactory<Program>` with `FakeAuthHandler` + `FakeUserSession`

> See `.claude/docs/testing.md` for assertion/mocking examples, auth bypass, Testcontainers, Respawn, and HttpClient extensions.

### CI/CD & Docker

- GitHub Actions + Azure Pipelines with identical behavior
- Push/PR to `main`: build + test. Semantic version tag: build + test + Docker push to `ghcr.io`
- `Dockerfile`: multi-stage build, `ARG VERSION=1.0.0` for assembly versioning
- `docker-compose.yml`: API + SQL Server + Seq for local development
- **`.gitignore`**: copy from `.claude/templates/dotnet-docker.gitignore`. Ignores build output, secrets, and `.env*` (keeps `.env.example`); **commits** `global.json`, `.editorconfig`, `Directory.Build.props`, `Directory.Packages.props`, `Dockerfile`, `docker-compose.yml`, `.env.example`, `appsettings.json`, `appsettings.Development.json`, and EF migrations.

> See `.claude/docs/ci-cd-docker.md` for pipeline definitions, Docker, and docker-compose details.

---

## Coding Patterns

- **Endpoints** live in `Api/Endpoints/` — inject `ISender`, call MediatR, use `ResultExtensions`. No business logic.
- **Handlers** are **always** inner classes named `Handler` inside the request record — never a separate top-level class. Depend on `IApplicationDbContext`, `IDateTimeProvider`, `IUserSession`. Return `Ardalis.Result<T>` — never throw for expected failures.
- **Validators** are inner classes of the request record inheriting `AbstractValidator<T>` (pure FluentValidation). Registered via `AddValidatorsFromAssembly` and validated by both the MediatR `ValidationBehavior` (for all callers) and FastEndpoints (for HTTP requests). Always use `.WithMessage()`. For endpoints with a separate request type, also add a standalone `Validator<TRequest>` in `Api/Endpoints/`.
- **Result mapping**: Use `result.ToApiResponse()` and `result.ToHttpStatusCode()` — never inline the switch.
- **EF Core**: Use `IQueryable` projections (`.Select()`) for reads — avoid loading full entities for GET operations.
- **No repositories**. Inject `IApplicationDbContext` directly. The DbContext *is* the unit of work.
- **Records** are preferred for requests, responses, and value objects.
- **Aggregates own their invariants.** Mutate domain state only through methods on the aggregate root (private setters, read-only collections). Handlers load the root, call one method, persist — they never re-implement business rules or reach into the root's state.
- **Enumerations over raw enums** for domain concepts. Request DTOs accept the enumeration `Name` as a string and map at the boundary via `Enumeration.TryFromName<T>` (400 on miss); never bind an `Enumeration` directly from JSON.

---

## Code Style

- Use **file-scoped namespaces**
- Use **primary constructors** where appropriate
- Use **nullable reference types** (`<Nullable>enable</Nullable>`) — set once in `Directory.Build.props` (see `.claude/templates/`)
- Prefer **var** instead of explicit types for local variables
- Prefer **expression-bodied members** for simple methods/properties
- Keep methods short — if a handler grows beyond ~40 lines, extract private methods or domain services
- No `#region` blocks
- Use `sealed` on classes that are not designed for inheritance
- Use `CancellationToken` named `ct` in all async methods
- All control flow statements (`if`, `else`, `for`, `foreach`, `while`, `do`) must always have braces — no single-line bodies

---

## When Creating a New Feature

1. Create request record (Command or Query) in `Application/Features/{Feature}/{Action}{Entity}/`
2. Add the `Handler` inner class with business logic returning `Result<T>`
3. Add the `Validator` inner class inheriting `AbstractValidator<T>` (FluentValidation) with rules and `.WithMessage()` on each rule. If the endpoint uses a separate request type from the command/query, also add a standalone `Validator<TRequest>` in `Api/Endpoints/{Feature}/`
4. Add the response record (positional record with strongly typed IDs)
5. Add manual mapping extension methods co-located with the feature
6. Add the FastEndpoints endpoint in `Api/Endpoints/{Feature}/`
7. Endpoint injects `ISender`, sends request, uses `result.ToApiResponse()` + `result.ToHttpStatusCode()`. Include `Summary()`, `Tags()`, example request, and response documentation.
8. Add tests using Shouldly assertions and NSubstitute mocks

---

## Do NOT

> This list is deliberately limited to **counterintuitive gotchas, version pins, and
> library-specific rules**. The positive conventions above (use `IApplicationDbContext`,
> `IDateTimeProvider`, `IUserSession`; `Handler`/`Validator` as inner classes; no anemic
> domains; Serilog `ForContext`; policies over raw claims; etc.) are the source of truth —
> not repeated here.

- Do not set audit fields (`CreatedBy`, `CreatedAt`, `ModifiedBy`, `ModifiedAt`) manually — the DbContext handles this automatically
- Do not serialize strongly typed IDs as `{ "value": "..." }` — the `StronglyTypedId` source generator handles flat Guid serialization automatically
- Do not manually register JSON converters for strongly typed IDs — the `[JsonConverter]` attribute on the generated struct is discovered automatically by System.Text.Json
- Do not define strongly typed IDs as `readonly record struct` manually — use `[StronglyTypedId] public partial struct`
- Do not create repository or generic repository abstractions — apply specifications directly against `DbSet<T>` via `WithSpecification()`
- Do not use any third-party mapping libraries (no AutoMapper, no Mapperly, no Mapster) — use manual extension methods only
- Do not leak exception details to clients — return generic error message in production
- Do not hardcode tenant ID, client ID, or any Entra ID config — use `appsettings.json` / environment variables
- Do not implement login/token flows in the API — it is a resource server that validates incoming tokens only
- Do not use `/api/` prefix or `/v{n}/` version prefix in routes — use plain `/resource` pattern
- Do not use Swashbuckle or Swagger UI — use `FastEndpoints.Swagger` (NSwag-based) + Scalar
- Do not create endpoints without a `Summary()` block — every endpoint must document itself for OpenAPI
- Do not expose Scalar or OpenAPI endpoints in production
- Do not use `SendAsync()`, `SendOkAsync()`, `SendCreatedAtAsync()`, or `HttpContext.Response.WriteAsJsonAsync()` in FastEndpoints — use `Send.OkAsync()`, `Send.ResponseAsync()`, `Send.NotFoundAsync()`, `Send.ErrorsAsync()` via the `Send` property
- Do not place domain types under `Domain/Entities/{Entity}/` — use `Domain/{Entity}/` (one folder per aggregate named for the entity, one file per class/enum; root is `{Entity}Aggregate.cs`)
- Do not use SQLite or EF InMemory for integration tests — always use Testcontainers with real SQL Server
- Do not use `Assert.*` from xUnit — use Shouldly
- Do not use Moq, FakeItEasy, or any other mocking library — use NSubstitute
- Do not pass connection strings to Respawn `CreateAsync`/`ResetAsync` — Respawn v7 requires `DbConnection` (use `new SqlConnection(connectionString)`)
- Do not use the parameterless `MsSqlBuilder()` constructor — pass the image as a constructor parameter: `new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest")`
- Do not upgrade MediatR beyond `12.5.0` — v13+ is commercially licensed. Pin to `12.5.0` (last Apache 2.0 version) in `Directory.Packages.props`
- Do not hardcode assembly version in health check responses — use `Assembly.GetEntryAssembly()?.GetName().Version` which is set at build time via Docker `VERSION` arg
- Do not use `FastEndpoints.Validator<T>` in Core/Application layer commands or queries — use `AbstractValidator<T>` from FluentValidation directly; `FastEndpoints.Validator<T>` is only for standalone endpoint request validators in the API layer
- Do not add inline `Result.Invalid()` format guards in handlers when a MediatR `ValidationBehavior` and FluentValidation validator already cover the same check — the behavior fires before the handler and the guard is dead code
- Do not use raw C# `enum` types for domain concepts — use the `Enumeration` base class
- Do not store Enumeration instances by name in the database — store by `Id` (int)
- Do not access `.Id` or `.Name` on Enumeration properties in EF Core LINQ queries (e.g. `OrderBy(x => x.Status.Id)`) — use the property directly (`OrderBy(x => x.Status)`), EF Core applies the value conversion automatically
- Do not use `Result.Invalid()` for state transition or business rule conflicts — use `Result.Conflict()` (maps to 409)
- Do not use `HasValueGenerator<T>()` on StronglyTypedId properties — it prevents EF Core from marking the property as `ValueGenerated.OnAdd` in some environments, causing "temporary value" exceptions at runtime that Testcontainers won't catch. Use `ValueGeneratedOnAdd()` instead
- Do not configure int-backed StronglyTypedId properties without `ValueGeneratedOnAdd()` + `UseIdentityColumn()` + `ValueComparer<TId>` — without all three, EF Core assigns `Id(0)` to every new entity and the change tracker throws a tracking conflict when adding multiple entities
- Do not configure a single `ValidIssuer` for Entra ID — set `ValidIssuers` to accept both v1.0 (`sts.windows.net/{tenantId}/`) and v2.0 (`login.microsoftonline.com/{tenantId}/v2.0`) formats, since the issuing endpoint depends on `accessTokenAcceptedVersion` in the app registration manifest
- Do not set `RoleClaimType = "roles"` in JWT bearer options — the v1.0 JWT handler auto-maps the `roles` claim to `ClaimTypes.Role`, so the default `RoleClaimType` already matches. Setting it to `"roles"` breaks `IsInRole` checks
- Do not inject a persistence vendor's client (`IDocumentStore`, `IMongoClient`, a concrete `DbContext`) into MediatR handlers — depend on a layer-owned seam (`IApplicationDbContext` for EF, a thin session interface for document stores). No repositories, but no raw client either
- Do not call a static Infrastructure helper (e.g. a static PDF/file extractor) directly from a handler — put it behind an `Application`-owned interface so the handler is unit-testable
- Do not re-implement store conventions (collection/table names, id format, registered indexes) in test setup — share one `ApplyConventions`-style method between the production and integration-test stores
- Do not register the persistence store, MediatR, and hosted services in one combined DI extension — split infrastructure registration (`AddInfrastructureServices()`) from application registration. This holds **regardless of project count** — keep the methods separate even in a collapsed 1- or 2-project layout where they live in the same assembly

---

## Infrastructure Layer

The Infrastructure folder/project owns every concrete dependency on an external system — the persistence client (EF `DbContext`, RavenDB `IDocumentStore`), schema-shaping (EF `IEntityTypeConfiguration<T>`, RavenDB `AbstractIndexCreationTask<T>`), data seeding (`IHostedService`), and external-tool wrappers (PDF/file/HTTP). Nothing in `Application/` or `Domain/` may reference a persistence vendor's types except through an abstraction those layers own.

- **Persistence seam.** Handlers depend on a data abstraction defined in the consuming layer, not on a concrete client. For EF Core that seam is `IApplicationDbContext` (the DbContext *is* the unit of work — no repositories on top). For a document database, define the **same** `IApplicationDbContext` interface in `Application/Common/` and implement it in Infrastructure over the document session — do **not** inject the raw `IDocumentStore` / `IMongoClient` into handlers, and do **not** add a generic repository either. The rule is "one layer-owned seam": between a vendor repository (too much) and a raw client (too little).
  - Register the document-DB context **scoped** so one session = one unit of work per request; the underlying store/client stays a singleton, seen only by Infrastructure (seeding, index creation). The interface may expose the store's native query types (e.g. RavenDB `IRavenQueryable<T>` / `IAsyncDocumentQuery<T>`) exactly as the EF seam exposes `DbSet<T>`.
  - Put cross-cutting load logic (e.g. an id-prefix fallback, derived from the collection-naming convention rather than hardcoded per type) **on the seam**, so handlers call one `LoadAsync<T>(id)` instead of repeating it. Bulk-insert helpers on the seam should be documented as bypassing the unit of work.
- **Static infrastructure helpers** that a handler invokes (PDF extraction, parsing, hashing) sit behind an interface declared in `Application/Common/Interfaces/` and implemented in Infrastructure — never call a static Infrastructure class from a handler, so the handler stays unit-testable.
- **Shared store conventions.** Conventions that shape stored data (id separators, collection/table naming, registered indexes) live in one method in Infrastructure and are applied identically by the production store and the integration-test store — tests must never re-derive naming/id rules.
- **DI registration is split by layer**: `AddInfrastructureServices()` registers the store, external clients, and hosted services; application wiring (MediatR, validators) is registered separately. Do not bundle store + MediatR + hosted services into a single catch-all extension. The split is by **method**, not by assembly — it stays in force in a collapsed 1- or 2-project layout.

---

## Database & Migrations

- SQL Server via EF Core
- Connection string key: `ConnectionStrings:DefaultConnection`
- Migrations live in `Infrastructure/Persistence/Migrations/`
- Entity configurations use `IEntityTypeConfiguration<T>` in `Infrastructure/Persistence/Configurations/`
- Use `dotnet ef migrations add <n>` and `dotnet ef database update`
