# AGENTS.md

billet is a private two-person love-notes app: SwiftUI client, Cloudflare backend on Effect.
Design is in [docs/architecture.md](docs/architecture.md), scope in [docs/plan.md](docs/plan.md).

## Commands

```sh
pnpm install                              # Node 24, pnpm from packageManager
pnpm turbo run lint typecheck test        # TypeScript checks, safe on Linux (no Swift)
pnpm format:check                         # oxfmt check; `pnpm format` writes
pnpm ios:test                             # swift test in packages/ios (Mac only)
pnpm ios:build                            # swift build in packages/ios (Mac only)
pnpm alchemy dev                          # local infrastructure, no credentials (docs/alchemy.md)
pnpm db:generate                          # Drizzle migrations for D1 and Durable Object SQLite
```

Swift tasks are named `ios:*`, never `test` or `build`, so the default TS commands skip them.
Versions come from the catalog in `pnpm-workspace.yaml`: use `"catalog:"` in `package.json`.

## Layout and boundaries

- Workspaces are `apps/*`, `packages/<context>/<name>` and `packages/ios`.
- kebab-case for folders, `exports` subpaths, and TypeScript and config files. Swift files are the exception (see Swift).
- No barrels: no `index.ts` that re-exports. Import the module you need.
- Explicit `exports` is the only package boundary. Never import across packages by relative path.
- Only `platform` packages (`packages/<context>/platform`) touch Worker bindings or runtime globals.

## Secrets

Secrets live in Proton Pass. Commit only references (`API_KEY=pass://Billet/<item>/<field>`) in
`.env.pass`, and run with `pp run --env-file .env.pass -- <command>`. Never commit secret values.

## Admin data

Agents read the admin panel's numbers, experiments, flags, flag history and pairs (by pair id)
read-only with `scripts/admin-read.sh <route>`, run as
`PROTON_PASS_AGENT_REASON="<why>" pp run --env-file .env.pass.agents -- scripts/admin-read.sh flags`.
It prints JSON. Agents never create or change Access credentials, and cannot write through it. See
[docs/admin.md](docs/admin.md#agent-api).

## Swift

- Swift files are PascalCase, named after their main type (`PairingError.swift`). Kebab-case applies to TypeScript and config files only.
- `switch` over enums is exhaustive, with no `default`.
- Use typed throws (`throws(PairingError)`).
- Dependencies are explicit parameters. No singletons or global containers.
- Swift 6 strict concurrency stays on.

## Always

Never bypass hooks (`--no-verify`) and never suppress lint or type checks (`eslint-disable`-style
comments, `@ts-ignore`, `@ts-expect-error`, loosened compiler options). Fix the cause.
