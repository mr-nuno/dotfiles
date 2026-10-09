# Direct Handlers

Code reference for `.claude/conventions/dotnet-direct-handlers.md`. Everything here follows the
`dotnet.md` house rules (Vogen IDs, `IApplicationDbContext`, `ApiResponse<T>`, Serilog
`ForContext`, Shouldly). Only the dispatch layer differs from the Mediator variant.

## The handler contract

```csharp
namespace Application.Common.Handlers;

public interface IHandler<in TRequest, TValue>
{
    ValueTask<Result<TValue>> Handle(TRequest request, CancellationToken ct);
}
```

The second type parameter is the **value**, not the `Result`. Every handler returns
`Result<TValue>`, so a decorator can short-circuit with `Result<TValue>.Invalid(...)` without
knowing the value type. Template: `templates/direct-handlers-IHandler.cs`.

## A slice

`Application/Features/Orders/CreateOrder/CreateOrderCommand.cs`. Same file layout as the Mediator
variant: record, inner `Handler`, inner `Validator`.

```csharp
using FluentValidation;

namespace Application.Features.Orders.CreateOrder;

public sealed record CreateOrderCommand(CustomerId CustomerId, IReadOnlyList<OrderLineDto> Lines)
{
    public sealed class Handler(
        IApplicationDbContext db,
        IDateTimeProvider dateTime) : IHandler<CreateOrderCommand, CreateOrderResponse>
    {
        private static readonly ILogger Log = Serilog.Log.ForContext<Handler>();

        public async ValueTask<Result<CreateOrderResponse>> Handle(CreateOrderCommand request, CancellationToken ct)
        {
            if (!await db.Customers.AnyAsync(c => c.Id == request.CustomerId, ct))
            {
                return Result.NotFound("Customer not found");
            }

            var created = OrderAggregate.Create(request.CustomerId, request.Lines, dateTime.UtcNow);
            if (!created.IsSuccess)
            {
                return created.Map(o => o.ToResponse());
            }

            db.Orders.Add(created.Value);
            await db.SaveChangesAsync(ct);

            Log.Information("Created order {OrderId}", created.Value.Id);
            return Result.Success(created.Value.ToResponse());
        }
    }

    public sealed class Validator : AbstractValidator<CreateOrderCommand>
    {
        public Validator()
        {
            RuleFor(x => x.Lines).NotEmpty().WithMessage("An order needs at least one line");
            RuleForEach(x => x.Lines).ChildRules(line =>
                line.RuleFor(l => l.Quantity).GreaterThan(0).WithMessage("Quantity must be greater than zero"));
        }
    }
}
```

The handler loads, calls the aggregate, saves. The rule "order needs a line" lives on
`OrderAggregate.Create` as well as the validator: the validator rejects bad input early over
HTTP, the aggregate guards the invariant for every caller.

## The endpoint

`Api/Endpoints/Orders/CreateOrderEndpoint.cs`:

```csharp
namespace Api.Endpoints.Orders;

public sealed class CreateOrderEndpoint(CreateOrderCommand.Handler handler)
    : Endpoint<CreateOrderCommand, ApiResponse<CreateOrderResponse>>
{
    public override void Configure()
    {
        Post("/orders");
        Policies("CanCreateOrders");
        Validator<CreateOrderCommand.Validator>();
        Tags("Orders");
        Summary(s =>
        {
            s.Summary = "Create an order";
            s.Response<ApiResponse<CreateOrderResponse>>(201, "Order created");
            s.Response<ApiResponse<CreateOrderResponse>>(400, "Validation failed");
            s.Response<ApiResponse<CreateOrderResponse>>(404, "Customer not found");
        });
    }

    public override async Task HandleAsync(CreateOrderCommand req, CancellationToken ct)
    {
        var result = await handler.Handle(req, ct);
        await Send.ResponseAsync(result.ToApiResponse(), result.IsSuccess ? 201 : result.ToHttpStatusCode(), ct);
    }
}
```

- **`Validator<CreateOrderCommand.Validator>()` is required.** FastEndpoints only auto-discovers
  validators that inherit its own `Validator<TRequest>`; an inner `AbstractValidator<T>` is
  ignored unless declared here. (Verified against FastEndpoints 7.0.)
- The endpoint injects the **concrete** `Handler`, so no decorators run on the HTTP path.
- With a separate HTTP request type, add `public CreateOrderCommand ToCommand() => new(...)` on
  the request and call `handler.Handle(req.ToCommand(), ct)`.

## Registration

`Application/DependencyInjection.cs`. Replaces the Mediator registration in
`.claude/docs/configuration.md`; the split into `AddApplicationServices()` /
`AddInfrastructureServices()` stays.

