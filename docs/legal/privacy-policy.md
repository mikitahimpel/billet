# Billet privacy policy (release draft)

> Draft for the first App Store release. Not legal advice: have it read by someone qualified, fill in the controller's name and address, and host it at a public URL before submitting. It follows what the code collects as of this branch; `docs/privacy.md` is the policy of the TestFlight test version.

Last updated: <DATE OF RELEASE>

Billet is a private app for two people to send each other drawings and photos. This policy covers Billet on the App Store.

## What the app handles
- **Your account:** the app creates an anonymous account with a key kept in your iCloud Keychain. There is no password and we never see your name or email address. If you choose "Save your cat and notes", you link the account to Sign in with Apple, and we then also keep an identifier that is unique to our app. We don't receive or store your name or email address from Apple.
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

- **Notes are stored.** The drawing (as strokes and as an image) or photo you send is kept in your pair's private storage so that your partner, and you, can see the history and a new device can catch up. Photos and images are kept in a private storage area reachable only by the two accounts in the pair. Notes are kept for as long as the pair exists. There is no automatic expiry.
- **Accounts and pairing data** (account identifier, devices, hashed sessions, hashed invite codes, the link between the two partners, push tokens, onboarding answers) are kept as long as the account exists.
- **Pick tonight swipes** are kept for 24 hours. Older ones are deleted the next time either of you swipes, and all of them are deleted when the pair ends. To suggest titles, our backend asks The Movie Database (TMDB) for titles like the ones on your list, by their TMDB numbers only, never with your account or your partner's.
- **Usage counts and test variants** are kept as long as the account exists, and are not removed when you unpair.
- **Usage events:** the named things above are also written, one by one, to Cloudflare's analytics storage for our backend (Workers Analytics Engine). Each entry holds the event's name, which thing it was when there is one (and a price in stamps for a purchase), a one-way hash of your pair (never your account, your Apple identifier, your email or your network address), the test variants of your pair, the app version and the iOS version. It holds no location and nothing you draw or write. When an account is deleted, an entry saying so is written, with the same hash and nothing else about the account. Cloudflare keeps these entries for three months, then deletes them. They are not shared with anyone else.
- **Switching it off:** we can switch these usage counts off for everyone at once; the app then stops recording them and deletes the ones it was waiting to send.
- **Abuse protection:** to limit abuse we count requests per minute against a one-way hash of the caller's network address. The address itself is not stored, and counters older than a minute are removed as new requests arrive.
- **Logs:** our server logs record the type of request, whether it succeeded and how long it took, with a pseudonymous reference to the account and couple so one request can be followed. They don't contain note content, tokens, codes, emails, account ids or addresses, and are kept for 7 days.

Notifications are sent through Apple Push Notification service. Apple may share crash reports and usage data with us, as described in its own terms.

We don't sell your data or use it for advertising, and we don't use your drawings or photos to train AI.

## Your data on your device
The app keeps your session, device ID and recent notes on your device to show them. Deleting the app removes these from your device, but not from our backend.

## Questions and deletion
You can sign out at any time, and unpairing removes the link between you and your partner. <TO CONFIRM BEFORE RELEASE: in-app account deletion, which deletes your account, notes, photos and pair data and revokes the Apple token. Until the app has it, App Review will reject the app (guideline 5.1.1(v)).> A report you or your partner sent us about the other is kept after either account is deleted, so we can still act on it. To ask about your data, or to have a report deleted, email gimpelllll@gmail.com.

## Children
The app asks your age range on first launch. If you are under 13, the app stops there, your answer is never sent and no account data is kept for you.

## Changes
We will say here when this policy changes, and change the date above.
