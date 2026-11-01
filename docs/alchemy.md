# Alchemy (infrastructure as code)

billet declares its Cloudflare infrastructure with [Alchemy](https://alchemy.run) v2 in the root
[`alchemy.run.ts`](../alchemy.run.ts). Alchemy v2 is a different library from v1 (it is built on
Effect v4), so older posts do not apply. Check the `.d.ts` files in `node_modules/alchemy` and
`node_modules/@alchemy.run/cloudflare`.

## Versions

- `alchemy` and `@alchemy.run/cloudflare` are `2.0.0-beta.84`, exact-pinned in the pnpm catalog.
  Bump them together.
- The root tooling uses the `infra` catalog: `effect` and `@effect/platform-node` `4.0.6`. Alchemy
  beta.84 imports `effect/Crypto`, which effect 4.1 renamed to `effect/crypto`, so it crashes on the
  `4.1.1` used by the rest of the repo. A pnpm override pins `@effect/platform-node-shared` to
  `4.0.6` for the same reason. Only the root uses these. Drop the catalog and the override when
  Alchemy supports effect 4.1.

## What the stack declares

| Logical id | Resource | Binding on `Api` |
| --- | --- | --- |
| `Database` | `Cloudflare.D1.Database`, the cross-couple directory (no tables yet) | `DB` |
| `Media` | `Cloudflare.R2.Bucket`, private: no public access, no custom domain | `MEDIA` |
| `PairRoom` | `Cloudflare.DurableObject`, SQLite-backed, one object per couple | `PAIR_ROOM` |
| `Api` | `Cloudflare.Worker`, `main: ./apps/api/src/worker.ts` | |

- `Api` is an async Worker: a plain module that exports `fetch` and the `PairRoom` class. The Worker
  code never imports Alchemy.
- `apps/api` is the composition root only. The Durable Object class, the placeholder response and the
  binding types live in `packages/backend/platform`, the only place that touches bindings. The
  binding types in `worker-env.ts` and `env` in `alchemy.run.ts` must stay in step.
- The `PairRoom` rules live in `packages/backend/pair-room`. The fetch response is still a
  placeholder, so no route reaches the object yet: the routes arrive with later tickets.
- Physical names derive from the stack (`billet`), the stage and the logical id. Nothing personal is
  committed. The Cloudflare account comes from `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`,
  read only by a real deploy.
- When the first D1 tables exist, add `migrations: "./apps/api/migrations"` to `Database`.

## Stages and state

- **Local** (`alchemy dev`): every resource runs on a local simulator, with no Cloudflare calls and no
  credentials. State is in the gitignored `.alchemy/` folder.
- **`dev` and `prod`** (`alchemy deploy --stage <stage>`): real Cloudflare resources. State is kept in
  a D1 database named `billet-alchemy-state`, in the same account, through
  [`alchemy-d1-state.ts`](../alchemy-d1-state.ts). It is created on first use, is not part of the
  stack (so `destroy` keeps it) and holds Worker secrets in plaintext, like the local store.
- `Cloudflare.state()` is not used: it keeps its token in the account's Secrets Store, which the
  deploy token should not need.
- `.alchemy` is never committed: it is in `.gitignore`, and `git ls-files | grep -cF .alchemy` must
  print `0`. The repository is public.

```sh
pnpm alchemy dev                              # local, no credentials
curl -si http://localhost:8787/               # 200 {"service":"billet-api","status":"ok"}
```

Stop `alchemy dev` with Ctrl-C. Killing only the `pnpm` wrapper leaves Alchemy and workerd running.

## Deploying

Secrets are Proton Pass references, never values. `.env.pass` (dev, vault `Billet`) and
`.env.pass.release` (prod, vault `Billet Release`) hold them:

| Variable | Vault item | Field |
| --- | --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | `cloudflare` | `account_id` |
| `CLOUDFLARE_API_TOKEN` | `cloudflare` | `api_token` |

The API token needs Workers Scripts, D1 and R2 edit on the account. Create one item per vault.

```sh
PROTON_PASS_AGENT_REASON="billet deploy dev" pp run --env-file .env.pass -- pnpm exec alchemy deploy --stage dev
```

Do not pass `--env-file` to `alchemy` itself: the file would then win over the shell, and Alchemy
would read the literal `pass://` strings.

### Deploy workflow

[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) is manual only
(`workflow_dispatch`). It never runs from a pull request or a push. It also does nothing until the
owner:

1. creates the vaults `Billet` and `Billet Release`, each with a `cloudflare` item;
2. installs and logs in `pp` on a runner that can read both vaults;
3. sets the repository variables `DEPLOY_RUNNER` (a JSON label list for that runner) and
   `DEPLOY_ENABLED=true`;
4. adds required reviewers to the `prod` environment.

The workflow runs the checks, deploys, prints the log with the `workers.dev` address masked (public
repository logs are public), and smoke-tests the Worker URL for HTTP 200. The account ID is masked too, and the raw log is deleted
from the runner in a final step that runs even when the deploy fails. Read the log of the first
`dev` run for anything private before enabling `prod`. To deploy on push later,
add a `push` trigger in a separate change, once the above works.

## Not verified without credentials

Everything except a real deploy is checked: typecheck, lint, tests, and an `alchemy dev` run that
planned and created all four resources locally. The pieces below have not run against Cloudflare:
`alchemy deploy`, the D1 state store, the `pass://Billet Release/...` reference (a vault name with a
space), and the workflow on a runner.
