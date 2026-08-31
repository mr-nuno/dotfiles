# Global Instructions

## Git — Always

- **NEVER push directly to `main` or `develop`** — always create a branch first
- **NEVER commit directly to `main` or `develop`** — all changes go through pull requests
- Before any git push, verify you are on a feature/fix/chore branch, not `main` or `develop`
- Conventional Commits: `feat`, `fix`, `refactor`, `chore`, `test`, `docs`, `style`
- Never include any claude references in commits or pull requests

### Commit message examples

- `feat: new endpoint for fetching pets`
- `fix: added validation to add pet`
- `chore: updated readme`

## Code search

- Default to `rg` (ripgrep) for code search — **not** `grep -r`.
  `rg` honors `~/Projects/.ignore` (currently `**/private/`) with no flags.
- The `grep` in this shell is a shim over `ugrep` that reads **`.gitignore`
  only** — it silently skips `.ignore`.
- If `grep` is used anyway (including when asked for "grep" by name), it
  **must** carry `--ignore-files=.ignore`:

      grep -rn --ignore-files=.ignore PATTERN path/

  The flag is additive — `.gitignore` and `.ignore` both apply.
- For a deliberately exhaustive sweep (secret scans, audits, "is this
  anywhere on disk"), use `rg --no-ignore` and say so in the results —
  otherwise the answer is scoped, not complete.

## .NET Web API Projects

For .NET Web API projects, see `conventions/dotnet.md` for standard conventions and patterns.

**Exception**: Projects that define their own complete .NET conventions in their project-level CLAUDE.md (e.g., the claude-api-workbench) should use their own conventions — ignore `conventions/dotnet.md` for those projects.

### DO NOT

- **DO NOT upgrade MediatR past `12.5.0`.** Version 13.0.0 and later require a paid commercial license (LuckyPennySoftware). `12.5.0` is the last release under the free Apache-2.0 license.

## React projects

For React projects, see `conventions/react.md` for standard conventions and patterns.

## Architecture reference (`docs/`)

Deep-dive docs the .NET conventions link into live in `docs/` — read the
relevant one when the conventions reference it.

## Scaffolding templates (`templates/`)

Reusable root files for standing up a new .NET Web API / React project live in
`templates/`. Copy the ones you need into the project root and replace any
`{Api}`/`{Worker}`/`{App}` placeholders.

## Working style

- **Docker**: build once / run anywhere; multi-stage builds; runtime config via env vars +
  nginx templates. See `rules/code-docker.md`.
- **Terminal**: prefix any question or clarification request with a ❓ emoji.
  See `rules/terminal-session.md`.
