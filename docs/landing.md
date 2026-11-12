# Landing

The marketing site, `apps/landing`: a static Astro build served by Cloudflare Pages. Every route
is listed once in `src/site.ts`; the copy lives in `src/config.ts`, `features.ts`, `faq.ts`,
`compare.ts` and `dates.ts`. The look is `src/styles/global.css`, with each first screen's rules
inlined from `critical-home.css` and `critical-site.css`.

```sh
pnpm --filter @billet/landing dev     # http://pc:4321 with --host 0.0.0.0
pnpm --filter @billet/landing build   # apps/landing/dist, with a Markdown twin beside every page
```

## Images

The room render and Mochi's loop are pre-sized in `src/assets/room/` (AVIF and WebP at 1000, 1600
and 2560 px; the loop at 80 and 140 px) and imported as URLs through `src/lib/room-assets.ts`, so
the build hashes their names without re-encoding them. Art, screenshots, date ideas and shop items
stay in `src/assets/` at their source size; the build makes their WebP steps. No multi-megabyte PNG
is shipped.

Only `/_astro/` is cached for good, because every name there carries a content hash; every other
file is revalidated on each visit, Pages' default (`public/_headers`). So `public/` holds only files that must keep
their name (the icons, `og.png`, `_headers`), and `scripts/check-public.mjs` fails the build on
anything else there.

## Deploys

`.github/workflows/landing.yml` deploys `apps/landing/dist` with wrangler from the pnpm catalog:

| Where | When | Pages project | URL |
| --- | --- | --- | --- |
| Staging | every push to `main` that touches the landing | `ourio-landing`, production deployment | https://ourio-landing.pages.dev |
| Preview | Actions › Landing › Run workflow, branch, **Preview** | `ourio-landing`, preview of that branch | `https://<branch>.ourio-landing.pages.dev` |
| Production | Actions › Landing › Run workflow, ref, **Production**, then approve | `ourio-landing-prod`, production deployment | https://ourio-landing-prod.pages.dev |

The two buttons:

- **Preview**: pick the branch in "Use workflow from", choose Preview, Run. Pages turns the branch
  into a host name (`feat/landing-ship` becomes `feat-landing-ship`); the run's summary has the URL
  and, when the branch has an open pull request, a comment on it does too. `main` is refused: it
  deploys itself to staging.
- **Production**: pick the branch or tag, choose Production, Run. The job waits for a reviewer of
  the `landing-production` environment, then deploys that ref as the production deployment of
  `ourio-landing-prod`.

Both run lint, typecheck, test and the format check of the landing before they build.

### Setting up, once

1. Repository secrets (Settings › Secrets and variables › Actions):
   - `CLOUDFLARE_API_TOKEN`: an API token with **Account › Cloudflare Pages › Edit** on the account.
   - `CLOUDFLARE_ACCOUNT_ID`: the account's ID.
2. The environment `landing-production` (Settings › Environments) with the owner as a required
   reviewer. `landing-staging` and `landing-preview` are created by the first runs and need no rules.
3. The two Pages projects, from a machine logged in to that account:

   ```sh
   pnpm --filter @billet/landing exec wrangler pages project create ourio-landing --production-branch main
   pnpm --filter @billet/landing exec wrangler pages project create ourio-landing-prod --production-branch main
   ```

A custom domain is added to the project in the Cloudflare dashboard (Workers & Pages › the project
› Custom domains). `ourio-landing-b` is a throwaway preview project, not part of these deploys.
