# Billet privacy policy

Last updated: 6 November 2026

Billet is a private app for two people to send each other drawings and photos. This policy covers the current test version, distributed through TestFlight.

## What the app handles
- **Sign in with Apple:** you sign in with Apple. We receive an identifier that is unique to our app and stored as your account. We don't receive or store your name or email address.
- **Pairing:** an invite code, valid for 24 hours, links your account to your partner's. We keep only a one-way hash of the code, never the code itself. A pair is exactly two accounts.
- **Devices and sessions:** a random device ID, and a session that keeps you signed in. We keep only a one-way hash of the session token.
- **Notes:** the drawings and photos you send to your partner, with who sent them and when.
- **Onboarding answers:** when you first open the app, a few questions you can each skip: your age range (never your date of birth), how we should talk about you, the name your partner calls you, and what you want to do together. We store your answers, and which questions you skipped, with your account. They shape what the app shows you, and we count across everyone how often each answer is chosen. What you type (the name) is never part of those counts. If you are under 13, the app stops there and your answer is never sent. The day your story started stays on your phone.
- **Pick tonight:** each partner's latest swipe on each film or show in the last 24 hours: which title (its name and poster), the choice (not tonight, seen it or want to) and when. A title you both want is a match, and your partner gets a notification that names it.
- **Who knows who:** for each day's round, which questions it asked, who it was about, and the option each partner picked for each question, with when. Neither of you sees the other's picks until you have both answered every question. We also keep each week's score. When one of you finishes their part, the other gets a notification that names no answer.
- **Push token:** an Apple identifier used to notify your device, if you allow notifications.
- **Usage counts:** how many times each account did a set of named things in the app on a given day, and when it first did each that day, with the app version and iOS version the app reported that day (the same two the usage events below carry). The things are: made an invite, paired, sent a note, opened the app, added a widget, watched or skipped the opening; petted, fed, played with or called the cat, saw a trick or its temperament, chose a cat; opened a note from the widget or in the app; decorated the room (placed, moved or put away a piece); which of the app's rooms was opened; opened the shop, looked at or bought an item, saw an offer, bought a bundle, took a purchase back, took the free gift of the day, bought something for your partner (never the note); opened the streak or saw a milestone; tapped a widget button; opened Pick tonight, got a match there or planned one (never which film or show); opened the profile; whether the app offered Sign in with Apple and how it was answered; which onboarding questions were seen, answered or skipped (never the answer), and whether onboarding stopped because you are under 13. Some of these carry which thing it was (which cat, which shop item or bundle and its price in stamps, which toy, trick or room piece, which widget) as the name of something the app ships, never anything you typed. This is counting only: it never includes what a note says or shows, your name or anything you write, and nothing is sent to anyone else. We use it to see whether the app is working for couples and which parts of it people use. Which things are chosen is also kept as a daily total that is not linked to any account.
- **App version and system:** each request from the app says which version of Billet it is and which iOS version it runs on (for example "1.2.0, iOS 26.1"). It says nothing about you or your phone beyond that. We use it to see whether a version works, and to show a new variant only to versions that have it.
- **Test variants:** to compare two versions of a screen, each pair is placed in one version. Both partners always get the same one. We keep which version each pair was given.

We don't ask for your contacts or location. The app has no ads, and no third-party analytics or tracking: the usage counts and events above are kept on our own backend only, which runs on Cloudflare.

## Where it goes
Everything above is stored on our backend, which runs on Cloudflare.

