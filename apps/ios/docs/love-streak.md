# Love Streak

A flame on the Us tab that grows every day the couple does something together in Ourio. Modelled on TikTok's DM
streaks, made gentler to fit engagement-concept.md (no fear-of-loss pushes).

## How TikTok streaks work

- **A streak day.** Two people message each other in a DM or group chat on consecutive days. The badge shows up after
  3 days in a row [1][2]. The sources don't say whether both people have to send each day.
- **Display.** A badge with the day count sits at the top of the chat (people call it the flame). Tapping it opens
  Streak Pets [1][2].
- **About to expire.** If nobody messages before the day ends, the badge fades (goes grey) and a notification says the
  streak is about to end. Both can be turned off under Settings › Notifications › Streaks [1][3].
- **Lost.** After another day with no message, the streak ends and the badge disappears, so there's about one day of
  grace [1][3].
- **Restore.** Tap Restore in the chat within 48 hours of the streak ending. Everyone gets a limited number of restores
  a month, and a restore brings back the original count and any Streak Pet [1][3].
- **Milestones.** No official colour tiers are documented. Users report the flame turning purple around day 100 [4],
  which is unverified.

1. TikTok Help — Streaks: https://support.tiktok.com/en/using-tiktok/messaging-and-notifications/streaks
2. TechCrunch, June 2024: https://techcrunch.com/?p=2790702
3. Dexerto — How to restore a streak on TikTok: https://www.dexerto.com/tiktok/how-to-restore-a-streak-on-tiktok-2971154
4. TikTok Discover (user pages): https://www.tiktok.com/discover/what-color-is-100-day-streak

## The couple version

- **A streak day** is any day either partner does one of these in the app: pets or treats Mochi (pets from the widget
  count too), adds a moment, pins a note or doodle, swipes a date idea, or checks in a mood. The first one of the day
  adds a flame. There's no daily question in the app yet; once there is, answering it should count as well.
- **Card** (top of the Us tab, under the countdown): flame and day count, best streak, the milestone badge, and a bar
  showing progress to the next milestone.
- **Today done:** the flame is lit and a small "today ✓" pill shows.
- **Streak at risk:** yesterday counted but today hasn't yet. The flame fades like TikTok's, and the card says how many
  hours are left, without guilt-tripping. No push notification.
- **Lost:** after a whole missed day, the count shows 0 and the best streak stays.
- **Restore:** a streak of 3+ days that missed exactly one day can be restored for free, once every 30 days. That
  matches TikTok's 48-hour window and monthly limit. A restore fills in the missed day, and today's first action carries
  the streak on.
- **Milestones:** 3, 7, 14, 30, 50, 100, 200, 365 days. The flame warms from orange to pink at 30 and to purple at 100
  (the purple-at-100 that users talk about).

Code: `Shared/Model/Streak.swift` (model and store, `Us/streak.json` in the app group); the card is in
`Nooki/UI/Us/StreakCard.swift`.
