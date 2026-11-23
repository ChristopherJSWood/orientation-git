# Bedtime or Bust: Design Notes

## 1. What the satire is aimed at

Satire needs a target. Without one, a toddler game is slapstick about a small child, and the joke lands on the child. Here the toddler is the weather: irrational, unstoppable and blameless. The satire is aimed at the adult world around the parent:

| Target | How it shows up |
|---|---|
| Contradictory expert advice | "Experts Say" cards: one study says say "no" less, another says more |
| Parenting influencers and the content economy | Staged photos ("Slow mornings 🤍"), beige toys, a $89 wooden rainbow the toddler ignores for the box |
| Gentle-parenting scripts used as incantations | "I hear that you're sad the banana broke." (Sometimes it works; the game is fair to the method.) |
| Social surveillance between parents | The Reputation meter, the group chat, playground hall monitors, birthday-party registries |
| Work culture that assumes no children exist | "Cameras on, it's a culture thing." |
| Consumer marketing aimed at toddlers | Cereal shelved at exactly the eye height of a seated toddler |

**Lines the content does not cross** (enforced in review, see `CONTENT_GUIDE.md`): the toddler is never hurt and never the punchline of cruelty; no outcome rewards neglect; real safety practice is modeled straight (furniture anchoring, dosing "exactly as the label directs", "Keep using the car seat"); no real brands, shows or people. Apple's guideline 1.1.1 exempts "professional political satirists and humorists" from its mean-spirited-content rule ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). The game should not lean on that exemption; it should stay out of that territory altogether.

## 2. Core loop and why each mechanic exists

1. **A card appears.** It is either forced (wake-up, breakfast, nap, dinner, bath, bedtime, meltdown) or drawn at random, weighted, from the events whose time window and conditions fit.
2. **You choose.** Each choice has a visible time cost and hidden effects. Some have random outcomes (the triangle toast lands butter-side down 70% of the time).
3. **Time passes:** the choice's duration plus a 15-minute gap for the rest of life. Passive drift applies: sleepiness rises, sanity, house and reputation erode.
4. **Repeat until bedtime or a meter breaks.**

Mechanics that model real parenting dynamics (the satire is funnier when the systems are true):

