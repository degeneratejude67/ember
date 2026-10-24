# Ember

A study-focus timer for iPad (iPadOS 17+): Pomodoro and other techniques, a lock-in mode
that ends the block when you leave the app, and Duolingo-style streaks and celebrations.
Personal project; no Mac needed.

## What it does

- **Techniques:** Pomodoro 25/5 (long break after 4), Deep 50/10, 52/17, Ultradian 90/20,
  Flowtime (break = focus/5), Mock exam (one long block with time checks, then your score),
  "Just 5 minutes" (turns into Flowtime), and Custom.
- **Each block:** a goal line before you start, a Time Timer-style disc, a parking lot for
  distracting thoughts, optional white/pink/brown noise, and a dim screen after 30 s.
- **Lock:**
  - Deep Focus: leaving Ember for longer than the grace time (10 s) ends the block.
    Locking the screen and Split View are fine.
  - Lock In: Guided Access pins the iPad to Ember.
  - Study in another app: time in CollaNote, Slate, Edge or Files counts as focus.
  - Focus Guard (a Shortcuts automation): YouTube, Instagram and games bounce you back.
  - Relaxed: timer only.
- **Rewards:**
  - Streak: one block of 10+ minutes a day. Two freezes, and earn-back after a missed day.
  - Daily goal, XP and ranks.
  - Ember the flame, which changes colour with the streak.
  - A celebration at the end of each block: block complete, streak, goal, rank-up.
- **Also:** exams with countdowns and hours studied, a progress screen with a 7-day chart
  and history, streak reminders on days you haven't studied, a re-sign reminder, and
  JSON export.

## Lock Lab

Settings > Lock Lab shows how iPadOS reports leaving the app versus locking the screen, and
judges each absence. `python tools\pull_lab.py` copies `locklab.json` (and the other data
files) to `out\device\` over USB.

## Build

GitHub Actions (`.github/workflows/build.yml`) generates the Xcode project with XcodeGen,
builds an unsigned `Ember.ipa`, and runs the unit and UI tests on an iPad simulator (and
the compact-width tour on an iPhone simulator). Screenshots are in the `test-output`
artifact.

Sounds and the icon are generated: `python tools\make_sounds.py`, `python tools\make_icon.py`.

## Install and re-sign from Windows

1. `tools\fetch.ps1` downloads the newest build into `out\`.
2. In iloader, choose Import IPA and pick that `Ember.ipa`. The iPad must be plugged in.

A free Apple ID signature lasts 7 days. Re-sign Ember and Slate together; the
"Slate re-sign reminder" task reminds you for both. Your data is kept when you re-sign.

## Data

Files > On My iPad > Ember: `ember.json` (everything), `active.json` (the running block),
`Backups/` (one per day, kept 7 days), `locklab.json`.
