# billet

A private two-person iPhone app for love notes. You draw something or send a photo, and it lands on
your partner's widget.

## Status

Pre-alpha, under construction. There is no app code yet; the repository currently holds the plan
and architecture only.

## Stack

- iOS: SwiftUI and WidgetKit
- Backend: Cloudflare Workers, Durable Objects, D1 and R2, written with Effect TS
- Tooling: pnpm and Turborepo

## Repository layout

```
apps/       Deployable entry points (api Worker, iOS app)
packages/   Shared code: contracts, backend modules, config, and the Swift package
docs/       Plan and architecture
```

Most of these directories do not exist yet; see the architecture document for the intended layout.

## Docs

- [docs/plan.md](docs/plan.md): the project plan, constraints and ticket breakdown
- [docs/architecture.md](docs/architecture.md): how the system fits together

## License

[MIT](LICENSE)
