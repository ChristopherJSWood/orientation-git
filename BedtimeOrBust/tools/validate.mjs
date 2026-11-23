// Content linter: catches authoring mistakes in content.json before they ship.
// Usage: node tools/validate.mjs [path/to/content.json]
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { METERS } from "./engine.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_CONTENT = resolve(here, "../Core/Sources/BedtimeCore/Resources/content.json");

const LIMITS = { title: 40, text: 280, label: 70, outcome: 280 };

export function validate(content) {
  const errors = [];
  const warnings = [];
  const err = (m) => errors.push(m);
  const warn = (m) => warnings.push(m);
  const isPosInt = (n) => Number.isInteger(n) && n > 0;

  const meterMap = (where, obj) => {
    for (const [k, v] of Object.entries(obj ?? {})) {
      if (!METERS.includes(k)) err(`${where}: unknown meter "${k}"`);
      if (!Number.isInteger(v)) err(`${where}: value for "${k}" must be an integer`);
    }
  };
  const counterMap = (where, obj) => {
    for (const [k, v] of Object.entries(obj ?? {})) {
      if (!(content.counters ?? []).some((c) => c.id === k)) err(`${where}: counter "${k}" is not declared in "counters"`);
      if (!Number.isInteger(v)) err(`${where}: counter "${k}" must be an integer`);
    }
  };
  const flagsSet = new Set();
  const flagsRead = [];
  const cond = (where, c) => {
    if (!c) return;
    const known = new Set(["flags", "notFlags", "min", "max"]);
    for (const k of Object.keys(c)) if (!known.has(k)) err(`${where}: unknown condition key "${k}"`);
    meterMap(`${where}.min`, c.min);
    meterMap(`${where}.max`, c.max);
    for (const f of [...(c.flags ?? []), ...(c.notFlags ?? [])]) flagsRead.push([where, f]);
  };
  const len = (where, kind, s) => {
    if (typeof s !== "string" || s.length === 0) err(`${where}: missing ${kind}`);
    else if (s.length > LIMITS[kind]) warn(`${where}: ${kind} is ${s.length} chars (limit ${LIMITS[kind]})`);
  };

  const cfg = content.config ?? {};
  for (const k of ["startClock", "bedtimeClock", "eventGap", "sleepyEvery", "overtiredAt", "overtiredMoodEvery", "asleepThreshold"]) {
    if (!Number.isInteger(cfg[k])) err(`config.${k} must be an integer`);
  }
  for (const m of METERS) if (!Number.isInteger(cfg.startMeters?.[m])) err(`config.startMeters.${m} missing`);
  meterMap("config.drainEvery", cfg.drainEvery);
  for (const [k, v] of Object.entries(cfg.drainEvery ?? {})) if (!(v > 0)) err(`config.drainEvery.${k} must be positive`);
  if (cfg.drainEvery?.sleepy) err("config.drainEvery.sleepy: sleepiness rises via sleepyEvery, it cannot also drain");
  const grades = cfg.grades ?? [];
  for (let i = 1; i < grades.length; i++) if (grades[i].min >= grades[i - 1].min) err("config.grades must be sorted by descending min");
  if (grades.length && grades[grades.length - 1].min !== 0) err("config.grades: last grade must have min 0");

  const endingIds = new Set(Object.keys(content.endings ?? {}));
  for (const id of ["meltdown", "ballpit", "groupchat", "second_wind", ...grades.map((g) => g.id)]) {
    if (!endingIds.has(id)) err(`endings: missing "${id}"`);
  }
  for (const m of METERS) if (!content.meters?.[m]) err(`meters: missing display name for "${m}"`);
  if (!Array.isArray(content.counters)) err("counters must be an array of { id, label }");
  const counterIds = new Set();
  for (const c of content.counters ?? []) {
    if (!c.id || !c.label) err(`counters: entry needs id and label`);
    if (counterIds.has(c.id)) err(`counters: duplicate id "${c.id}"`);
    counterIds.add(c.id);
  }

  const modIds = new Set();
  for (const m of content.modifiers ?? []) {
    if (modIds.has(m.id)) err(`modifier "${m.id}": duplicate id`);
    modIds.add(m.id);
    if (m.weight !== undefined && !isPosInt(m.weight)) err(`modifier "${m.id}": weight must be a positive integer`);
    meterMap(`modifier "${m.id}".effects`, m.effects);
    for (const f of m.set ?? []) flagsSet.add(f);
  }
  if (modIds.size === 0) err("modifiers: need at least one");

  const ids = new Set();
  let fillers = 0;
  let finals = 0;
  for (const e of content.events ?? []) {
    const w = `event "${e.id}"`;
    if (ids.has(e.id)) err(`${w}: duplicate id`);
    ids.add(e.id);
    len(w, "title", e.title);
    len(w, "text", e.text);
    if (!Array.isArray(e.window) || e.window.length !== 2 || !(e.window[0] <= e.window[1])) err(`${w}: window must be [from, to]`);
    if (e.weight !== undefined && !isPosInt(e.weight)) err(`${w}: weight must be a positive integer`);
    if (e.priority !== undefined && !Number.isInteger(e.priority)) err(`${w}: priority must be an integer`);
    if (e.filler) fillers++;
    if (e.final) finals++;
    cond(`${w}.when`, e.when);
    if (!Array.isArray(e.choices) || e.choices.length < 1 || e.choices.length > 3) err(`${w}: needs 1-3 choices`);
    const unconditional = (e.choices ?? []).filter((c) => !c.when).length;
    if (unconditional === 0) err(`${w}: at least one choice must have no "when" (so the event is never empty)`);
    (e.choices ?? []).forEach((c, ci) => {
      const cw = `${w} choice ${ci}`;
      len(cw, "label", c.label);
      if (!isPosInt(c.duration)) err(`${cw}: duration must be a positive integer (minutes)`);
      cond(`${cw}.when`, c.when);
      if (!Array.isArray(c.outcomes) || c.outcomes.length < 1) err(`${cw}: needs at least one outcome`);
      (c.outcomes ?? []).forEach((o, oi) => {
        const ow = `${cw} outcome ${oi}`;
        len(ow, "outcome", o.text);
        if (o.weight !== undefined && !isPosInt(o.weight)) err(`${ow}: weight must be a positive integer`);
        meterMap(`${ow}.effects`, o.effects);
        counterMap(`${ow}.count`, o.count);
        for (const f of o.set ?? []) flagsSet.add(f);
      });
    });
  }
  if (fillers !== 1) err(`exactly one filler event required (found ${fillers})`);
  if (finals < 1) err("at least one final event required");
  for (const [where, f] of flagsRead) if (!flagsSet.has(f)) warn(`${where}: flag "${f}" is read but never set`);

  return { errors, warnings, stats: { events: ids.size, modifiers: modIds.size } };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const path = process.argv[2] ?? DEFAULT_CONTENT;
  const content = JSON.parse(readFileSync(path, "utf8"));
  const { errors, warnings, stats } = validate(content);
  for (const w of warnings) console.log(`warning: ${w}`);
  for (const e of errors) console.log(`ERROR: ${e}`);
  console.log(`${stats.events} events, ${stats.modifiers} modifiers, ${errors.length} errors, ${warnings.length} warnings`);
  process.exit(errors.length ? 1 : 0);
}
