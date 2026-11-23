// Bedtime or Bust — reference rules engine (JavaScript).
//
// This file is the executable specification of the game rules. The Swift
// engine in Core/Sources/BedtimeCore/Engine.swift must behave identically;
// tools/golden.mjs records traces from this engine and the Swift test suite
// replays them (Core/Tests/BedtimeCoreTests/ConformanceTests.swift).
//
// Determinism contract (both engines):
//   * RNG is mulberry32 over a 32-bit unsigned state.
//   * Exactly one RNG draw per weighted pick: day modifier at start, the next
//     random (non-priority) event, and an outcome when a choice has >1 outcome.
//   * Integer meters, clamped to [0, 100] after every change.

export const METERS = ["sanity", "mood", "home", "rep", "sleepy"];

export function mulberry32(seed) {
  let a = seed | 0;
  return function next() {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function weightedPick(items, weightOf, rng) {
  let total = 0;
  for (const it of items) total += weightOf(it);
  const r = rng() * total;
  let acc = 0;
  for (let i = 0; i < items.length; i++) {
    acc += weightOf(items[i]);
    if (r < acc) return i;
  }
  return items.length - 1;
}

const clamp = (v) => (v < 0 ? 0 : v > 100 ? 100 : v);

export function meets(cond, s) {
  if (!cond) return true;
  for (const f of cond.flags ?? []) if (!s.flags.has(f)) return false;
  for (const f of cond.notFlags ?? []) if (s.flags.has(f)) return false;
  for (const [k, v] of Object.entries(cond.min ?? {})) if (s.meters[k] < v) return false;
  for (const [k, v] of Object.entries(cond.max ?? {})) if (s.meters[k] > v) return false;
  return true;
}

export function formatClock(minutes) {
  const m = ((minutes % 1440) + 1440) % 1440;
  const h24 = Math.floor(m / 60);
  const mm = m % 60;
  const suffix = h24 < 12 ? "AM" : "PM";
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}:${String(mm).padStart(2, "0")} ${suffix}`;
}

export class Game {
  constructor(content, seed) {
    this.content = content;
    this.cfg = content.config;
    this.rng = mulberry32(seed >>> 0);
    this.state = {
      seed: seed >>> 0,
      clock: this.cfg.startClock,
      meters: { ...this.cfg.startMeters },
      flags: new Set(),
      counters: {},
      seen: new Set(),
      lastEventId: null,
      currentEventId: null,
      modifierId: null,
      step: 0,
      endingId: null,
    };
    const mods = content.modifiers;
    const mod = mods[weightedPick(mods, (m) => m.weight ?? 1, this.rng)];
    this.state.modifierId = mod.id;
    this.#apply(mod.effects, mod.set, null, null);
    this.state.currentEventId = this.#nextEvent().id;
  }

  get modifier() {
    return this.content.modifiers.find((m) => m.id === this.state.modifierId);
  }
  get currentEvent() {
    const id = this.state.currentEventId;
    return id == null ? null : this.content.events.find((e) => e.id === id);
  }
  get ending() {
    const id = this.state.endingId;
    return id == null ? null : { id, ...this.content.endings[id] };
  }
  get isOver() {
    return this.state.endingId != null;
  }

  visibleChoices(event = this.currentEvent) {
    if (!event) return [];
    return event.choices.filter((c) => meets(c.when, this.state));
  }

  choose(visibleIndex) {
    if (this.isOver) throw new Error("game is over");
    const ev = this.currentEvent;
    const choices = this.visibleChoices(ev);
    if (!(visibleIndex >= 0 && visibleIndex < choices.length)) throw new Error(`bad choice ${visibleIndex}`);
    const choice = choices[visibleIndex];
    const before = { ...this.state.meters };

    let outcomeIndex = 0;
    if (choice.outcomes.length > 1) {
      outcomeIndex = weightedPick(choice.outcomes, (o) => o.weight ?? 1, this.rng);
    }
    const out = choice.outcomes[outcomeIndex];
    this.#apply(out.effects, out.set, out.clear, out.count);
    const minutes = choice.duration + (this.cfg.eventGap ?? 0);
    this.#advance(minutes);

    const s = this.state;
    s.seen.add(ev.id);
    s.lastEventId = ev.id;
    s.step += 1;

    let endingId = null;
    if (s.meters.sanity <= 0) endingId = "meltdown";
    else if (s.meters.home <= 0) endingId = "ballpit";
    else if (s.meters.rep <= 0) endingId = "groupchat";
    else if (ev.final) endingId = this.#bedtimeEnding();

    if (endingId) {
      s.endingId = endingId;
      s.currentEventId = null;
    } else {
      s.currentEventId = this.#nextEvent().id;
    }

    const deltas = {};
    for (const m of METERS) if (s.meters[m] !== before[m]) deltas[m] = s.meters[m] - before[m];
    return { eventId: ev.id, choiceIndex: visibleIndex, outcomeIndex, text: out.text, deltas, minutes, endingId };
  }

  // Rank of the asleep ending from the four "quality" meters (sleepy excluded).
  score() {
    const m = this.state.meters;
    return m.sanity + m.mood + m.home + m.rep;
  }

  #bedtimeEnding() {
    if (this.state.meters.sleepy < this.cfg.asleepThreshold) return "second_wind";
    const total = this.score();
    for (const g of this.cfg.grades) if (total >= g.min) return g.id;
    return this.cfg.grades[this.cfg.grades.length - 1].id;
  }

  #apply(effects, set, clear, count) {
    const s = this.state;
    for (const [k, v] of Object.entries(effects ?? {})) s.meters[k] = clamp(s.meters[k] + v);
    for (const f of set ?? []) s.flags.add(f);
    for (const f of clear ?? []) s.flags.delete(f);
    for (const [k, v] of Object.entries(count ?? {})) s.counters[k] = (s.counters[k] ?? 0) + v;
  }

  // Passive drift while time passes. Ticks are counted on minutes since the
  // start of the day so that drift does not depend on how time is chunked.
  #advance(minutes) {
    const s = this.state;
    const cfg = this.cfg;
    const t0 = s.clock - cfg.startClock;
    const t1 = t0 + minutes;
    const ticks = (every) => Math.floor(t1 / every) - Math.floor(t0 / every);
    s.meters.sleepy = clamp(s.meters.sleepy + ticks(cfg.sleepyEvery));
    for (const m of METERS) {
      const every = cfg.drainEvery?.[m];
      if (every) s.meters[m] = clamp(s.meters[m] - ticks(every));
    }
    if (s.meters.sleepy >= cfg.overtiredAt) {
      s.meters.mood = clamp(s.meters.mood - ticks(cfg.overtiredMoodEvery));
    }
    s.clock += minutes;
  }

  #nextEvent() {
    const s = this.state;
    const cands = this.content.events.filter(
      (e) =>
        !e.filler &&
        (e.repeatable || !s.seen.has(e.id)) &&
        e.id !== s.lastEventId &&
        s.clock >= e.window[0] &&
        s.clock <= e.window[1] &&
        meets(e.when, s) &&
        this.visibleChoices(e).length > 0,
    );
    let best = null;
    for (const e of cands) if ((e.priority ?? 0) > 0 && (best == null || e.priority > best.priority)) best = e;
    if (best) return best;
    const pool = cands.filter((e) => !((e.priority ?? 0) > 0));
    if (pool.length === 0) return this.content.events.find((e) => e.filler);
    return pool[weightedPick(pool, (e) => e.weight ?? 1, this.rng)];
  }
}

// Serializable snapshot (used by golden traces and tests).
export function snapshot(game) {
  const s = game.state;
  return {
    clock: s.clock,
    meters: { ...s.meters },
    flags: [...s.flags].sort(),
    counters: Object.fromEntries(Object.entries(s.counters).sort(([a], [b]) => (a < b ? -1 : 1))),
    modifierId: s.modifierId,
    step: s.step,
    endingId: s.endingId,
  };
}
