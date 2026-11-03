# Billet privacy policy

Last updated: 3 November 2026

Billet is a private app for two people to send each other drawings and photos. This policy covers the current test version, distributed through TestFlight.

## What the app handles
- **Sign in with Apple:** you sign in with Apple. We receive an identifier that is unique to our app and stored as your account. We don't receive or store your name or email address.
- **Pairing:** an invite code, valid for 24 hours, links your account to your partner's. We keep only a one-way hash of the code, never the code itself. A pair is exactly two accounts.
- **Devices and sessions:** a random device ID, and a session that keeps you signed in. We keep only a one-way hash of the session token.
- **Notes:** the drawings and photos you send to your partner, with who sent them and when.
- **Push token:** an Apple identifier used to notify your device, if you allow notifications.
- **Usage counts:** how many times each account did a few named things on a given day (made an invite, paired, sent a note, opened the app, added a widget, watched or skipped the opening), and when it first did each that day. This is counting only: it never includes what a note says or shows, and nothing is sent to anyone else. We use it to see whether the app is working for couples.
- **App version and system:** each request from the app says which version of Billet it is and which iOS version it runs on (for example "1.2.0, iOS 26.1"). It says nothing about you or your phone beyond that. We use it to see whether a version works, and to show a new variant only to versions that have it.
- **Test variants:** to compare two versions of a screen, each pair is placed in one version. Both partners always get the same one. We keep which version each pair was given.

We don't ask for your contacts or location. The app has no ads, and no third-party analytics or tracking: the usage counts and events above are kept on our own backend only, which runs on Cloudflare.

## Where it goes
Everything above is stored on our backend, which runs on Cloudflare.

- **Notes are stored.** The drawing (as strokes and as an image) or photo you send is kept in your pair's private storage so that your partner, and you, can see the history and a new device can catch up. Photos and images are kept in a private storage area reachable only by the two accounts in the pair. Notes are kept for as long as the pair exists. There is no automatic expiry.
- **Accounts and pairing data** (account identifier, devices, hashed sessions, hashed invite codes, the link between the two partners, push tokens) are kept as long as the account exists.
- **Usage counts and test variants** are kept as long as the account exists, and are not removed when you unpair.
- **Usage events:** the named things the app reports about itself (opened, widget added, opening watched or skipped) are also written, one by one, to Cloudflare's analytics storage for our backend (Workers Analytics Engine). Each entry holds the event's name, a one-way hash of your pair (never your account, your Apple identifier, your email or your network address), the test variants of your pair, the app version and the iOS version. It holds no location and nothing you draw or write. Cloudflare keeps these entries for three months, then deletes them. They are not shared with anyone else.
- **Abuse protection:** to limit abuse we count requests per minute against a one-way hash of the caller's network address. The address itself is not stored, and counters older than a minute are removed as new requests arrive.
- **Logs:** our server logs record the type of request, whether it succeeded and how long it took. They don't contain note content, tokens, codes or addresses.

Notifications are sent through Apple Push Notification service. Apple also provides TestFlight and may share crash reports and usage data with us, as described in its own terms.

We don't sell your data or use it for advertising, and we don't use your drawings or photos to train AI.

## Test rooms
Some test builds exchange notes through a temporary test room instead. A test room is identified by a short code that two devices share, keeps a random device ID per device and an optional push token, and holds up to 50 notes that have not yet reached the other device until they do. Test rooms are not linked to a Sign in with Apple account.

## Your data on your device
The app keeps your session, device ID and recent notes on your device to show them. Deleting the app removes these from your device, but not from our backend.

## Questions and deletion
You can sign out at any time, and unpairing removes the link between you and your partner. In this test version unpairing doesn't yet delete the notes that were stored, and an in-app way to delete your account doesn't exist yet. To have your account and everything stored for it deleted, or to ask about your data, email gimpelllll@gmail.com.