- **The nap trade-off.** Skip the nap and the afternoon is a mood disaster: past 80 sleepiness, mood drains 1 point per 10 minutes. Take a late "danger nap" in the car at 5 PM and bedtime fails. Most children nap until somewhere between ages 3 and 5: fewer than 2.5% stop before age 2, and 94% have stopped by age 5 ([Staton et al., 2020, *Sleep Med Rev*](https://doi.org/10.1016/j.smrv.2019.101247)). So for this age group the nap is a real daily decision.
- **Meltdowns are survivable.** Mood at zero triggers a meltdown card rather than a loss. 83.7% of preschoolers have tantrums at least sometimes, but only 8.6% have them daily ([Wakschlag et al., 2012, *J Child Psychol Psychiatry*](https://doi.org/10.1111/j.1469-7610.2012.02595.x)). The most common length is 30 seconds to a minute, and 75% end within 5 minutes ([Potegal, Kosorok & Davidson, 2003, *J Dev Behav Pediatr*](https://doi.org/10.1097/00004703-200306000-00003)). The card text ("Most last only a few minutes. This one felt like a fiscal quarter.") follows that finding.
- **Sanity is the binding constraint.** Parental burnout is a measurable construct ([Roskam, Brianda & Mikolajczak, 2018, *Front Psychol*](https://doi.org/10.3389/fpsyg.2018.00758)). A 42-country study put prevalence at 0% to 9.8% depending on the country, with the USA at 8.9% ([Roskam et al., 2021, *Affect Sci*](https://doi.org/10.1007/s42761-020-00028-4)). Parents' sleep does not fully recover for years after a first child ([Richter et al., 2019, *Sleep*](https://doi.org/10.1093/sleep/zsz015)). The "Sleep Regression" day starts you at minus 15 sanity for that reason.
- **Food refusal is the norm, not a failure.** Pooled picky-eating prevalence is about 22% in children up to 30 months old ([Cole et al., 2017, *Nutr Rev*](https://doi.org/10.1093/nutrit/nux024)). In one cohort it peaked at 27.6% at age 3 ([Cardona Cano et al., 2015, *Int J Eat Disord*](https://doi.org/10.1002/eat.22384)). Dinner is therefore a forced event, and no dinner choice is safe.

## 3. Balance: tuned by simulation, not by feel

`tools/simulate.mjs` plays 4,000 seeded days with each of four scripted players and turns the targets into a CI gate (`--check`). Results for the current content:

| Player | Win rate | Typical outcome |
|---|---|---|
| Random choices | 61.6% | 40.7% "Survived", 20.2% sanity meltdown, 10.7% house loss, 5.7% second wind |
| Always first option | 35.3% | 64.5% sanity meltdown |
| Careful player (perfect knowledge of hidden numbers, cautious utility) | 100% | only 14.0% reach the top grade |
| Deliberately bad | 3.8% | median loss at 3:48 PM |

About 30 decisions per day, roughly a 5-minute session.

How the simulator changed the design (each change was measured, not guessed):

1. **First draft:** 85 decisions per day and a 94% house-loss rate for random play. Choices were too short to fill a 13.5-hour day. **Fix:** a fixed 15-minute gap after every event.
2. **Too easy afterwards:** 93.5% random win rate, and the bedtime check almost never failed. **Fix:** sleepiness rises every 12 minutes instead of every 10, and sanity drains every 20 minutes instead of every 30.
3. **One-meter game:** only sanity ever ended a day, and reputation finished above its starting value. **Fix:** passive drain on House (every 30 min) and Reputation (every 40 min). All four loss types now occur.
4. **Eleven strictly dominated choices**, options worse on every meter than a sibling, so not real dilemmas. **Fix:** each got a distinct upside. The static check now reports none.

Known balance limitations:
- **Modifiers are uneven.** Random-play win rate ranges from 51% (Sleep Regression, Potty Training) to 68% (Normal Day). That variety may be fine; it is worth playtesting.
- **The careful player wins 100%.** It sees the hidden numbers, which humans don't. Real players fall between "random" and "careful". Only human playtesting can place them; see §6.
- **Seven events have a clear best choice** for the careful player (for example, the backup lovey). They are kept as jokes, and the simulator lists them each run.

## 4. Architecture

```
content.json ──► BedtimeCore (Swift) ──► SwiftUI app
     │                ▲
     │       golden traces (40 days)
     ▼                │
 engine.mjs (JS) ─────┘──► simulator, linter, browser playtest build
```

- **Data-driven content.** Writers edit JSON, not Swift. That keeps the comedy separate from the code, which is the only practical way to scale to hundreds of events.
- **Deterministic engine.** Seed + choices fully determine a day. Save files are tiny, bugs are reproducible from a seed, and the same day can be replayed exactly.
- **Value-type state.** `GameState` is a `Codable` struct, including the RNG state. The app saves after every choice, and iOS can kill the app in the background without losing the day.

## 5. Risks and mitigations

| Risk | Mitigation | How it's monitored |
|---|---|---|
| The two engines drift apart | Golden traces replayed by Swift tests; CI fails on any stale fixture | CI job `ios` (Swift) + `golden.mjs --check` |
| A content edit breaks balance | Win-rate bands enforced in CI | `simulate.mjs --check` |
| A content edit crashes the app | Swift refuses invalid content at load and shows an error screen instead of crashing. The linter catches unknown meters, bad windows, undeclared counters and unreachable flags | `validate.mjs`, `ContentTests.swift` |
| An update invalidates a saved day | Saves carry `contentVersion`; a mismatched or dangling save is discarded and a new day starts | `GameStore.resume()` |
| The satire reads as mocking children or a group | Content rules in §1 and `CONTENT_GUIDE.md`; review every new event against them | Human review checklist |
| App Review rejects it as "minimum functionality" (4.2) or a copycat (4.3) | Native SwiftUI (not a web wrapper), original writing, real systems depth. 4.3 rejects apps "indistinguishable from what's already widely available" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)) | Pre-submission review of 4.2 and 4.3 |
| Wrong store category | Do **not** list in the Kids Category, and don't use "for kids" in metadata. 2.3.8 reserves those terms for the Kids Category. The audience is adults | Metadata checklist |
| Age rating | Apple's tiers are 4+, 9+, 13+, 16+, 18+ ([Apple, July 2025](https://developer.apple.com/news/?id=ks775ehf)). Expect 9+ or 13+ for mild crude humor (diapers); answer the questionnaire honestly | App Store Connect questionnaire |
| Working title collides with an existing app | Search the App Store and USPTO TESS before committing to the name | Before buying a domain or icon |

## 6. What is not yet known (and how to find out)

- **Whether it's funny to people who aren't me.** Run 5 to 8 parents through the browser build. Record which cards make them laugh, which they skip, and where they quit. Cut or rewrite the bottom 20%.
- **Where human win rates land.** Add anonymous, opt-in logging to the prototype (seed + choices is already the whole save format), or just watch over shoulders.
- **Session-length retention.** A 5-minute day suits commuting and naptime. Multi-day progression is the main retention bet (§7).

## 7. Roadmap (in priority order)

1. **Human playtest** of the browser build (§6).
2. **App icon and launch art.** Required for App Store submission; the project ships without an asset catalog.
3. **Content to about 120 events,** so a week of play rarely repeats a card. The simulator's "events never seen" report guards reachability.
4. **A week mode:** Monday to Friday, meters carry over partially, Friday "date night" as the boss. This is the main retention mechanic.
5. **Accessibility pass:** VoiceOver order on the HUD, Dynamic Type at the largest sizes, haptics toggle.
6. **Localization:** satire is culturally specific (the group chat, daycare norms), so adapt the writing rather than translating it.
