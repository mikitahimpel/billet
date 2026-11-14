# Landing

The marketing site, `apps/landing`: a static Astro build served by Cloudflare Pages. Every route
is listed once in `src/site.ts`; the copy lives in `src/config.ts`, `features.ts`, `faq.ts`,
`compare.ts` and `dates.ts`. The look is `src/styles/global.css`; each page's first-screen rules
are a subset of it in `src/styles/critical/<page>.css` (`/` is `index`, `/features/games/` is
`features-games`), inlined minified with the fonts of `critical/fonts.css`. The home page's set
stays under 15 KB. A rule changed in `global.css` is changed in the critical files that hold it.

Images are pre-encoded and ship byte for byte under hashed names: room renders and close-ups
(`crop-*`) in `src/assets/room` through `roomAsset()` and `src/lib/crops.ts`, shop pieces in
`src/assets/props` through `src/lib/shop.ts`. A phone whose screen still shows a close-up has
`data-shot="<page>-<n>"`: that is the app screenshot it waits for.

```sh
pnpm --filter @billet/landing dev     # http://pc:4321 with --host 0.0.0.0
pnpm --filter @billet/landing build   # apps/landing/dist, with a Markdown twin beside every page
```

## Markdown twins

The build writes `index.md` beside every page. `functions/_middleware.js` serves it at the page's
own URL to a request that asks for `text/markdown`, names it in each page's `Link` header, and
sends `X-Robots-Tag: noindex` on every `*.pages.dev` host, so only the custom domain is indexed.

## ourio.app

ourio.app and www.ourio.app are custom domains of the Pages project `ourio-landing-prod` in the
Cloudflare account that holds the ourio.app zone (https://ourio-landing-prod-1ym.pages.dev). The
workflow's Production target is the repository's account, so a production release is deployed from
a machine logged in to the zone's account:

```sh
pnpm --filter @billet/landing build
cd apps/landing && pnpm exec wrangler pages deploy dist --project-name ourio-landing-prod --branch main
pnpm --filter @billet/landing indexnow https://ourio.app/<changed>/   # changed URLs only; --all after a site-wide change
```

The middleware sends www.ourio.app to ourio.app with a 301.

## Images

The room render and Mochi's loop are pre-sized in `src/assets/room/` (AVIF and WebP at 1000, 1600
and 2560 px; the loop at 80 and 140 px) and imported as URLs through `src/lib/room-assets.ts`, so
the build hashes their names without re-encoding them. Art, screenshots, date ideas and shop items
stay in `src/assets/` at their source size; the build makes their WebP steps. No multi-megabyte PNG
is shipped.

Only `/_astro/` is cached for good, because every name there carries a content hash; every other
file keeps Pages' default and is revalidated on each visit (`public/_headers`). So `public/` holds
only files that must keep their name (the icons, `og.png`, `_headers`), and `scripts/check-public.mjs` fails the build on
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
