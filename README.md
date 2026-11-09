# Ourio

A private two-person iPhone app. You draw a note or send a photo and it lands on your partner's
widget; together you raise a cat, play small games and keep a streak.

## Stack

- iOS: SwiftUI and WidgetKit (`apps/ios`, `packages/ios`)
- Backend: Cloudflare Workers, Durable Objects, D1 and R2, written with Effect TS (`apps/api`,
  `packages/backend`)
- Contracts: Effect Schema, shared by TypeScript and Swift (`packages/contracts`)
- Tooling: pnpm and Turborepo

## Docs

- [docs/architecture.md](docs/architecture.md): how the system fits together
- [docs/design-system.md](docs/design-system.md): how the app looks
- [AGENTS.md](AGENTS.md): commands and repository rules

## License

[MIT](LICENSE) for this project's own code; see [NOTICE.md](NOTICE.md) for the parts it does not cover.
