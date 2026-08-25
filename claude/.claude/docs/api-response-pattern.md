# API Response Pattern

## ApiResponse<T> Envelope

All endpoints return a consistent `ApiResponse<T>` envelope:

```csharp
namespace Application.Common.Models;

public sealed record ApiResponse<T>
{
    public bool Success { get; init; }
    public T? Data { get; init; }
    public string? Error { get; init; }
    public List<ValidationError>? ValidationErrors { get; init; }
}

public sealed record ValidationError(string Property, string Message);
```

- **Success**: `ApiResponse<T> { Success = true, Data = result }`
- **Validation failure**: `ApiResponse<T> { Success = false, ValidationErrors = [...] }`
- **Error/Exception**: `ApiResponse<T> { Success = false, Error = "Something went wrong" }`
- **Not found**: `ApiResponse<T> { Success = false, Error = "Product not found" }`

Every endpoint wraps its response in `ApiResponse<T>`. No endpoint ever returns a raw DTO.

## Result -> ApiResponse Extension Method

The `Result<T>` to `ApiResponse<T>` mapping is done via a shared extension method in `Api/Extensions/ResultExtensions.cs`. Endpoints **never** contain the switch statement inline.

**Ambiguous `ValidationError`**: Both `Ardalis.Result` and `Application.Common.Models` define a `ValidationError` type. In `ResultExtensions.cs`, you **must** fully qualify `{Namespace}.Application.Common.Models.ValidationError` to avoid CS0104 (replace `{Namespace}` with the project's root namespace).

```csharp
namespace Api.Extensions;

public static class ResultExtensions
{
    public static ApiResponse<T> ToApiResponse<T>(this Result<T> result) => result.Status switch
    {
        ResultStatus.Ok => new ApiResponse<T> { Success = true, Data = result.Value },
        ResultStatus.NotFound => new ApiResponse<T> { Success = false, Error = result.Errors.FirstOrDefault() ?? "Not found" },
        ResultStatus.Invalid => new ApiResponse<T>
        {
            Success = false,
            ValidationErrors = result.ValidationErrors
                .Select(e => new {Namespace}.Application.Common.Models.ValidationError(e.Identifier, e.ErrorMessage))
                .ToList()
        },
        ResultStatus.Conflict => new ApiResponse<T> { Success = false, Error = result.Errors.FirstOrDefault() ?? "Conflict" },
        _ => new ApiResponse<T> { Success = false, Error = result.Errors.FirstOrDefault() ?? "An error occurred" }
    };

    public static int ToHttpStatusCode<T>(this Result<T> result) => result.Status switch
    {
        ResultStatus.Ok => 200,
        ResultStatus.NotFound => 404,
        ResultStatus.Invalid => 400,
        ResultStatus.Conflict => 409,
        _ => 500
    };
}
```

## FastEndpoints Validation -> ApiResponse Integration

FastEndpoints' built-in validation failure response must be overridden to return `ApiResponse<T>` instead of the default error format:

```csharp
app.UseFastEndpoints(c =>
{
    c.Errors.ResponseBuilder = (failures, ctx, statusCode) =>
    {
        return new ApiResponse<object>
        {
            Success = false,
            ValidationErrors = failures
                .Select(f => new ValidationError(f.PropertyName, f.ErrorMessage))
                .ToList()
        };
    };
    c.Errors.StatusCode = 400;
});
```

**Property-name casing.** `f.PropertyName` is **camelCased by FastEndpoints to match the serialized JSON field name** — a validator rule on a `Price` property surfaces as `Property == "price"`, not `"Price"`. This is intentional and correct: the client sees JSON field names, not C# property names. Tests asserting on `ValidationError.Property` must therefore compare **case-insensitively** (see `.claude/docs/testing.md`, "Integration Test HttpClient Pattern").

## Endpoint Examples

Endpoints are thin. They inject `ISender`, call MediatR, and use `ResultExtensions` to produce `ApiResponse<T>`:

```csharp
namespace Api.Endpoints.Products;

public sealed class CreateProductEndpoint(ISender sender)
    : Endpoint<CreateProductCommand, ApiResponse<CreateProductResponse>>
{
    public override void Configure()
    {
        Post("/products");
        Policies("CanCreateProducts");
        Tags("Products");
        Summary(s =>
        {
            s.Summary = "Create a new product";
            s.Description = "Creates a new product with the given name and price.";
            s.ExampleRequest = new CreateProductCommand("Widget", 9.99m);
            s.Response<ApiResponse<CreateProductResponse>>(201, "Product created successfully");
            s.Response<ApiResponse<CreateProductResponse>>(400, "Validation failed");
            s.Response<ApiResponse<CreateProductResponse>>(401, "Unauthorized");
        });
    }

    public override async Task HandleAsync(CreateProductCommand req, CancellationToken ct)
    {
        var result = await sender.Send(req, ct);
        await Send.ResponseAsync(result.ToApiResponse(), 201, ct);
    }
}
```

## Body-less POST Endpoints

When a POST command has **no request properties**, FastEndpoints' `RequestBinder` will throw a `TypeInitializationException`. Use `EndpointWithoutRequest<TResponse>` instead:

```csharp
public sealed class CreateGameEndpoint(ISender sender)
    : EndpointWithoutRequest<ApiResponse<CreateGameResponse>>
{
    public override void Configure()
    {
        Post("/games");
        Policies("CanManageGames");
        Tags("Games");
        Summary(s =>
        {
            s.Summary = "Create a new game";
            s.Response<ApiResponse<CreateGameResponse>>(201, "Game created successfully");
        });
    }

    public override async Task HandleAsync(CancellationToken ct)
    {
        var result = await sender.Send(new CreateGameCommand(), ct);
        await Send.ResponseAsync(result.ToApiResponse(), 201, ct);
    }
}
```

- Use `EndpointWithoutRequest<TResponse>` — not `Endpoint<TRequest, TResponse>` — when the command has no properties
- The handler signature is `HandleAsync(CancellationToken ct)` — no request parameter
- Create the command inline in the handler

## Global Error Handling

Unhandled exceptions are caught by `GlobalExceptionHandlerMiddleware`:

- Catches all unhandled exceptions
- Logs the exception via `Serilog.Log.ForContext<GlobalExceptionHandlerMiddleware>()`
- Returns `500` with `ApiResponse<object> { Success = false, Error = "An unexpected error occurred" }`
- **Never** leaks stack traces or internal details to the client in production
