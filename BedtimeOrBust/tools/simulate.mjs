// Balance simulator: plays thousands of seeded days with scripted "players"
// and reports outcome distributions, so tuning is driven by data instead of
// gut feel. `--check` turns the balance targets into a CI gate.
//
// Usage: node tools/simulate.mjs [--days 4000] [--check] [--json]
import { readFileSync } from "node:fs";
import { Game, METERS, formatClock } from "./engine.mjs";
import { DEFAULT_CONTENT } from "./validate.mjs";

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 ? Number(args[i + 1]) : dflt;
};
const DAYS = opt("--days", 4000);
const CHECK = args.includes("--check");
const JSON_OUT = args.includes("--json");

const content = JSON.parse(readFileSync(DEFAULT_CONTENT, "utf8"));
const cfg = content.config;
const QUALITY = ["sanity", "mood", "home", "rep"];

// Concave utility: losing the last 10 points of a meter hurts far more than
// losing 10 points from a full meter. This is how a cautious human plays.
const u = (v) => 100 * (1 - Math.exp(-Math.max(v, 0) / 25));

function evaluate(game, choice) {
  const m = game.state.meters;
  const clock = game.state.clock;
  const ev = game.currentEvent;
  const total = choice.outcomes.reduce((a, o) => a + (o.weight ?? 1), 0);
  let exp = 0;
  for (const o of choice.outcomes) {
    const p = (o.weight ?? 1) / total;
    const after = {};
    for (const k of METERS) after[k] = Math.min(100, Math.max(0, m[k] + (o.effects?.[k] ?? 0)));
    const mins = choice.duration + (cfg.eventGap ?? 0);
    for (const [k, every] of Object.entries(cfg.drainEvery ?? {})) after[k] -= mins / every;
    let util = 0;
    for (const k of QUALITY) util += u(after[k]);
    for (const k of ["sanity", "home", "rep"]) if (after[k] <= 0) util -= 1000;
    const projected = after.sleepy + (cfg.bedtimeClock - clock - choice.duration) / cfg.sleepyEvery;
    if (ev.final) util += after.sleepy >= cfg.asleepThreshold ? 300 : -300;
    else if (clock >= 840) util -= Math.abs(projected - 68) * 0.8;
    else if (ev.id === "nap") util -= Math.abs(projected - 68) * 0.8;
    exp += p * util;
  }
  return exp;
}

const POLICIES = {
  random: (game, choices, rand) => Math.floor(rand() * choices.length),
  first: () => 0,
  greedy: (game, choices) => {
    let best = 0;
    let bestV = -Infinity;
    choices.forEach((c, i) => {
      const v = evaluate(game, c);
      if (v > bestV) [best, bestV] = [i, v];
    });
    return best;
  },
  worst: (game, choices) => {
    let best = 0;
    let bestV = Infinity;
    choices.forEach((c, i) => {
      const v = evaluate(game, c);
      if (v < bestV) [best, bestV] = [i, v];
    });
    return best;
  },
};

function lcg(seed) {
  let s = seed >>> 0;
  return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
}

function run(policyName) {
  const policy = POLICIES[policyName];
  const endings = {};
  const eventSeen = {};
  const picks = {};
  const lossClock = [];
  let steps = 0;
  let fillers = 0;
  let wins = 0;
  const finalMeters = Object.fromEntries(METERS.map((k) => [k, 0]));
  const byModifier = {};
  for (let d = 0; d < DAYS; d++) {
    const seed = (d * 2654435761) >>> 0;
    const g = new Game(content, seed);
    const rand = lcg(seed ^ 0x9e3779b9);
    let guard = 0;
    while (!g.isOver) {
      if (++guard > 200) throw new Error(`runaway day: seed ${seed}`);
      const ev = g.currentEvent;
      eventSeen[ev.id] = (eventSeen[ev.id] ?? 0) + 1;
      if (ev.filler) fillers++;
      const choices = g.visibleChoices();
      const i = policy(g, choices, rand);
      const key = `${ev.id}#${ev.choices.indexOf(choices[i])}`;
      picks[key] = (picks[key] ?? 0) + 1;
      g.choose(i);
      steps++;
    }
    const e = g.state.endingId;
    endings[e] = (endings[e] ?? 0) + 1;
    const kind = content.endings[e].kind;
    if (kind === "win") wins++;
    if (kind === "loss") lossClock.push(g.state.clock);
    for (const k of METERS) finalMeters[k] += g.state.meters[k];
    const bm = (byModifier[g.state.modifierId] ??= { days: 0, wins: 0 });
    bm.days++;
    if (kind === "win") bm.wins++;
  }
  for (const k of METERS) finalMeters[k] = +(finalMeters[k] / DAYS).toFixed(1);
  lossClock.sort((a, b) => a - b);
  return {
    policy: policyName,
    winRate: wins / DAYS,
    endings: Object.fromEntries(Object.entries(endings).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, +(v / DAYS).toFixed(3)])),
    meanSteps: +(steps / DAYS).toFixed(1),
    fillerShare: +(fillers / steps).toFixed(4),
    medianLossTime: lossClock.length ? formatClock(lossClock[Math.floor(lossClock.length / 2)]) : null,
    finalMeters,
    byModifier: Object.fromEntries(Object.entries(byModifier).map(([k, v]) => [k, +(v.wins / v.days).toFixed(3)])),
    eventSeen,
    picks,
  };
}

