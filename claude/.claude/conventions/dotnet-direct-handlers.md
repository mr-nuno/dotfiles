# .NET Web API Conventions — Direct Handlers (alternative)

**Read `.claude/conventions/dotnet.md` first.** This file is a delta: it replaces only the
dispatch layer. Everything not mentioned here (layout, `ApiResponse<T>`, `IApplicationDbContext`,
Vogen IDs, aggregates, specifications, Serilog, auth, testing stack, Do-NOT list) applies unchanged.

FastEndpoints endpoints inject a plain handler class and call it. No Mediator, no `ISender`, no
pipeline behaviors. "Go to definition" on the handler call lands on the logic, and the handler's
constructor lists everything the slice touches.

## When to choose it

- **Choose direct handlers** when HTTP is the main entry point and conventions can be held by
  architecture tests and review.
- **Keep Mediator (the default)** when many entry points (HTTP, gRPC, queue consumers, jobs) need
  identical cross-cutting behavior, or a large team needs a pipeline to force consistency.

## Opt-in

A project opts in with one line in its project-level `CLAUDE.md`:

```markdown
Dispatch: direct handlers (see ~/.claude/conventions/dotnet-direct-handlers.md)
```

Without that line, the Mediator conventions in `dotnet.md` apply.

## Bootstrap delta

In addition to the `dotnet.md` bootstrap steps, copy from `.claude/templates/`:

| Template | Destination |
|---|---|
| `direct-handlers-IHandler.cs` | `Application/Common/Handlers/IHandler.cs` |
| `direct-handlers-decorators.cs` | `Application/Common/Handlers/HandlerDecorators.cs` |
| `direct-handlers-architecture-tests.cs` | `tests/Architecture.Tests/ArchitectureTests.cs` |

Replace `{Namespace}` (and `{ApplicationType}` in the arch tests). There is no
`Application/Common/Behaviors/` folder.

## Tech stack delta

- **Remove** `Mediator.Abstractions` and `Mediator.SourceGenerator`.
- **Add** `Scrutor` — scans handlers into DI and applies decorators.
- **Add** `NetArchTest.Rules` — architecture tests (test project only).

Both are already listed in `templates/Directory.Packages.props` under "Direct-handlers variant only".

## Coding patterns (replaces the Endpoints / Requests / Handlers / Validators bullets)

- **Requests** are plain records named `...Command` (writes) or `...Query` (reads). They implement
  nothing.
- **Handlers** stay an **inner class named `Handler`** of the request record and implement
  `IHandler<TRequest, TValue>`, returning `ValueTask<Result<TValue>>`. The shape matches the
  Mediator variant, so moving a slice between the two variants is mechanical. Dependencies are
  the same: `IApplicationDbContext`, `IDateTimeProvider`, `IUserSession`.
- **Endpoints** inject the **concrete** handler (`CreateOrderCommand.Handler`), call `Handle`, and
  map with `result.ToApiResponse()` + `result.ToHttpStatusCode()`. `HandleAsync` is about two lines.
  When the endpoint has its own request type, map it with a `ToCommand()` method on the request.
- **Handlers never inject another handler.** Slices never reference each other. Shared behavior
  goes on the aggregate, a domain service, or a domain event.
- **Trivial reads**: a GET that is one projection with no decision may query
  `IApplicationDbContext` directly in the endpoint. Add a handler as soon as it needs a testable
  decision or a second caller.
- **Transactions**: one `SaveChangesAsync` per handler. When a handler needs more (several saves,
  an outbox write), it opens `BeginTransactionAsync(ct)` itself, where readers can see it.

> See `.claude/docs/direct-handlers.md` for the full slice, DI registration and decorator code.

## Validation (replaces the Mediator `ValidationBehavior`)

- The inner `Validator : AbstractValidator<T>` stays, with `.WithMessage()` on every rule.
- **HTTP**: the endpoint declares it in `Configure()` with `Validator<CreateOrderCommand.Validator>()`.
  FastEndpoints does **not** discover an inner `AbstractValidator<T>` on its own; without that
  line the request is never validated. For a separate endpoint request type, a standalone
  `Validator<TRequest>` in `Api/Endpoints/` still works as in `dotnet.md`.
