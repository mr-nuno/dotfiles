// IHandler.cs — the one contract for direct handlers (no dispatch library).
// See .claude/conventions/dotnet-direct-handlers.md. Copy to
// src/{Application}/Common/Handlers/IHandler.cs and replace {Namespace}.
//
// Every handler returns Ardalis.Result<TValue>, so decorators can short-circuit with
// Result.Invalid(...) without knowing the concrete value type. Endpoints inject the
// concrete nested Handler type; the interface exists for scanning and decorators, not mocking.

using Ardalis.Result;

namespace {Namespace}.Application.Common.Handlers;

public interface IHandler<in TRequest, TValue>
{
    ValueTask<Result<TValue>> Handle(TRequest request, CancellationToken ct);
}
