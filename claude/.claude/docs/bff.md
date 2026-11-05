# Backend-for-Frontend (React SPA + .NET BFF)

A BFF is a .NET host that signs the user in, keeps every token on the server, proxies the
APIs the SPA calls and serves the built SPA from `wwwroot`. The browser only ever holds an
HttpOnly session cookie. Use it instead of MSAL in the browser whenever a SPA calls protected
APIs: no tokens in JS, no CORS, one origin, one image.

Everything in `conventions/dotnet.md` applies unless this file says otherwise. Reference
implementation: `tromb-hr-techpool` (`backend/Tromb.Hr.Techpool.Bff`).

## Shape

- **Repo**: sibling `frontend/` (Vite React) and `backend/` (.NET). Root `Dockerfile` from
  `templates/dotnet-spa-bff.Dockerfile`: one image, the SPA in `wwwroot`, no nginx.
- **Layout**: **1-project** with `Dispatch: direct handlers` by default. A BFF proxies and
  signs in; it has almost no use cases. Keep the layer folders and namespaces
  (`Api/`, `Application/`, `Infrastructure/`) and the split DI methods as usual. Skip `Domain/`
  when there is no database.
- **Stack**: **Microsoft.Identity.Web** (OIDC sign-in, token acquisition, token cache) +
  **YARP** (proxy) + FastEndpoints (the BFF's own endpoints). **Not Duende.BFF**: it needs a
  commercial license, the same problem as MediatR v13+.
- **No Swagger/Scalar**: the BFF's endpoints exist for one SPA.

## Credentials: managed identity, no client secret in Azure

A BFF is a confidential client and needs a credential. In Azure that credential is **the
container app's user-assigned managed identity**, trusted by the app registration through a
**federated identity credential (FIC)**. Nothing expires and nothing is rotated.

App registration, per managed identity (one per environment/stack):

| Field | Value |
|---|---|
| Issuer | `https://login.microsoftonline.com/{tenant-id}/v2.0` |
| Subject | the managed identity's **object (principal) id** |
| Audience | `api://AzureADTokenExchange` |

Container app env vars (Microsoft.Identity.Web reads them from the `EntraId` section, no code):

```
EntraId__ClientId=<app registration client id>
EntraId__ClientCredentials__0__SourceType=SignedAssertionFromManagedIdentity
EntraId__ClientCredentials__0__ManagedIdentityClientId=<managed identity client id>
```

- Use a **user-assigned** identity: its ids are known before the app exists, so the FIC and
  the env var can be set from IaC in one pass, and it survives recreating the app.
- **Local sign-in** has no managed identity. Use a **short-lived** client secret (≈30 days) in
  `dotnet user-secrets` (`EntraId:ClientSecret`), or put it on a separate dev-only app
  registration so the deployed one has no secret at all. Never set `EntraId__ClientSecret` in
  Azure. A mock mode (`npm run dev:mock`) needs no credential.
- The app registration also needs a **Web** platform with `{origin}/signin-oidc` redirect URIs
  (dev, compose, each environment) and consented delegated scopes for every downstream API.
- Pin the env var shape with a unit test that binds `EntraId:ClientCredentials:0:*` to
  `MicrosoftIdentityOptions`; a typo otherwise only shows at the first sign-in in Azure.

## Sign-in and session

```csharp
services.AddAuthentication(o =>
    {
        o.DefaultScheme = CookieAuthenticationDefaults.AuthenticationScheme;
        o.DefaultChallengeScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    })
    .AddMicrosoftIdentityWebApp(configuration.GetSection("EntraId"))
    .EnableTokenAcquisitionToCallDownstreamApi([apiScope, graphScope])
    .AddInMemoryTokenCaches();
```

- **Cookie is the default challenge**, and its `OnRedirectToLogin` returns **401** (and
  `OnRedirectToAccessDenied` 403). A `fetch` must never follow a redirect to Entra. Only
  `GET /bff/login?returnUrl=` challenges the OIDC scheme.
- Cookie: `__Host-{app}`, HttpOnly, `SecurePolicy.Always`, **SameSite=Strict**, path `/`,
  sliding expiry. Strict is fine: the first page load after sign-in arrives cross-site without
  the cookie, but it only needs static files, and the SPA's first `fetch` is same-site.
- `returnUrl` must be a **local path** (`/…`, not `//` or `/\`, no control characters).
  Anything else is 400, so the login can't be used as an open redirect.
- `POST /bff/logout` is a **form POST** (a navigation): sign out of the cookie and OIDC schemes.
- `GET /bff/user` is anonymous and returns `ApiResponse<{ isAuthenticated, name, email, roles }>`;
  anonymous is `isAuthenticated: false`, not 401, so the SPA decides to sign in.
- **Roles for the UI** come from the downstream API's access token (decode its `roles` claim
  on the server, no validation needed: it came straight from Entra), when the API's app roles
  are what the UI mirrors. They only decide what the UI offers; the API enforces them.

## Token cache and replicas

- **In-memory** token cache (`AddInMemoryTokenCaches`) ⇒ **one replica**. A restart empties
  the cache and the in-memory data-protection keys, so users sign in again (silently while
  their Entra session lives). Set `maxReplicas: 1` in IaC.
- To scale out: distributed token cache (Redis) **and** persisted data-protection keys
  (Blob + Key Vault). Both, or cookies from one replica fail on another.
- When the cookie is valid but the cache has no token (`MicrosoftIdentityWebChallengeUserException`
  / `MsalUiRequiredException`): sign out of the cookie scheme and answer 401 / "anonymous".
  Don't throw; the SPA redirects to `/bff/login`.

## Proxy (YARP)

- One route per downstream API, path unchanged (`/v1/{**catch-all}` when the API versions its
  routes; the BFF's own routes stay unversioned per the conventions), `AuthorizationPolicy =
  "default"`, config in code via `LoadFromMemory` with the base URL from settings.
- **Acquire the token in a proxy pipeline step before forwarding** (`MapReverseProxy(p =>
  p.Use(...))`): no token ⇒ 401 and stop. A request transform then sets `Authorization: Bearer`.
- Strip `Cookie` and the CSRF header from the upstream request.
- Other downstream calls the BFF makes itself (e.g. Graph photo) are typed `HttpClient`s with
  `AddStandardResilienceHandler()` behind an `Application` interface, cached by a decorator.

## CSRF

Every `fetch` from the SPA sends `X-CSRF: 1`. A middleware rejects calls to the proxied and
`/bff/user`-style JSON routes without it (400). A custom header forces a CORS preflight no other
site can pass; with SameSite=Strict that covers CSRF without antiforgery tokens. Navigations
(`/bff/login`, `/bff/logout`, the SPA) are exempt.

## Hosting the SPA

- `UseDefaultFiles` + `UseStaticFiles` **before** authentication, `MapFallbackToFile("index.html")`
  last and anonymous. Cache rules (what nginx used to do): `index.html`/`version.txt`
  `no-store`, `/assets/*` `public, max-age=31536000, immutable`, `/locales/*` `no-cache`.
- The Dockerfile writes `version.txt` into `wwwroot` from the `VERSION` build arg.
- **Forwarded headers**: Container Apps ends TLS. `UseForwardedHeaders()` first, with
  `XForwardedFor | XForwardedProto` and known networks/proxies cleared, so the OIDC redirect URI
  is `https`. Do not trust `X-Forwarded-Host`.
- Middleware order: ForwardedHeaders → Serilog → exception handler → static files → CSRF →
  authentication → authorization → FastEndpoints → reverse proxy → health → SPA fallback.
- Runtime config is env vars only; the SPA needs none (no `settings.js`, no `env.sh`).

## Frontend side

- Services call **relative** paths on the same origin with `X-CSRF: 1`; no `Authorization`
  header, no token anywhere in JS. A 401 from any call ⇒ `window.location.assign('/bff/login?returnUrl=' + here)`, once.
- `authStore` holds the user from `/bff/user`; role streams map from `user.roles`.
- Vite dev: proxy `/bff`, the API prefix, `/photo`-style routes, `/signin-oidc` and
  `/signout-callback-oidc` to the BFF with `changeOrigin: false`, so the BFF builds
  `http://localhost:5173/signin-oidc` as its redirect URI (register it).
- The mock mode answers every BFF route the UI calls (including a 404 for photos), or the Vite
  dev server returns `index.html` for them.

## Testing

`WebApplicationFactory<Program>` over the real pipeline, swapping only the outside world:

- A test auth scheme set as `DefaultAuthenticateScheme` (authenticates when a test header is
  present); the cookie stays the challenge scheme, so the 401 behavior is under test.
- NSubstitute for the token seam (`IDownstreamTokens`) and downstream clients.
- Replace YARP's `IForwarderHttpClientFactory` with a stub that records the forwarded request
  (assert Bearer header present, cookie and CSRF header absent, path unchanged).
- `UseSetting(WebHostDefaults.WebRootKey, tempDir)` with a minimal built SPA for cache-header tests.
- Cover: anonymous ⇒ 401 without `Location`; missing CSRF ⇒ 400; token unavailable ⇒ 401;
  `/bff/user` anonymous and signed in; non-local `returnUrl` ⇒ 400; static cache headers.
- Smoke the real host once with dummy settings: `/bff/login` must 302 to the right tenant with
  the expected scopes + `offline_access`, and `X-Forwarded-Proto: https` must give an `https`
  redirect URI.

## Gotchas

- Microsoft.Identity.Web 4.x pulls `System.Security.Cryptography.Xml`/`.Pkcs` 10.0.10, which
  have high-severity advisories; with `TreatWarningsAsErrors` restore fails (NU1903). Pin the
  patched versions in `Directory.Packages.props` (transitive pinning is on).
- Bind tests against `Microsoft.Identity.Web.MicrosoftIdentityOptions` (has `ClientSecret` and
  `ClientCredentials`), not `MicrosoftIdentityApplicationOptions`.