- **Non-HTTP callers** (jobs, consumers) inject `IHandler<TRequest, TValue>` and get
  `ValidationDecorator`, which returns `Result.Invalid(...)`.
- Validators check **shape** only and never query the database.

| Rule type | Where | Mechanism | Example |
|---|---|---|---|
| Shape | Validator | FluentValidation | Required field, email format, quantity > 0 |
| State | Handler | `Result.NotFound()` / `Result.Conflict()` / `Result.Invalid()` | SKU doesn't exist, order already shipped |
| Invariant | Aggregate | Method returns `Result`, as in `dotnet.md` | Order must have at least one line |

## Cross-cutting concerns

| Concern | Mechanism | Applies to |
|---|---|---|
| Request validation | `Validator<T>()` in `Configure()` | HTTP |
| Logging, timing, auditing | FastEndpoints global pre/post processors | HTTP |
| Per-endpoint behavior | `PreProcessor<T>()` / `PostProcessor<T>()` in `Configure()` | HTTP |
| Behavior shared with jobs and consumers | Scrutor decorator on `IHandler<,>` | Callers of the interface |
| In-process notifications | FastEndpoints events, or domain events from a `SaveChanges` interceptor | Any |

Decorators wrap only calls made through `IHandler<,>`. Endpoints inject the concrete type and are
**not** decorated, so HTTP gets its cross-cutting behavior from FastEndpoints.

## Testing delta

On top of the `dotnet.md` test layers, add a **handler test** layer:

| Layer | Tests | Database | Asserts on |
|---|---|---|---|
| Unit | Aggregates, value objects, specifications | None | Rules and invariants |
| Handler | One `Handler`, constructed directly | Testcontainers SQL Server, Respawn reset | `ResultStatus`, returned value, persisted state |
| Integration | Endpoint over HTTP | Same container | Routing, auth, validation, serialization, status codes |
| Architecture | Assembly rules | None | The Do-NOT rules below |

- Handler tests never touch HTTP. Endpoint tests do not re-test business rules the handler tests cover.
- Per slice: one handler test per meaningful `Result` branch, and a few endpoint tests (happy path,
  one validation failure, one auth failure).

## Do NOT (delta)

These `dotnet.md` Do-NOT bullets **do not apply** (Mediator-only): Mediator `ServiceLifetime`,
`options.PipelineBehaviors`, single `Mediator.SourceGenerator` reference, generic requests, and
"`ValidationBehavior` already covers it". The MediatR licensing rule still applies.

Additional rules for this variant:

- Do not inject one handler into another — move the shared behavior to the domain. *(arch test)*
- Do not reference FastEndpoints or `Microsoft.AspNetCore.Http` from `Application/`. *(arch test)*
- Do not reference one feature folder from another (`Features.Orders` → `Features.Customers`). *(arch test)*
- Do not add repositories over `IApplicationDbContext`. *(arch test)*
- Do not put business logic in an endpoint's `HandleAsync` — it maps, calls, sends.
- Do not query the database from a validator — state rules belong in the handler.
- Do not forget `Validator<T>()` in `Configure()` when the endpoint binds the command directly — FastEndpoints will silently skip validation.
- Do not inject `IHandler<,>` in an endpoint to "get" decorators — HTTP concerns belong in FastEndpoints processors. Inject the interface only from non-HTTP callers.
- Do not throw for expected failures — return a `Result`. Exceptions are for bugs and infrastructure faults.

## When creating a new feature

1. Create the request record (`...Command` / `...Query`, no interface) in `Application/Features/{Feature}/{Action}{Entity}/`.
2. Add the inner `Handler : IHandler<TRequest, TValue>` returning `ValueTask<Result<TValue>>`.
3. Add the inner `Validator : AbstractValidator<T>` with `.WithMessage()` on each rule.
4. Add the response record (positional, strongly typed IDs).
5. Add manual mapping extension methods co-located with the feature.
6. Add the FastEndpoints endpoint in `Api/Endpoints/{Feature}/`.
7. The endpoint injects `{Request}.Handler`, declares `Validator<{Request}.Validator>()`, calls `Handle`, and sends `result.ToApiResponse()` with `result.ToHttpStatusCode()`. Include `Summary()`, `Tags()` and response docs.
8. Add handler tests, endpoint tests, and keep the architecture tests green.
