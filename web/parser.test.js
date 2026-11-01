// Run with: node --test web/parser.test.js
const test = require("node:test");
const assert = require("node:assert");
const { createParser, splitFields } = require("./parser.js");

const ME = "Player-1-AAAAAAAA";
const BOSS = "Creature-0-1-1-1-100-0000000001";
const ADV = "0000000000000000,1,1,0,0,0,0,0,0,1,0,0,0,0,0,1,0,90";
const unit = (guid, name, flags) => `${guid},"${name}",${flags},0x80000000`;
const me = unit(ME, "Tester-Realm-EU", "0x511");
const boss = unit(BOSS, "Big Boss", "0x10a48");
const at = (s) => `11/1/2026 17:00:${String(s).padStart(2, "0")}.0000  `;

function spellHit(s, id, name, amount, overkill, crit, ev = "SPELL_DAMAGE", src = me) {
  return `${at(s)}${ev},${src},${boss},${id},"${name}",0x1,${BOSS},${ADV},${amount},${amount},${overkill},1,0,0,0,${crit ? 1 : "nil"},nil,nil,ST`;
}
function swing(s, amount, crit) {
  return `${at(s)}SWING_DAMAGE,${me},${boss},${ME},${ADV},${amount},${amount},-1,1,0,0,0,${crit ? 1 : "nil"},nil,nil`;
}
function aura(s, ev, id, name) {
  return `${at(s)}${ev},${me},${boss},${id},"${name}",0x1,DEBUFF`;
}
function run(lines) {
  const p = createParser();
  [`${at(0)}COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,12.1.5,PROJECT_ID,1`, ...lines].forEach((l) => p.line(l));
  return p.finish();
}
const start = (s) => `${at(s)}ENCOUNTER_START,1,"Big Boss",16,20,1`;
const end = (s, ok = 1) => `${at(s)}ENCOUNTER_END,1,"Big Boss",16,20,${ok},1000`;

test("splits quoted fields containing commas", () => {
  assert.deepStrictEqual(splitFields('A,"B, C",D'), ["A", "B, C", "D"]);
});

test("reads spell and swing damage, and leaves overkill out", () => {
  const r = run([start(1), spellHit(2, 10, "Stab", 100, -1, true), swing(3, 50, false), spellHit(4, 10, "Stab", 200, 80, false), end(5)]);
  const player = r.pulls[0].players[0];
  assert.strictEqual(player.damage, 270);
  const stab = player.spells.find((s) => s.name === "Stab");
  assert.strictEqual(stab.total, 220);
  assert.strictEqual(stab.hits, 2);
  assert.strictEqual(stab.crits, 1);
  assert.strictEqual(stab.max, 200);
  assert.strictEqual(player.spells.find((s) => s.name === "Melee").total, 50);
});

test("ignores damage outside a pull, keeps the grace after it, drops later hits", () => {
  const r = run([spellHit(1, 10, "Stab", 999, -1, false), start(2), end(5), spellHit(5, 10, "Stab", 100, -1, false), spellHit(9, 10, "Stab", 999, -1, false)]);
  assert.strictEqual(r.pulls[0].players[0].damage, 100);
});

test("counts pet damage for the owner and separates it by name", () => {
  const pet = "Pet-0-1-1-1-1-0000000002";
  const r = run([
    `${at(1)}SPELL_SUMMON,${me},${unit(pet, "Fluffy", "0x1114")},5,"Call Pet",0x1`,
    start(2),
    spellHit(3, 11, "Bite", 40, -1, false, "SPELL_DAMAGE", unit(pet, "Fluffy", "0x1114")),
    end(4),
  ]);
  const player = r.pulls[0].players[0];
  assert.strictEqual(player.damage, 40);
  assert.strictEqual(player.spells[0].name, "Bite (Fluffy)");
});

test("gives a party NPC its own row and credits its pet to it", () => {
  const npc = "Vehicle-0-1-1-1-200-0000000003";
  const pet = "Creature-0-1-1-1-300-0000000004";
  const r = run([
    `${at(1)}SPELL_SUMMON,${unit(npc, "Austin Huxworth", "0xa12")},${unit(pet, "Ash", "0x1212")},5,"Call Pet",0x1`,
    start(2),
    spellHit(3, 11, "Cobra Shot", 70, -1, false, "SPELL_DAMAGE", unit(npc, "Austin Huxworth", "0xa12")),
    spellHit(3, 12, "Bite", 30, -1, false, "SPELL_DAMAGE", unit(pet, "Ash", "0x1212")),
    end(4),
  ]);
  const row = r.pulls[0].players[0];
  assert.strictEqual(row.name, "Austin Huxworth");
  assert.strictEqual(row.follower, true);
  assert.strictEqual(row.damage, 100);
  assert.strictEqual(r.pulls[0].unattributed, 0);
});

test("links a pet to its owner from the swing line", () => {
  const pet = "Creature-0-1-1-1-400-0000000005";
  const line = `${at(3)}SWING_DAMAGE,${unit(pet, "Nyx", "0x2212")},${boss},${pet},${ME},1,1,0,0,0,0,0,0,1,0,0,0,0,0,1,0,90,25,25,-1,1,0,0,0,nil,nil,nil`;
  const r = run([start(2), spellHit(3, 10, "Stab", 5, -1, false), line, end(4)]);
  assert.strictEqual(r.pulls[0].players[0].damage, 30);
  assert.strictEqual(r.pulls[0].unattributed, 0);
});

test("counts hits soaked by an enemy's shield, and ignores real misses", () => {
  const soaked = `${at(3)}SPELL_MISSED,${me},${boss},10,"Stab",0x1,ABSORB,nil,300,200,1`;
  const swing = `${at(3)}SWING_MISSED,${me},${boss},ABSORB,nil,50,40,nil`;
  const miss = `${at(3)}SWING_MISSED,${me},${boss},MISS,nil`;
  const r = run([start(2), soaked, swing, miss, end(4)]);
  const player = r.pulls[0].players[0];
  assert.strictEqual(player.damage, 350);
  const stab = player.spells.find((s) => s.name === "Stab");
  assert.strictEqual(stab.hits, 1);
  assert.strictEqual(stab.crits, 1);
  assert.strictEqual(player.spells.find((s) => s.name === "Melee").hits, 1);
});

test("works out uptime, and treats an aura seen first as removed as already up", () => {
  const r = run([start(0), spellHit(1, 10, "Stab", 5, -1, false), aura(5, "SPELL_AURA_APPLIED", 20, "Rupture"), aura(10, "SPELL_AURA_REMOVED", 20, "Rupture"), aura(5, "SPELL_AURA_REMOVED", 21, "Old"), end(20)]);
  const auras = r.pulls[0].players[0].auras;
  assert.ok(Math.abs(auras.find((a) => a.name === "Rupture").uptime - 0.25) < 0.001);
  assert.ok(Math.abs(auras.find((a) => a.name === "Old").uptime - 0.25) < 0.001);
});

test("records wipes, and closes a pull the log never ended", () => {
  const wipe = run([start(1), end(5, 0)]);
  assert.strictEqual(wipe.pulls[0].success, false);
  const cut = run([start(1), spellHit(9, 10, "Stab", 5, -1, false)]);
  assert.strictEqual(cut.pulls[0].success, null);
  assert.strictEqual(cut.pulls[0].durationMs, 8000);
});

test("a log with no pulls gives an empty list", () => {
  assert.deepStrictEqual(run([spellHit(1, 10, "Stab", 5, -1, false)]).pulls, []);
});
