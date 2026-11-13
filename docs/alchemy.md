# Alchemy (infrastructure as code)

billet declares its Cloudflare infrastructure with [Alchemy](https://alchemy.run) v2 in the root
[`alchemy.run.ts`](../alchemy.run.ts). Alchemy v2 is a different library from v1 (it is built on
Effect v4), so older posts do not apply. Check the `.d.ts` files in `node_modules/alchemy` and
`node_modules/@alchemy.run/cloudflare`.

## Versions

- `alchemy`, `@alchemy.run/cloudflare` and `@alchemy.run/drizzle` are `2.0.0-beta.84`, exact-pinned in
  the pnpm catalog. `drizzle-orm` and `drizzle-kit` are exact-pinned to `1.0.0-rc.5-ab785fc`, the build
  `@alchemy.run/drizzle` peers on. It is a release candidate. Upgrade all of them together.
- The root tooling uses the `infra` catalog: `effect` and `@effect/platform-node` `4.0.6`. Alchemy
  beta.84 imports `effect/Crypto`, which effect 4.1 renamed to `effect/crypto`, so it crashes on the
  `4.1.1` used by the rest of the repo. A pnpm override pins `@effect/platform-node-shared` to
  `4.0.6` for the same reason. Only the root uses these. Drop the catalog and the override when
  Alchemy supports effect 4.1. `@effect/sql-d1` then also stops warning about its `effect` peer at the
  root. That warning is harmless while the root imports `@alchemy.run/drizzle/Schema` and
  `/Providers`, not the package root.

## What the stack declares

| Logical id | Resource | Binding on `Api` |
| --- | --- | --- |
| `DirectorySchema` | `Drizzle.Schema`, the D1 tables and their migrations | |
| `Database` | `Cloudflare.D1.Database`, the cross-couple directory | `DB` |
| `Media` | `Cloudflare.R2.Bucket`, private: no public access, no custom domain | `MEDIA` |
| `Titles` | `Cloudflare.KV.Namespace`, TMDB's answers for the To watch list, keyed by hash | `TITLES` |
| `PairRoom` | `Cloudflare.DurableObject`, SQLite-backed, one object per couple | `PAIR_ROOM` |
| `Events` | `Cloudflare.AnalyticsEngine.Dataset`, dataset `billet_<stage>_events` | `EVENTS` |
| `Api` | `Cloudflare.Worker`, `main: ./apps/api/src/worker.ts`, static assets from `./apps/api/public` | `ASSETS` |

- `Events` is only a binding: Analytics Engine creates the dataset on the first write, so there is
  nothing to provision and nothing to destroy. The row layout is in
  [experiments.md](experiments.md#analytics-engine).
- `Api` is an async Worker: a plain module that exports `fetch` and the `PairRoom` class. The Worker
  code never imports `alchemy` or `@alchemy.run/*` (see [Drizzle](#drizzle)).
- `Api`'s static assets are served assets-first: a path that matches a file in `apps/api/public`
  is answered by Cloudflare's asset layer without running the Worker, and every other path reaches
  the Worker. The folder has no `index.html`, so `/`, `/v1/*`, `/admin` and `/i/*` stay the
  Worker's. `_headers` there sets the cache rules. The Worker doesn't read the `ASSETS` binding, so
  `worker-env.ts` leaves it out. `alchemy dev` serves the folder the same way.
- `apps/api` is the composition root only. The Durable Object class, `respondApi` and the
  binding types live in `packages/backend/platform`, the only place that touches bindings. The
  binding types in `worker-env.ts` and `env` in `alchemy.run.ts` must stay in step.
- The `PairRoom` rules live in `packages/backend/pair-room`. `/v1/` serves the auth, pairing, notes and
  media routes, and anything else answers the placeholder that the deploy smoke test reads.
- Physical names derive from the stack (`billet`), the stage and the logical id. Nothing personal is
  committed. The Cloudflare account comes from `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`,
  read only by a real deploy.

## Drizzle

`packages/backend/platform` uses the official Effect drivers directly: `drizzle-orm/effect-d1` in
`directory-database.ts` and `drizzle-orm/effect-sqlite-do` in `room-database.ts`. Alchemy only does
infrastructure, including the D1 migrations.

### Why not `Drizzle.DurableObject`

The first design used `Cloudflare.SqlMigrations` and `Drizzle.DurableObject`. They need an
Effect-native `Cloudflare.DurableObject`, and the Alchemy CLI loads that class in Node. On effect 4.1.1
it loads `@alchemy.run/cloudflare`, which reaches the `effect/Crypto` import in
`alchemy/lib/Auth/OAuthFlow.js` and crashes with `Cannot find module .../effect/dist/Crypto.js`.

`Drizzle.D1` and `Drizzle.DurableObject` do run in a plain Worker, but the second one then needs
`DurableObjectState` provided by hand. That is the wrapper this design avoids, and it adds Alchemy
modules to the bundle. With the direct drivers the Worker bundle has no `alchemy` or `@alchemy.run`
source, and every `effect` source is 4.1.1. Revisit this when Alchemy supports effect 4.1.

### Migrations

Change a schema, then run `pnpm db:generate` and commit the result. A test fails if a schema has no
committed migration. drizzle-kit may ask about renames or data loss, so run it in a terminal. To add
tables and drop one in a change without that prompt, generate the additions first and the drop second.

| | D1 | Durable Object SQLite |
| --- | --- | --- |
| Schema | `src/directory-schema.ts` | `src/room-schema.ts` |
| Files | `migrations/directory/` | `migrations/room/` |
| Generated with | `drizzle-kit generate --dialect sqlite` | the same, plus `--driver durable-sqlite` |
| Applied by | `alchemy deploy` | `openRoomDatabase`, called when the object activates |
| History table | `__alchemy_migrations` | `__drizzle_migrations` |

- The Alchemy docs do not say how Durable Object files are made. `--driver durable-sqlite` adds a
  `migrations.js` that imports each `.sql` file. Alchemy's bundler imports `.sql` as text, so no
  codegen is needed. The test config has a small plugin that does the same. `migrations.d.ts` is
  written by hand and stays when the files are regenerated.
- If a schema change has no migration, `Drizzle.Schema` generates one during the deploy and applies it
  unreviewed. That is what the test prevents.

`PairRoom` itself does not use `openRoomDatabase` yet: `pair-room-sqlite-store.ts` still runs its own
hand-written migrations until #67 moves it to Drizzle. The two histories are separate tables, so they
do not collide.

### When a Durable Object migration fails

Call `openRoomDatabase` inside `blockConcurrencyWhile`, in the constructor, so no request gets in first.
All pending migrations run in one transaction, so a failure leaves the schema as it was. The object
then resets, the request fails, and every later request retries and fails the same way. Data is safe,
but that room is down until a fixed migration ships.

- Objects migrate one by one as they activate. A bad migration breaks each room when it is next used,
  not at deploy time.
- Never edit a migration that has shipped. The history stores names, with no content hash, so an
  object that has applied it will not notice. Ship a new migration instead.

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
`.env.pass.release` (prod, vault `Billet Release`) hold them. `.env.pass.release` is the single list
of what prod needs:

| Variable | Vault, item (prod) | Field |
| --- | --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | `Billet Release`, `cloudflare` | `account_id` |
| `CLOUDFLARE_API_TOKEN` | `Billet Release`, `cloudflare` | `api_token` |
| `APNS_KEY`, `APNS_KEY_ID` | `Billet`, `Apple` | same names |
| `APPLE_SIGN_IN_KEY`, `APPLE_SIGN_IN_KEY_ID` | `Billet`, `Apple` | same names |
| `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD` | `Billet Release`, `Cloudflare Access` | `team_domain`, `aud` |
| `TMDB_TOKEN` | `Billet Release`, `TMDB` | `api_token` |

The prod API token is its own token, separate from dev's: Account, Workers Scripts, D1 and R2, all
Edit, on this account only. The deploy also makes KV namespaces, an Analytics Engine dataset and
Durable Object migrations; if a deploy fails with an authentication error naming one of them, add
that permission (Workers KV Storage: Edit) to the token and rerun.

The four `Apple` fields are account-wide Apple keys: the APNs key (push) and the Sign in with
Apple key (`APPLE_SIGN_IN_KEY`, the `.p8` PEM, which lets the Worker revoke a user's Apple token
when they delete their account, App Store guideline 5.1.1(v)). The same `.p8` files work for every
stage, so every stage binds them (`alchemy.run.ts`); only `DEMO_ROOM` stays dev-only. A `dev` or `prod`
deploy stops before planning, naming the missing variables, if one is absent (local `alchemy dev`
needs none). Because the keys are the same, `.env.pass.release` reads
them from the item `Apple` in the vault `Billet`, like `.env.pass`; there is no second copy to keep in
step. The Sign in with Apple key has `com.ourio.app` as its primary App ID; the Worker still accepts
tokens and revokes codes for the first app, `com.mikitahimpel.billet`, until the owner retires it.

The `dev` stage is deployed locally, by the manager, through `pp`:

```sh
PROTON_PASS_AGENT_REASON="billet deploy dev" pp run --env-file .env.pass -- pnpm exec alchemy deploy --stage dev
```

Do not pass `--env-file` to `alchemy` itself: the file would then win over the shell, and Alchemy
would read the literal `pass://` strings.

**Prod is deployed only by the owner, only from GitHub Actions** (below). Agents never deploy prod,
never run `.env.pass.release` through `pp`, and never run the sync script.

### Deploy workflow

[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) is manual only
(`workflow_dispatch`, stage `prod`). It never runs from a pull request or a push. It runs on a
GitHub-hosted runner in the GitHub environment `prod`, which needs the owner's approval (required
reviewer) and accepts only the `main` branch. Its secrets are the environment's secrets, a copy of
the Proton Pass items above; Proton Pass stays the source of truth. The `dev` stage has no GitHub
environment and does not run here.

The workflow checks that the six required secrets are present (names only) and warns about missing optional ones, runs
`pnpm turbo run lint typecheck test format:check`, then
`pnpm exec alchemy deploy --stage prod --yes --no-input`, prints the log with the `workers.dev`
address masked (public repository logs are public; the account ID is a secret, so GitHub masks it
too), smoke-tests the Worker URL for HTTP 200 and deletes the raw log in a last step.

Owner steps, once. The secrets are copied from Proton Pass to GitHub; the Mac's `pp` session is
the agents' session and cannot read the prod vault, so the main path is by hand.

1. Create the prod items in Proton Pass (the vault and field names are in the table above), and
   back up the Apple `.p8` keys in the item `Apple`: Apple shows each one only once.
2. **Manual copy (main path).** GitHub, Settings, Environments, `prod`, Environment secrets, Add
   secret, for each name below, pasting the value from Proton Pass. `APPLE_SIGN_IN_KEY` and
   `APNS_KEY` are multi-line PEM (`.p8`) values: paste them whole, with the BEGIN and END lines.

   | Secret | Proton item and field | Needed |
   | --- | --- | --- |
   | `CLOUDFLARE_ACCOUNT_ID` | prod `cloudflare`, `account_id` | required |
   | `CLOUDFLARE_API_TOKEN` | prod `cloudflare`, `api_token` | required |
   | `APNS_KEY` | `Apple`, `APNS_KEY` (PEM) | required |
   | `APNS_KEY_ID` | `Apple`, `APNS_KEY_ID` | required |
   | `APPLE_SIGN_IN_KEY` | `Apple`, `APPLE_SIGN_IN_KEY` (PEM) | required |
   | `APPLE_SIGN_IN_KEY_ID` | `Apple`, `APPLE_SIGN_IN_KEY_ID` | required |
   | `ACCESS_TEAM_DOMAIN` | prod `Cloudflare Access`, `team_domain` | optional |
   | `ACCESS_AUD` | prod `Cloudflare Access`, `aud` | optional |
   | `TMDB_TOKEN` | prod `TMDB`, `api_token` | optional |

   The first prod deploy works without the three optional ones: the Access application needs the
   deployed host first, so `/admin` stays closed until `ACCESS_*` are set, and without
   `TMDB_TOKEN` prod serves no titles. The workflow warns by name. Add them later and run Deploy
   again.
3. **Script (optional).** `scripts/sync-prod-secrets.sh` does the same copy without printing a
   value: `--dry-run` lists names; it skips an optional variable whose Proton item does not exist
   yet and lists what it skipped. It needs a `pp` session that can read the prod vault, that is the
   owner's own login (`PROTON_PASS_SESSION_DIR` pointing at a directory logged in as the owner),
   and `gh` logged in.
4. Actions, Deploy, Run workflow, stage `prod`. Approve the waiting run in the GitHub app or the
   run page. Then check `GET /` and `/v1/flags` on the prod host.

Rotation: change the value in Proton Pass first, update the secret in GitHub (by hand or with the script), then run
the workflow so the Worker gets the new value. A new variable goes into `.env.pass.release` and
`deploy.yml` together.

State: the deploy keeps its state in the account's D1 database `billet-alchemy-state`
([Stages and state](#stages-and-state)), not on the runner, so CI and a local deploy agree on what
exists. The first prod deploy creates that database if the account has none, then the prod
resources. The raw log of the first run may hold something private; read it once after the run.

## Verified and not verified

`alchemy deploy`, the D1 state store, D1 migrations and Durable Object migrations have run on the
`dev` stage. The `prod` stage, the `pass://Billet Release/...` reference (a vault name with a space)
and the workflow have not.