```csharp
public static IServiceCollection AddApplicationServices(this IServiceCollection services)
{
    services.Scan(s => s.FromAssemblyOf<DependencyInjection>()
        .AddClasses(c => c.AssignableTo(typeof(IHandler<,>)).Where(t => !t.IsGenericTypeDefinition), publicOnly: true)
        .AsSelfWithInterfaces()
        .WithScopedLifetime());

    // Order matters: the last Decorate call is the outermost wrapper.
    services.Decorate(typeof(IHandler<,>), typeof(ValidationDecorator<,>));
    services.Decorate(typeof(IHandler<,>), typeof(LoggingDecorator<,>));

    services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);
    return services;
}
```

- **Scoped** so handlers share the request's `IApplicationDbContext`.
- `AsSelfWithInterfaces()` registers both `CreateOrderCommand.Handler` (for endpoints) and
  `IHandler<CreateOrderCommand, CreateOrderResponse>` (for other callers). `Decorate` wraps only
  the interface registration; resolving the concrete type returns the undecorated handler.
  (Verified with Scrutor 7.0.)
- The `!t.IsGenericTypeDefinition` filter keeps the open-generic decorators out of the scan;
  without it Scrutor registers them as services of their own type.
- In a collapsed 1-project layout use `FromAssemblyOf<Program>()`.

## Cross-cutting concerns

| Concern | Mechanism | Applies to |
|---|---|---|
| Request validation | `Validator<T>()` in `Configure()` | HTTP |
| Logging, timing, auditing | `IGlobalPreProcessor` / `IGlobalPostProcessor` | HTTP |
| Per-endpoint behavior | `PreProcessor<T>()` / `PostProcessor<T>()` in `Configure()` | HTTP |
| Behavior shared with jobs and consumers | Scrutor decorator on `IHandler<,>` | Callers of the interface |
| In-process notifications | FastEndpoints `IEvent` / `IEventHandler<T>`, or domain events from a `SaveChanges` interceptor | Any |
| Mediator-style dispatch with middleware | FastEndpoints command bus (`ICommand`, `ICommandHandler`) | Any — only when you really need it |

Decorators (template: `templates/direct-handlers-decorators.cs`):

- `ValidationDecorator<TRequest, TValue>` — runs every `IValidator<TRequest>` and returns
  `Result<TValue>.Invalid(...)` on failure.
- `LoggingDecorator<TRequest, TValue>` — logs the outcome with Serilog `ForContext`
  (`Information` for success, `Warning` for expected failures).

A job that should get them injects the interface:

```csharp
public sealed class ExpireOrdersJob(IHandler<ExpireOrdersCommand, int> handler) : BackgroundService
{
    // handler is LoggingDecorator -> ValidationDecorator -> ExpireOrdersCommand.Handler
}
```

`Serilog.ILogger` is fully qualified in the decorator template: in a Web SDK project
`ImplicitUsings` also imports `Microsoft.Extensions.Logging`, and a bare `ILogger` is ambiguous.

## Data access

- Handlers use `IApplicationDbContext` directly; specs from `Domain/{Entity}/Specifications/`
  are applied with `WithSpecification()` as in `dotnet.md`.
- Write a spec only when two or more slices share the rule. Projections to slice-specific
  responses stay inline in the handler.
- Writes: load the aggregate tracked, call one method, save. Reads: `AsNoTracking()` + `Select`.
- More than one save, or an outbox write: open `db.Database.BeginTransactionAsync(ct)` inside the
  handler (expose `Database` on `IApplicationDbContext` if the project needs it).

## Handler tests

Construct the `Handler` directly against the Testcontainers database. No HTTP, no DI pipeline.
Reuse the integration factory from `.claude/docs/testing.md` to get a scoped
`IApplicationDbContext`, and reset with Respawn between tests.

```csharp
[Collection("Database")]
public sealed class CreateOrderHandlerTests(IntegrationTestWebAppFactory factory)
{
    [Fact]
    public async Task Handle_Should_ReturnNotFound_When_CustomerMissing()
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<IApplicationDbContext>();
        var handler = new CreateOrderCommand.Handler(db, Substitute.For<IDateTimeProvider>());

        var result = await handler.Handle(
            new CreateOrderCommand(CustomerId.FromNewGuid(), [new OrderLineDto("SKU-1", 2)]),
            CancellationToken.None);

        result.Status.ShouldBe(ResultStatus.NotFound);
    }
}
```

- One handler test per meaningful `Result` branch; assert on `Status`, `Value`, and what was persisted.
- Endpoint tests cover routing, auth, validation wiring and serialization — not business rules.

## Architecture tests

Both variants share `templates/dotnet-architecture-tests.cs` (see `.claude/docs/testing.md`,
"Architecture Tests"): layer direction, nested `Handler`/`Validator`, no cross-feature references,
no repositories. Keep its **"Direct handlers only"** block and delete the Mediator one. That block
adds `Handlers_Should_NotInjectOtherHandlers_When_Constructed`: no handler constructor takes an
`IHandler<,>` or another nested `Handler`.

Review covers what the tests can't: logic in `HandleAsync`, database queries in validators,
specs written for a single slice, exceptions thrown for expected failures.
