# Ember

A study-focus timer for iPad (iPadOS 17+): Pomodoro and other techniques, a lock-in mode
that fails the block when you leave the app, and Duolingo-style streaks and celebrations.
Personal project; no Mac needed.

Status: **M0, Lock Lab build.** It measures how iPadOS reports leaving the app versus
locking the screen, before Deep Focus is built on top. The plan is in the session notes.

## Lock Lab test (2 minutes)

Open Ember > Lock Lab and follow the steps on screen: Home and back, a 15 s screen lock,
Control Center, Notification Center, the app switcher, Split View, and a 20 s absence.
Then `python tools\pull_lab.py` copies `locklab.json` to `out\device\` over USB.

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