// Static check: is any choice strictly dominated (no better on any meter,
// worse on at least one, and not faster)? Dominated choices are dead weight.
function dominated() {
  const out = [];
  const expected = (c) => {
    const total = c.outcomes.reduce((a, o) => a + (o.weight ?? 1), 0);
    const e = Object.fromEntries(METERS.map((k) => [k, 0]));
    for (const o of c.outcomes) for (const k of METERS) e[k] += ((o.weight ?? 1) / total) * (o.effects?.[k] ?? 0);
    return e;
  };
  for (const ev of content.events) {
    const ex = ev.choices.map(expected);
    ev.choices.forEach((c, i) => {
      ev.choices.forEach((d, j) => {
        if (i === j || c.when || d.when) return;
        const better = QUALITY.every((k) => ex[j][k] >= ex[i][k]) && ex[j].sleepy === ex[i].sleepy && d.duration <= c.duration;
        const strictly = QUALITY.some((k) => ex[j][k] > ex[i][k]) || d.duration < c.duration;
        if (better && strictly) out.push(`${ev.id}: "${c.label}" is dominated by "${d.label}"`);
      });
    });
  }
  return out;
}

const results = Object.keys(POLICIES).map(run);
const dom = dominated();

// Choices the greedy player picks >= 97% of the time are not real dilemmas.
const greedy = results.find((r) => r.policy === "greedy");
const noDilemma = [];
for (const ev of content.events) {
  if (ev.choices.length < 2) continue;
  const counts = ev.choices.map((_, i) => greedy.picks[`${ev.id}#${i}`] ?? 0);
  const total = counts.reduce((a, b) => a + b, 0);
  if (total >= 50 && Math.max(...counts) / total >= 0.97) {
    noDilemma.push(`${ev.id}: greedy picks "${ev.choices[counts.indexOf(Math.max(...counts))].label}" ${((100 * Math.max(...counts)) / total).toFixed(0)}%`);
  }
}

const TARGETS = {
  "random win rate in [0.30, 0.65]": (r) => r.random.winRate >= 0.3 && r.random.winRate <= 0.65,
  "greedy win rate >= 0.75": (r) => r.greedy.winRate >= 0.75,
  "worst win rate <= 0.15": (r) => r.worst.winRate <= 0.15,
  "always-first win rate <= greedy - 0.15": (r) => r.first.winRate <= r.greedy.winRate - 0.15,
  "filler share < 3% (random)": (r) => r.random.fillerShare < 0.03,
  "mean events per day in [15, 40] (random)": (r) => r.random.meanSteps >= 15 && r.random.meanSteps <= 40,
  "no strictly dominated choices": () => dom.length === 0,
};
const byName = Object.fromEntries(results.map((r) => [r.policy, r]));
const checks = Object.entries(TARGETS).map(([name, f]) => ({ name, pass: f(byName) }));

if (JSON_OUT) {
  console.log(JSON.stringify({ days: DAYS, results, dominated: dom, noDilemma, checks }, null, 2));
} else {
  console.log(`Simulated ${DAYS} days per policy\n`);
  for (const r of results) {
    console.log(`${r.policy.padEnd(7)} win ${(100 * r.winRate).toFixed(1)}%  steps ${r.meanSteps}  filler ${(100 * r.fillerShare).toFixed(2)}%  median loss ${r.medianLossTime ?? "-"}`);
    console.log(`        endings ${JSON.stringify(r.endings)}`);
    console.log(`        final   ${JSON.stringify(r.finalMeters)}`);
    console.log(`        win by modifier ${JSON.stringify(r.byModifier)}`);
  }
  const never = content.events.filter((e) => !(byName.random.eventSeen[e.id] > 0)).map((e) => e.id);
  console.log(`\nEvents never seen (random policy): ${never.length ? never.join(", ") : "none"}`);
  console.log(`Dominated choices: ${dom.length ? "\n  " + dom.join("\n  ") : "none"}`);
  console.log(`Low-dilemma events (greedy >=97% one choice): ${noDilemma.length ? "\n  " + noDilemma.join("\n  ") : "none"}`);
  console.log("\nBalance targets:");
  for (const c of checks) console.log(`  ${c.pass ? "PASS" : "FAIL"}  ${c.name}`);
}
if (CHECK && checks.some((c) => !c.pass)) process.exit(1);