- **Notes are stored.** The drawing (as strokes and as an image) or photo you send is kept in your pair's private storage so that your partner, and you, can see the history and a new device can catch up. Photos and images are kept in a private storage area reachable only by the two accounts in the pair. Notes are kept for as long as the pair exists, with no automatic expiry. When either of you unpairs or blocks the other, the room is deleted at once for both of you: the notes, photos and drawings, the cat and its journal, and the activity. What you bought is never deleted: each of you keeps a copy of the ink colours and room pieces you had together, and half of your coins, and they go into your next pair. What each of you saved on your own phone stays there.
- **Accounts and pairing data** (account identifier, devices, hashed sessions, hashed invite codes, the link between the two partners, push tokens, onboarding answers) are kept as long as the account exists.
- **Pick tonight swipes** are kept for 24 hours. Older ones are deleted the next time either of you swipes, and all of them are deleted when the pair ends. To suggest titles, our backend asks The Movie Database (TMDB) for titles like the ones on your list, by their TMDB numbers only, never with your account or your partner's.
- **Kept purchases** (your coins and the ink colours and room pieces you bought) are kept for your account after your pair ends, until your next pair has them, and are deleted with your account.
- **Blocks and reports** are kept after the pair or an account ends. A block records which account blocked which, so the two can't pair again; it is deleted with either account. A report records who reported whom, the pair, the reason you chose and the time, so we can act on it; it is kept so we can still act on it after the pair or either account is gone, and you can ask us to delete yours.
- **Usage counts and test variants** are kept as long as the account exists, and are not removed when you unpair.
- **Usage events:** the named things above are also written, one by one, to Cloudflare's analytics storage for our backend (Workers Analytics Engine). Each entry holds the event's name, which thing it was when there is one (and a price in stamps for a purchase), a one-way hash of your pair (never your account, your Apple identifier, your email or your network address), the test variants of your pair, the app version and the iOS version. It holds no location and nothing you draw or write. When an account is deleted, an entry saying so is written, with the same hash and nothing else about the account. Cloudflare keeps these entries for three months, then deletes them. They are not shared with anyone else.
- **Switching it off:** we can switch these usage counts off for everyone at once; the app then stops recording them and deletes the ones it was waiting to send.
- **Abuse protection:** to limit abuse we count requests per minute against a one-way hash of the caller's network address. The address itself is not stored, and counters older than a minute are removed as new requests arrive.
- **Logs:** our server logs record the type of request, whether it succeeded and how long it took, with a pseudonymous reference to the account and couple so one request can be followed. They don't contain note content, tokens, codes, emails, account ids or addresses, and are kept for 7 days.

Notifications are sent through Apple Push Notification service. Apple also provides TestFlight and may share crash reports and usage data with us, as described in its own terms.

We don't sell your data or use it for advertising, and we don't use your drawings or photos to train AI.

## Test rooms
Some test builds exchange notes through a temporary test room instead. A test room is identified by a short code that two devices share, keeps a random device ID per device and an optional push token, and holds up to 50 notes that have not yet reached the other device until they do. Test rooms are not linked to a Sign in with Apple account. A test room also keeps the drawing of the day: each partner's drawing of the day's prompt, for the last 60 days, and the time zone offset each phone last wrote its time in, so the evening reminder comes in your evening and never during quiet hours (22:00 to 08:00). Your partner's drawing of a day is only sent to you once you have drawn yours.

## Your data on your device
The app keeps your session, device ID and recent notes on your device to show them. Deleting the app removes these from your device, but not from our backend.

## Questions and deletion
You can unpair at any time in Settings, which deletes the room you shared, and delete your account there too: that removes your account and the notes and photos you sent from our backend, and your partner is unpaired. To ask about your data, or to have a report deleted, email gimpelllll@gmail.com.

## App Privacy answers for App Store Connect

Not part of the policy shown to users: the answers to give in App Store Connect > App Privacy, kept here so they stay in step with the policy above.

- **Tracking:** No. Nothing is linked with data from other companies' apps or websites, and nothing is shared with data brokers or ad networks. The app does not show the App Tracking Transparency prompt and does not need to.
- **Usage Data > Product Interaction:** Collected. Linked to the user (the counts are stored per account). Not used for tracking. Purpose: Analytics only. These are the usage counts and events above.
- **Identifiers > User ID:** Collected, linked to the user, not used for tracking, for App Functionality (the account behind Sign in with Apple and the session).
- **Identifiers > Device ID:** Collected, linked to the user, not used for tracking, for App Functionality (the random device ID). It is not the advertising identifier.
- **User Content > Photos or Videos, Other User Content:** Collected, linked to the user, not used for tracking, for App Functionality (the notes you send, Pick tonight swipes, and Who knows who answers).
- **Diagnostics:** Only what Apple provides through TestFlight and App Store crash reports; the app adds no diagnostics SDK.
- **Not collected:** contact info (name, email, phone), location, contacts, browsing or search history, purchases (coins are earned in the app; buying them is off in this release; revisit this answer when they can be bought), financial info, health, sensitive info.

Change these answers whenever the list of usage counts or what they carry changes: see `docs/analytics.md`.
