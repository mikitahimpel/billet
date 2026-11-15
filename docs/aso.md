# App Store optimization (ASO)

The search and conversion choices for the App Store listing, English (U.S.). The full listing text
(description, privacy answers, review notes) is [legal/app-store-listing.md](legal/app-store-listing.md);
where the two differ, this page is the newer decision (name and subtitle).

## What the market looks like (read 2026-11-15)

Shared-pet and couples-widget apps are crowded: Petiverse, PetTomo, Pookie, Lovemoe, Waddle, Nestly,
Cozy Couples, Widgetable, Paint Love, Together, UsTwo. Most are free with in-app purchases. Their names
and subtitles lean on the same words: *couples, widget, long distance, draw together, lock screen, notes,
pet*. This is a read of their store pages, not keyword-volume data (that needs AppTweak or Sensor Tower).

Rules that decide the layout (vendor guides, not Apple documentation; check App Store Connect's metadata
help): name 30, subtitle 30 and keywords 100 characters; the name weighs most, then the subtitle, then the
keyword field; words are combined across the three fields, so a word is written once; the keyword field is
comma-separated without spaces; singular forms are enough; the category names are indexed too; the
description does not carry search weight.

## The fields

| Field | Value | Length |
| --- | --- | --- |
| Name | `Ourio: Couple Cat & Widgets` | 27 / 30 |
| Subtitle | `Raise a pet, draw love notes` | 28 / 30 |
| Keywords | `long,distance,relationship,games,calendar,questions,together,shared,drawing,lock,screen,doodle,cozy` | 99 / 100 |
| Promotional text | Share one cozy room and a cat with the person you love. Pet her, draw a note, and it appears on their widget. Made for couples, near or far. | 140 / 170 |
| Primary / secondary category | Lifestyle / Entertainment | |

The name replaces the plain `Ourio` of the first draft: it adds *couple*, *cat* and *widgets*. The
subtitle adds *raise*, *pet*, *love* and *notes* (decided from [aso-research.md](aso-research.md): *love
notes* and *drawing widget* are the winnable terms, *long distance* is crowded). *long* and *distance*
moved to the keyword field; `girlfriend` and `boyfriend` were dropped because their results are AI-companion
apps. No word is repeated across the three fields. The promotional text can be changed at any time without a new build; the name, subtitle, keywords
and screenshots change with a version.

## Screenshots

The first three show in search results, so they carry the pitch. Order and captions:

1. A cat you raise together (Living room)
2. Draw a note, see it on their widget
3. Decorate your shared home
4. Play with your cat (games)
5. Fresh finds in the shop
6. Keep your streak going

Sizes: 6.9-inch (1320 x 2868) and 6.5-inch; the generator is `tools/appstore-shots`.

## Honesty limits

No caption or text may promise what the app does not do: no account recovery through Apple on a fresh
install, no drawing set as a lock screen wallpaper (a drawn note appears on the partner's widget),
no payments before `payments` is switched on.

## After the release

- Product Page Optimization: test the first screenshot and the icon.
- More locales (en-GB, de, fr, es): the keyword field is indexed per locale, so translate the same ideas,
  do not copy the English words.
- Ask for a rating once, after a 7-day streak, never on first launch.
- Answer every review in the first month.
- Track rank for *couples widget*, *long distance*, *shared pet*, *couple cat* weekly.
