# Writing Content

Everything players read, and every number they're affected by, is in `Core/Sources/BedtimeCore/Resources/content.json`.

## An event

```json
{
  "id": "banana",                       // unique, lowercase
  "title": "The Broken Banana",         // ≤ 40 characters
  "text": "You peeled the banana...",   // ≤ 280 characters; one breath
  "window": [420, 1080],                // clock minutes it can appear: 7:00 AM to 6:00 PM
  "weight": 2,                          // relative odds of being drawn (default 1)
  "repeatable": false,                  // can it appear twice in a day? (default false)
  "when": { "flags": ["teething"] },    // optional: only on some days / states
  "choices": [
    {
      "label": "Try to tape the banana back together",   // ≤ 70 characters
      "duration": 10,                                     // minutes, ≥ 1
      "outcomes": [                                       // one is drawn by weight
        { "weight": 1, "text": "...", "effects": { "mood": 14, "rep": 4 } },
        { "weight": 1, "text": "...", "effects": { "mood": -10, "sanity": -4 },
          "set": ["bananaGate"], "count": { "gentle": 1 } }
      ]
    }
  ]
}
```

Clock minutes: 360 = 6:00 AM, 720 = noon, 1020 = 5:00 PM, 1170 = 7:30 PM.

- **Meters** for `effects`, `min` and `max`: `sanity`, `mood`, `home`, `rep`, `sleepy`. Values are clamped to 0–100.
- **Conditions** (`when` on an event or a choice): `flags` (all required), `notFlags` (none allowed), `min` / `max` (meter bounds). A choice with an unmet `when` is hidden, and every event needs at least one unconditional choice.
- **Flags** are set by day modifiers (`teething`, `grandma`, `soloParent`, `potty`, `germs`) and by outcomes (`set` / `clear`).
- **Counters** (`count`) feed the end-of-day receipt and must be declared in the top-level `counters` list.
- **Special events:** `priority > 0` forces an event as soon as it is eligible (wake, meals, nap, bedtime); `filler: true` is the fallback when nothing else fits; `final: true` ends and grades the day.

## Writing rules

1. **Punch up or sideways, never down at the child.** The toddler is a force of nature, not a villain. Aim the joke at the adult world (advice, influencers, judgment, work, marketing) or at the parent's own coping.
2. **No harm, no neglect as a "win".** No outcome injures the toddler. No choice that would be unsafe in real life is ever the best option. When safety comes up, model the real practice and make it the joke's straight man ("Keep using the car seat.").
3. **No real brands, shows, influencers or people.** Parody types, not individuals ("a man in an alarming amount of corduroy").
4. **Every choice needs a real upside.** If one choice is better on every meter, it isn't a decision. `simulate.mjs` flags dominated choices and fails CI on them.
5. **Short.** Players read on a phone, often one-handed, often while holding a toddler. One idea per card, deadpan delivery, specific numbers ("34 whys", "$3.49").
6. **Facts must be true.** "Experts Say" cards cite real guidance:
   - 11–14 hours of sleep per 24 hours (naps included) for ages 1–2: American Academy of Sleep Medicine consensus ([Paruthi et al., 2016, *J Clin Sleep Med*](https://doi.org/10.5664/jcsm.5866)). *To confirm:* the PubMed abstract does not list the ranges; check the table in the full text before shipping.
   - 8–10 or more tries before a new food is accepted: systematic review of 21 studies in infants and toddlers aged 4–24 months ([Spill et al., 2019, *Am J Clin Nutr*](https://doi.org/10.1093/ajcn/nqy308)); see also the [2025 USDA Dietary Guidelines review](https://nesr.usda.gov/2025-dietary-guidelines-advisory-committee-systematic-reviews/repeated-exposure_acceptance).

## After editing

```sh
node tools/validate.mjs && node tools/simulate.mjs && node tools/golden.mjs && node tools/build-prototype.mjs
```

If `simulate.mjs` reports a balance target failing, adjust effects or durations rather than the target, unless the change in difficulty was the point.
