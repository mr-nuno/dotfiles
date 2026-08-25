# Responses, Mapping & Vertical Slices

## Response Record Convention

Response records are positional records using the strongly typed ID:

```csharp
public sealed record CreateProductResponse(
    ProductId Id,
    string Name,
    decimal Price);
```

- Always use strongly typed IDs in response records (the JSON converter handles flat serialization).
- Keep response records flat — avoid nesting unless representing a clear sub-object.

## Mapping — Manual Extension Methods

All mapping is done via **manual static extension methods** — no third-party mapping libraries.

Mapping extensions live co-located with the feature:

```csharp
namespace Application.Features.Products.CreateProduct;

public static class CreateProductMappingExtensions
{
    public static CreateProductResponse ToResponse(this Product product) => new(
        product.Id,
        product.Name,
        product.Price);
}
```

- One mapping extension class per feature action
- Methods are named `ToResponse()`, `ToDto()`, or `ToEntity()` as appropriate
- Keep mappings as simple extension methods — no abstraction, no interfaces, no base classes
- For projections in read queries, prefer inline `.Select()` expressions over extension methods

## DTO Placement — Three Tiers

**Tier 1 — Feature-action response records** (most common)

Response records unique to a single endpoint. Co-located with the feature action:

```
Application/Features/Games/CreateGame/CreateGameResponse.cs
Application/Features/Games/GetGame/GetGameResponse.cs
```

- Each endpoint defines its own response shape
- This is the default — use this unless the same shape is needed by multiple endpoints

**Tier 2 — Shared DTOs within a feature**

DTOs reused across multiple endpoints in the same feature. Live in a `Dtos/` folder under the feature:

```
Application/Features/Games/Dtos/BoardSquareDto.cs
Application/Features/Games/Dtos/MoveDto.cs
```

- Use when 2+ endpoints in the same feature return the identical shape
- Named `{Concept}Dto` — defined as positional records

**Tier 3 — Cross-feature DTOs** (rare)

DTOs shared across different features. Live in `Application/Common/Dtos/`:

- Only use when the shape genuinely represents a cross-cutting concept (e.g., `AddressDto`)

**Rule of thumb:**

- Unique to one endpoint? -> Tier 1 (co-located)
- Reused in same feature? -> Tier 2 (`Features/{Feature}/Dtos/`)
- Reused across features? -> Tier 3 (`Application/Common/Dtos/`)

## Vertical Slice — Feature File Structure

Each request file (Command/Query) contains the request record, the MediatR handler, and the validator as **inner classes**:

```csharp
using FluentValidation;

namespace Application.Features.Products.CreateProduct;

public sealed record CreateProductCommand(string Name, decimal Price) : IRequest<Result<CreateProductResponse>>
{
    public sealed class Handler(
        IApplicationDbContext db,
        IDateTimeProvider dateTime) : IRequestHandler<CreateProductCommand, Result<CreateProductResponse>>
    {
        private static readonly ILogger Log = Serilog.Log.ForContext<Handler>();

        public async Task<Result<CreateProductResponse>> Handle(CreateProductCommand request, CancellationToken ct)
        {
            var product = new Product(ProductId.New(), request.Name, request.Price);
            db.Products.Add(product);
            await db.SaveChangesAsync(ct);

            Log.Information("Created product {ProductId}", product.Id);
            return Result.Success(product.ToResponse());
        }
    }

    public sealed class Validator : AbstractValidator<CreateProductCommand>
    {
        public Validator()
        {
            RuleFor(x => x.Name).NotEmpty().WithMessage("Product name is required");
            RuleFor(x => x.Price).GreaterThan(0).WithMessage("Price must be greater than zero");
        }
    }
}
```

## Pagination

```csharp
public sealed record PagedRequest(int Page = 1, int PageSize = 20);

public sealed record PagedResponse<T>(
    List<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
}
```

- Offset-based pagination (not cursor-based)
- Default page size is 20, max page size is 100
- Paginated endpoints return `ApiResponse<PagedResponse<T>>`
- Queries accept `PagedRequest` properties as query string parameters
- Apply `.Skip()` / `.Take()` in the handler or specification
