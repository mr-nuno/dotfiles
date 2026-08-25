# React Conventions

## Applicability

- **New projects**: Follow these conventions strictly.
- **Existing/legacy projects**: Treat as preferred conventions. Adopt incrementally
  in new code and refactors. Do not rewrite working code solely to conform.

## Tech Stack

- **React 19** — function components only.
- **TypeScript** — strict mode (`strict`, `noUnusedLocals`, `noUnusedParameters`,
  `noFallthroughCasesInSwitch`).
- **Vite** — frontend tooling (`bundler` module resolution, `esnext` target).
- **Tailwind CSS v4 + shadcn/ui + Radix** — styling and primitives. Merge classes
  with `cn()` from `@/lib/utils`. Do **not** use MUI or CSS-in-JS.
- **Dark mode** — required. Support light / dark / **system**, with `system`
  resolved against `prefers-color-scheme`. Drive it from a `themeStore` (RxJS)
  that toggles the `dark` class on `<html>`; style with Tailwind's `dark:` variants
  and shadcn CSS variables (never hard-coded colors).
- **RxJS** — state management via `BehaviorSubject` stores, consumed with
  `useObservableState` from `observable-hooks`. No Redux, no Zustand, no Context
  for app state.
- **Docker / docker-compose** — containerized development and deployment.

## Coding Style

- Always use `export const` + arrow functions for pages, components, hooks, and
  functions. Type components' return as `ReactElement`.

```tsx
export const ExperienceCard = ({ exchanges, onRefresh }: ExperienceCardProps): ReactElement => {}
```

- **Tabs** for indentation (matches the existing codebase / editorconfig).
- Always set path aliases and use barrels — no relative import paths across
  feature boundaries. Mirror the aliases in **both** `tsconfig.app.json` and
  `vite.config.ts`.

```json
"paths": {
  "@/*": ["src/*"],
  "@components/*": ["src/components/*"],
  "@features/*": ["src/features/*"],
  "@services/*": ["src/services/*"],
  "@config/*": ["src/config/*"]
}
```

- Each top-level folder has a barrel (`index.ts`). Re-export new public modules
  through it so callers `import { x } from '@services'` rather than reaching into
  files. Stores are re-exported as **namespaces** so call sites read as
  `resumeStore.workExperience$`:

```ts
export * as resumeStore from './resumeStore';
export * as themeStore from './themeStore';
```

- Prefer one object and one `useState` where several fields move together.

```tsx
const initialForm = { name: '', type: 'direct', durable: true };
const [form, setForm] = useState(initialForm);

const setField = <K extends keyof typeof initialForm>(field: K, value: typeof initialForm[K]) => {
  setForm(prev => ({ ...prev, [field]: value }));
};
```

## State — RxJS store pattern

- One `BehaviorSubject` per atomic piece of state. Never export the raw
  `BehaviorSubject`; expose derived selector streams instead.
- Derive selectors with
  `.pipe(map(...), distinctUntilChanged(shallowEqual | shallowEqualArray), shareReplay({ bufferSize: 1, refCount: true }))`.
  Shared equality helpers live in `src/state/equality.ts`.
- Setters are named exports. Never mutate in place — always produce a new
  object/array, and guard with a `!==` check before calling `.next()`.
- Components subscribe via `useObservableState(stream$, default)`. **Never** read
  `.value` from a component in a render path. For synchronous reads inside event
  handlers, expose a `*Snapshots` object with getters (e.g. `uiSnapshots.isSimplified`).

```ts
const isSimplified$ = new BehaviorSubject<boolean>(false);

export const isSimplifiedStream$ = isSimplified$.pipe(
  distinctUntilChanged(),
  shareReplay({ bufferSize: 1, refCount: true }),
);

export const setIsSimplified = (v: boolean): void => {
  if (isSimplified$.value !== v) isSimplified$.next(v);
};

export const uiSnapshots = {
  get isSimplified() { return isSimplified$.value; },
};
```

## Services (HTTP / I/O)

- Set `Authorization: Bearer ${token}` + `Accept: application/json` on GETs.
- Map raw DTOs (`IApi*`) into domain types inside the service — the UI never sees
  `IApi*`.
- Return a safe empty/`IApiResult` value on failure, log the error, and do not
  throw past the service boundary. Carry the HTTP status so callers can surface a
  status-specific message (see the `IApiResult` / `errorKeyForStatus` pattern).
- Re-export new fetchers through the services barrel.

## Types — three tiers

- `IApi*` — raw JSON from the server, consumed **only** inside the service.
- Domain type (e.g. `ICertification`) — what editor + stores work with; adds
  UI-only fields like `id`, `isActive`, optional `isNew`.
- View/export type (e.g. `IPdf*`) — slimmed shape for a specific output; strips
  UI-only fields.

## Components

- `export const` + arrow functions for every page, component, hook.
- Follow the `*Card` + `*ListItem` pattern: the card owns layout + the add
  button, and each list item is an isolated subscriber so toggling one row does
  not re-render the rest.
- shadcn/ui primitives live under `src/components/ui/`. Generic shared components
  live directly under `src/components/`.

## Do NOT

- Do **not** set a `Content-Type` header on **GET** requests — a GET has no body,
  so the header is meaningless and can trigger an unnecessary CORS preflight.
  (POST/PUT/PATCH with a JSON body still set `Content-Type: application/json`.)
- Do **not** use MUI, Redux, Zustand, or React Context for app state.
- Do **not** export raw `BehaviorSubject`s or read `.value` in render paths.
- Do **not** use relative imports across feature boundaries — go through an alias.
