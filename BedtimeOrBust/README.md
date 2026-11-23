# Bedtime or Bust

A satirical iOS game. You are a parent. Your goal is to get through one day with your toddler, from the 5:58 AM monitor crackle to bedtime at 7:30 PM, without losing your sanity, your house, or your standing in the parents' group chat.

- **Platform:** iOS 17+ (iPhone and iPad), SwiftUI
- **Status:** playable vertical slice: 46 events, 7 day types, 8 endings
- **Play it in a browser now:** open `prototype/index.html`. It runs the same rules and content as the iOS app.

## How a day works

Each card is a moment of your day with two or three choices. Every choice costs time and moves five meters:

| Meter | Hits zero → | Notes |
|---|---|---|
| Sanity | **Game over** (you're in the pantry) | Drains 1 point per 20 minutes on its own |
| Toddler Mood | A meltdown event (survivable, costly) | Drops fast once the toddler is overtired |
| House | **Game over** (the house is condemned) | Drains 1 point per 30 minutes: toddlers make mess |
| Reputation | **Game over** (removed from the group chat) | Drains 1 point per 40 minutes: the chat forgets you |
| Sleepiness | — | Rises all day; naps lower it. Must be 50+ at bedtime, 80+ means overtired |

Reach bedtime with a sleepy toddler and the day is graded on Sanity + Mood + House + Reputation (out of 400). A random daily modifier (Teething, Grandma Is Visiting, Potty Training: Day 3…) changes the starting meters and unlocks its own events.

## Run it on a Mac

You need a Mac with **Xcode 26 or later** (free on the Mac App Store). Apple has required apps uploaded to the App Store to be built with Xcode 26 and the iOS 26 SDK since April 28, 2026 ([Apple](https://developer.apple.com/news/upcoming-requirements/)).

```sh
brew install xcodegen          # one time; generates the Xcode project from project.yml
cd BedtimeOrBust
xcodegen generate              # creates BedtimeOrBust.xcodeproj
open BedtimeOrBust.xcodeproj   # pick an iPhone simulator, press ⌘R
```

To run on your own iPhone, select your phone as the run destination and choose your Apple ID under *Signing & Capabilities*. A free Apple ID works for personal testing. Shipping to the App Store needs the Apple Developer Program, which costs 99 USD a year ([Apple](https://developer.apple.com/programs/whats-included/)).

Engine tests (no simulator needed): `swift test --package-path Core`

## Project layout

```
BedtimeOrBust/
├── App/                      SwiftUI app: screens, GameStore (flow + save/resume)
├── Core/                     Swift package "BedtimeCore": the rules engine, Foundation only
│   ├── Sources/BedtimeCore/
│   │   ├── Engine.swift      rules, time, drift, endings
│   │   ├── Content.swift     data model for content.json
│   │   └── Resources/content.json   ALL game text and numbers
│   └── Tests/                unit tests + golden-trace conformance tests
├── tools/                    Node scripts (no npm install needed; Node 18+)
│   ├── engine.mjs            reference rules engine (the executable spec)
│   ├── validate.mjs          content linter
│   ├── simulate.mjs          balance simulator (thousands of seeded days)
│   ├── golden.mjs            records traces the Swift tests replay
│   └── build-prototype.mjs   builds the browser playtest page
├── prototype/                single-file web playtest build
├── docs/DESIGN.md            design rationale, balance data, risks, roadmap
├── docs/CONTENT_GUIDE.md     how to write events
└── project.yml               XcodeGen spec for the iOS app
```

## Changing the game

All writing and tuning lives in `Core/Sources/BedtimeCore/Resources/content.json`. After editing it:

```sh
node tools/validate.mjs            # catches typos, unknown meters, bad windows
node tools/simulate.mjs            # are the win rates still in the target bands?
node tools/golden.mjs              # refresh the Swift conformance fixture
node tools/build-prototype.mjs     # refresh the browser build
```

CI (`.github/workflows/bedtime-or-bust.yml`) runs all four checks, then the Swift tests and an iOS Simulator build on a macOS runner. **This repository is a fork, and GitHub does not run workflows in forks until you enable Actions in the repository's Actions tab** ([GitHub Docs](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)).

## Why two engines?

The rules exist twice: in Swift for the app, and in JavaScript (`tools/engine.mjs`) for the simulator and the browser build. Duplication can drift, so it is fenced in. Both use the same 32-bit RNG (mulberry32), and `golden.mjs` records 40 complete seeded days (1,127 decisions) from the JavaScript engine. `ConformanceTests.swift` replays every one and fails on the first differing event, outcome, clock value or meter. If you change a rule, change it in both files and regenerate the traces.
