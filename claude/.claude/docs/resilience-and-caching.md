# Resilience & Caching

## HttpClient Resilience

External HTTP calls use **`Microsoft.Extensions.Http.Resilience`** (Polly v8) for retry, circuit breaker, and timeout. Apply the standard resilience handler when registering typed `HttpClient`s:

```csharp
services.AddHttpClient<ISupplierApiClient, SupplierApiClient>(client =>
{
    client.BaseAddress = new Uri(config["BaseUrl"]!);
})
.AddStandardResilienceHandler();
```

`AddStandardResilienceHandler()` provides sensible defaults:
- **Retry**: 3 attempts with exponential backoff (1s, 2s, 4s) for 5xx and 408 responses
- **Circuit breaker**: opens after 10% failure rate in a 30s sampling window, stays open for 30s
- **Timeout**: 30s per attempt, 2min total

Override defaults via `appsettings.json` when needed:

```json
{
  "SupplierApi": {
    "Resilience": {
      "Retry": { "MaxRetryAttempts": 2 },
      "CircuitBreaker": { "SamplingDuration": "00:00:30" },
      "AttemptTimeout": { "Timeout": "00:00:10" },
      "TotalRequestTimeout": { "Timeout": "00:01:00" }
    }
  }
}
```

## Response Caching

For external API responses that don't change frequently, use **`IMemoryCache`** with a configurable TTL:

```csharp
public interface ICachedSupplierApiClient
{
    Task<Result<List<BackendSupplier>>> GetSuppliersAsync(CancellationToken ct);
}
```

- Implement as a **decorator** over `ISupplierApiClient` — the cache layer wraps the real client
- Cache key should be simple and deterministic (e.g., `"suppliers:all"`)
- TTL is configurable via `appsettings.json` (e.g., `SupplierApi:CacheTtlMinutes`)
- Use `IMemoryCache.GetOrCreateAsync()` — single method handles cache miss + population
- Cache invalidation: TTL-based only (no manual invalidation needed for read-only facades)
- Register `IMemoryCache` via `services.AddMemoryCache()` in DI

## Conventions

- Always apply `AddStandardResilienceHandler()` to typed `HttpClient` registrations for external APIs
- Use `IMemoryCache` for response caching — not distributed cache (overkill for single-instance facades)
- Cache TTL should be configurable, not hardcoded
- Handlers inject the cached interface, never the raw client directly
- Log cache hits/misses at `Debug` level
