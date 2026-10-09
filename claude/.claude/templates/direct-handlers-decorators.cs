// HandlerDecorators.cs — cross-cutting behavior for non-HTTP callers of direct handlers.
// See .claude/docs/direct-handlers.md "Cross-cutting concerns". Copy to
// src/{Application}/Common/Handlers/HandlerDecorators.cs and replace {Namespace}.
//
// Registered in AddApplicationServices() with Scrutor, in this order (last = outermost):
//
//     services.Decorate(typeof(IHandler<,>), typeof(ValidationDecorator<,>));
//     services.Decorate(typeof(IHandler<,>), typeof(LoggingDecorator<,>));
//
// Decorators wrap ONLY calls made through IHandler<TRequest, TValue>. Endpoints inject the
// concrete Handler and get validation/logging from FastEndpoints instead. Jobs and queue
// consumers inject the interface to get the decorated pipeline.

using Ardalis.Result;
using FluentValidation;

namespace {Namespace}.Application.Common.Handlers;

public sealed class ValidationDecorator<TRequest, TValue>(
    IHandler<TRequest, TValue> inner,
    IEnumerable<IValidator<TRequest>> validators) : IHandler<TRequest, TValue>
{
    public async ValueTask<Result<TValue>> Handle(TRequest request, CancellationToken ct)
    {
        var context = new ValidationContext<TRequest>(request);
        var errors = new List<ValidationError>();
        foreach (var validator in validators)
        {
            var result = await validator.ValidateAsync(context, ct);
            errors.AddRange(result.Errors.Select(e => new ValidationError(e.PropertyName, e.ErrorMessage)));
        }

        if (errors.Count > 0)
        {
            return Result<TValue>.Invalid(errors);
        }

        return await inner.Handle(request, ct);
    }
}

public sealed class LoggingDecorator<TRequest, TValue>(IHandler<TRequest, TValue> inner) : IHandler<TRequest, TValue>
{
    private static readonly Serilog.ILogger Log = Serilog.Log.ForContext<LoggingDecorator<TRequest, TValue>>();

    public async ValueTask<Result<TValue>> Handle(TRequest request, CancellationToken ct)
    {
        var result = await inner.Handle(request, ct);
        if (result.IsSuccess)
        {
            Log.Information("Handled {Request} with {Status}", typeof(TRequest).Name, result.Status);
        }
        else
        {
            Log.Warning("Handled {Request} with {Status}", typeof(TRequest).Name, result.Status);
        }

        return result;
    }
}
