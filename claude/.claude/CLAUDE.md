# Global Instructions

## Git — Always

- **NEVER push directly to `main` or `develop`** — always create a branch first
- **NEVER commit directly to `main` or `develop`** — all changes go through pull requests
- Before any git push, verify you are on a feature/fix/chore branch, not `main` or `develop`
- Conventional Commits: `feat`, `fix`, `refactor`, `chore`, `test`, `docs`, `style`
- Never include any claude references in commits or pull requests
- NEVER include "Co-Authored-By" or "Generated with Claude" in commit messages.
- Use clean, human-only commit messages.

### Commit message examples

- `feat: new endpoint for fetching pets`
- `fix: added validation to add pet`
- `chore: updated readme`

## .NET Web API Projects

For .NET Web API projects, see `conventions/dotnet.md` for standard conventions and patterns.
Projects whose `CLAUDE.md` says `Dispatch: direct handlers` also follow
`conventions/dotnet-direct-handlers.md` (no Mediator; endpoints call handlers directly).

**Exception**: Projects that define their own complete .NET conventions in their project-level CLAUDE.md (e.g., the claude-api-workbench) should use their own conventions — ignore `conventions/dotnet.md` for those projects.

### DO NOT

- **DO NOT use MediatR in new code.** Version 13.0.0 and later require a paid commercial license (LuckyPennySoftware). Use [Mediator](https://github.com/martinothamar/Mediator) (`martinothamar/Mediator`, MIT, source generator) instead.
- **DO NOT upgrade MediatR past `12.5.0`** in existing projects that still use it. `12.5.0` is the last release under the free Apache-2.0 license.

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

- **Sensitive data**: never read, search, or reference anything under a `private/`
  folder — real personal data lives there, and tool output is sent to the model. Use the
  purpose-built dummy fixture instead. Enforced by a `PreToolUse` hook, not by attention.
  See `rules/sensitive-data.md`.
- **Docker**: build once / run anywhere; multi-stage builds; runtime config via env vars +
  nginx templates. See `rules/code-docker.md`.
- **Terminal**: prefix any question or clarification request with a ❓ emoji.
  See `rules/terminal-session.md`.
