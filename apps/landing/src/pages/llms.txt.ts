import type { APIRoute } from "astro";
import { appStoreUrl, siteDescription } from "../config";
import { faq } from "../faq";

// The llms.txt convention (llmstxt.org): a plain summary that answer engines can quote without parsing the page.
export const GET: APIRoute = ({ site }) =>
  new Response(
    `# Ourio

> ${siteDescription}

- Website: ${new URL("/", site).href}
- App Store: ${appStoreUrl}
- Platform: iPhone, iOS 18 or later
- Price: free, no in-app purchases at launch

## What you can do

- Pet, feed and play with Mochi, the cat you share. Your partner sees it on their Lock Screen and widget.
- Draw on your partner's Lock Screen; the drawing appears stroke by stroke while you draw.
- Pin notes in your own ink colour to Mochi's wall; a Live Activity shows her carrying the note over.
- Send Moments: photos that arrive as polaroids with your caption.
- Furnish the shared room with coins you both earn by looking after Mochi.
- Read the Inbox: everything the two of you did, by day.

## Questions

${faq.map((item) => `### ${item.question}\n\n${item.answer}`).join("\n\n")}
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
