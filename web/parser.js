// CZ Meter log parser. Reads WoWCombatLog.txt one line at a time and returns
// per-pull stats. Runs in a Web Worker, on the page, or in Node for tests.
// Nothing here touches the network.

(function (root) {
  "use strict";

  // Hits that land just after ENCOUNTER_END still count towards the pull.
  var END_GRACE_MS = 1000;
  var SUPPORTED_LOG_VERSION = 22;
  var HOSTILE = 0x40;
  var HOSTILE_OR_NEUTRAL = 0x60;
  var IN_GROUP = 0x7;
  var IS_NPC = 0x800;
  var NO_OWNER = "0000000000000000";
  var SWING_ID = 6603;

  // Fields are counted from the end of the line: the block before them changes size.
  var DAMAGE_EVENTS = {
    SPELL_DAMAGE: { amount: 11, overkill: 9, absorbed: 5, crit: 4, swing: false, periodic: false },
    SPELL_PERIODIC_DAMAGE: { amount: 11, overkill: 9, absorbed: 5, crit: 4, swing: false, periodic: true },
    RANGE_DAMAGE: { amount: 11, overkill: 9, absorbed: 5, crit: 4, swing: false, periodic: false },
    SWING_DAMAGE: { amount: 10, overkill: 8, absorbed: 4, crit: 3, swing: true, periodic: false },
  };

  var MISSED_EVENTS = {
    SPELL_MISSED: { type: 12, swing: false, periodic: false },
    SPELL_PERIODIC_MISSED: { type: 12, swing: false, periodic: true },
    RANGE_MISSED: { type: 12, swing: false, periodic: false },
    SWING_MISSED: { type: 9, swing: true, periodic: false },
  };

  var AURA_EVENTS = {
    SPELL_AURA_APPLIED: 1,
    SPELL_AURA_REMOVED: -1,
    SPELL_AURA_REFRESH: 0,
    SPELL_AURA_APPLIED_DOSE: 0,
    SPELL_AURA_REMOVED_DOSE: 0,
  };

  function splitFields(text) {
    var out = [];
    var i = 0;
    var n = text.length;
    while (i <= n) {
      if (text.charCodeAt(i) === 34) {
        var close = text.indexOf('"', i + 1);
        if (close < 0) close = n;
        out.push(text.slice(i + 1, close));
        i = close + 2;
      } else {
        var comma = text.indexOf(",", i);
        if (comma < 0) comma = n;
        out.push(text.slice(i, comma));
        i = comma + 1;
      }
    }
    return out;
  }

  function parseTime(stamp) {
    // 11/1/2026 17:18:15.0792
    var space = stamp.indexOf(" ");
    var date = stamp.slice(0, space).split("/");
    var time = stamp.slice(space + 1).split(":");
    var seconds = parseFloat(time[2]);
    var whole = Math.floor(seconds);
    return Date.UTC(+date[2], +date[0] - 1, +date[1], +time[0], +time[1], whole) + (seconds - whole) * 1000;
  }

  function shortName(fullName) {
    var dash = fullName.indexOf("-");
    return dash > 0 ? fullName.slice(0, dash) : fullName;
  }

  function createParser() {
    var owners = Object.create(null);
    var playerNames = Object.create(null);
    var followers = Object.create(null);
    var pulls = [];
    var pull = null;
    var lastTime = 0;
    var logVersion = null;
    var advanced = null;
    var zone = null;
    var lineCount = 0;

    function rootOwner(guid) {
      for (var i = 0; i < 5 && owners[guid]; i++) guid = owners[guid];
      return guid;
    }

    // Players get a row, and so do party NPCs such as dungeon followers.
    function isRow(guid) {
      return guid.indexOf("Player-") === 0 || followers[guid] === true;
    }

    function getPlayer(guid) {
      var p = pull.players[guid];
      if (!p) {
        p = { guid: guid, damage: 0, deaths: 0, spells: Object.create(null), auras: Object.create(null) };
        pull.players[guid] = p;
      }
      return p;
    }

    function getSpell(player, name) {
      var s = player.spells[name];
      if (!s) {
        s = { name: name, ids: {}, total: 0, hits: 0, crits: 0, ticks: 0, tickCrits: 0, min: null, max: null, overkill: 0, casts: 0 };
        player.spells[name] = s;
      }
      return s;
    }

    function startPull(t, f) {
      closePull(t);
      pull = {
        encounterId: +f[1], name: f[2], difficultyId: +f[3], groupSize: +f[4], zone: zone,
        startTime: t, endTime: null, success: null,
        players: Object.create(null), enemies: Object.create(null), unattributed: 0,
      };
      pulls.push(pull);
    }

    function closeAuras(p, t) {
      if (!p) return;
      Object.keys(p.players).forEach(function (guid) {
        var auras = p.players[guid].auras;
        Object.keys(auras).forEach(function (key) {
          var a = auras[key];
          if (a.since !== null) {
            a.up += Math.max(0, t - a.since);
            a.since = null;
          }
          a.count = 0;
        });
      });
    }

    function closePull(t) {
      if (!pull) return;
      if (pull.endTime === null) pull.endTime = t;
      closeAuras(pull, pull.endTime);
      pull = null;
    }

    function onDamage(t, ev, spec, f) {
      var n = f.length;
      var hit = +f[n - spec.amount];
      var overkill = Math.max(0, +f[n - spec.overkill]);
      // Matches Blizzard's meter: overkill is left out, damage soaked by an enemy's shield counts.
      var amount = hit - overkill + (+f[n - spec.absorbed] || 0);
      addDamage(f, spec, hit, overkill, amount, f[n - spec.crit] === "1");
    }

    // A hit an enemy's shield soaks completely is logged as a miss, with the amount after the type.
    function onMissed(t, spec, f) {
      if (f[spec.type] !== "ABSORB") return;
      var amount = +f[spec.type + 2];
      addDamage(f, spec, amount, 0, amount, f[spec.type + 4] === "1");
    }

    function addDamage(f, spec, hit, overkill, amount, crit) {
      if (!(parseInt(f[7], 16) & HOSTILE_OR_NEUTRAL)) return;
      if (parseInt(f[3], 16) & HOSTILE) return;
      var source = rootOwner(f[1]);
      var enemy = pull.enemies[f[6]] || (pull.enemies[f[6]] = { name: f[6], total: 0 });
      enemy.total += amount;
      if (!isRow(source)) {
        pull.unattributed += amount;
        return;
      }
      var player = getPlayer(source);
      var id = spec.swing ? SWING_ID : +f[9];
      var name = spec.swing ? "Melee" : f[10];
      if (source !== f[1]) name += " (" + f[2] + ")";
      var s = getSpell(player, name);
      s.ids[id] = true;
      s.total += amount;
      s.overkill += overkill;
      if (spec.periodic) {
        s.ticks++;
        if (crit) s.tickCrits++;
      } else {
        s.hits++;
        if (crit) s.crits++;
      }
      if (s.min === null || hit < s.min) s.min = hit;
      if (s.max === null || hit > s.max) s.max = hit;
      player.damage += amount;
    }

    function onCast(t, f) {
      if (pull.endTime !== null) return;
      var source = rootOwner(f[1]);
      if (!isRow(source)) return;
      var name = f[10];
      if (source !== f[1]) name += " (" + f[2] + ")";
      var s = getSpell(getPlayer(source), name);
      s.ids[+f[9]] = true;
      s.casts++;
    }

    function onAura(t, change, f) {
      if (pull.endTime !== null) return;
      var source = rootOwner(f[1]);
      if (!isRow(source)) return;
      var kind = f[12];
      var key = f[10] + "|" + kind;
      var player = getPlayer(source);
      var a = player.auras[key];
      if (!a) {
        a = { name: f[10], id: +f[9], kind: kind, up: 0, applies: 0, count: 0, since: null };
        // Seen first without being applied, so it was already up when the pull began.
        if (change !== 1) {
          a.count = 1;
          a.since = pull.startTime;
        }
        player.auras[key] = a;
      }
      if (change === 1) {
        a.applies++;
        if (a.count === 0) a.since = t;
        a.count++;
      } else if (change === -1 && a.count > 0) {
        a.count--;
        if (a.count === 0) {
          a.up += Math.max(0, t - a.since);
          a.since = null;
        }
      } else if (change === 0 && a.count === 0) {
        a.count = 1;
        a.since = t;
      }
    }

    function line(text) {
      lineCount++;
      var gap = text.indexOf("  ");
      if (gap < 0) return;
      var comma = text.indexOf(",", gap + 2);
      if (comma < 0) return;
      var ev = text.slice(gap + 2, comma);
      var damage = DAMAGE_EVENTS[ev];
      var missed = MISSED_EVENTS[ev];
      var auraChange = AURA_EVENTS[ev];
      var isAura = auraChange !== undefined;

      if (pull === null && !isAnyPullEvent(ev)) return;
      if (damage === undefined && !isAura && !isTracked(ev)) return;

      var f = splitFields(text.slice(gap + 2));
      var t = parseTime(text.slice(0, gap));
      lastTime = t;

      if (ev === "COMBAT_LOG_VERSION") {
        logVersion = +f[1];
        advanced = f[3] === "1";
      } else if (ev === "ZONE_CHANGE") {
        zone = f[2];
      } else if (ev === "ENCOUNTER_START") {
        startPull(t, f);
      } else if (ev === "ENCOUNTER_END") {
        if (pull && pull.encounterId === +f[1]) {
          pull.endTime = t;
          pull.success = f[5] === "1";
          closeAuras(pull, t);
        }
      } else if (ev === "SPELL_SUMMON") {
        owners[f[5]] = f[1];
      } else {
        if (f[1].indexOf("Player-") === 0) {
          playerNames[f[1]] = f[2];
        } else if (!followers[f[1]] && f[3] && (parseInt(f[3], 16) & IS_NPC) && (parseInt(f[3], 16) & IN_GROUP)) {
          followers[f[1]] = true;
          playerNames[f[1]] = f[2];
        }
        if (damage !== undefined || ev === "SPELL_CAST_SUCCESS") {
          // The advanced block names a unit and its owner when it has one.
          // It starts earlier on swings, which have no spell fields, and there it's the attacker.
          var unitAt = damage !== undefined && damage.swing ? 9 : 12;
          var ownerGuid = f[unitAt + 1];
          if (ownerGuid && ownerGuid !== NO_OWNER && ownerGuid.indexOf("-") > 0) owners[f[unitAt]] = ownerGuid;
        }
        if (!pull) return;
        if (pull.endTime !== null && t > pull.endTime + END_GRACE_MS) {
          closePull(t);
          return;
        }
        if (damage !== undefined) {
          onDamage(t, ev, damage, f);
        } else if (missed !== undefined) {
          onMissed(t, missed, f);
        } else if (isAura) {
          onAura(t, auraChange, f);
        } else if (ev === "SPELL_CAST_SUCCESS") {
          onCast(t, f);
        } else if (ev === "UNIT_DIED" && f[5].indexOf("Player-") === 0 && pull.endTime === null) {
          getPlayer(f[5]).deaths++;
        }
      }
    }

    // Outside a pull only these matter, so the rest of a huge log is skipped cheaply.
    function isAnyPullEvent(ev) {
      return ev === "COMBAT_LOG_VERSION" || ev === "ZONE_CHANGE" || ev === "ENCOUNTER_START" ||
        ev === "SPELL_SUMMON" || ev === "SPELL_CAST_SUCCESS" || DAMAGE_EVENTS[ev] !== undefined;
    }

    function isTracked(ev) {
      return isAnyPullEvent(ev) || ev === "ENCOUNTER_END" || ev === "UNIT_DIED" || MISSED_EVENTS[ev] !== undefined;
    }

    function finish() {
      closePull(lastTime);
      return {
        logVersion: logVersion,
        advanced: advanced,
        supported: logVersion === SUPPORTED_LOG_VERSION,
        lines: lineCount,
        pulls: pulls.map(buildPull),
      };
    }

    function buildPull(p) {
      var duration = Math.max(1, p.endTime - p.startTime);
      var players = Object.keys(p.players).map(function (guid) {
        var r = p.players[guid];
        var spells = Object.keys(r.spells).map(function (k) {
          var s = r.spells[k];
          return {
            name: s.name, ids: Object.keys(s.ids).map(Number), total: s.total, hits: s.hits, crits: s.crits,
            ticks: s.ticks, tickCrits: s.tickCrits, min: s.min, max: s.max, overkill: s.overkill, casts: s.casts,
          };
        }).sort(function (a, b) { return b.total - a.total; });
        var auras = Object.keys(r.auras).map(function (k) {
          var a = r.auras[k];
          return { name: a.name, id: a.id, kind: a.kind, applies: a.applies, uptime: Math.min(1, a.up / duration) };
        }).sort(function (a, b) { return b.uptime - a.uptime; });
        return {
          guid: guid, name: shortName(playerNames[guid] || guid), fullName: playerNames[guid] || guid,
          follower: followers[guid] === true,
          damage: r.damage, dps: r.damage / (duration / 1000), deaths: r.deaths, spells: spells, auras: auras,
        };
      }).filter(function (r) {
        // A follower that dealt no damage is usually a totem or helper, not a member of the group.
        return r.damage > 0 || (!r.follower && (r.deaths > 0 || r.spells.length > 0));
      })
        .sort(function (a, b) { return b.damage - a.damage; });
      return {
        name: p.name, encounterId: p.encounterId, difficultyId: p.difficultyId, groupSize: p.groupSize, zone: p.zone,
        startTime: p.startTime, durationMs: duration, success: p.success, unattributed: p.unattributed,
        players: players,
        enemies: Object.keys(p.enemies).map(function (k) { return p.enemies[k]; })
          .sort(function (a, b) { return b.total - a.total; }),
      };
    }

    return { line: line, finish: finish };
  }

  // Streams a browser File through the parser without loading it into memory.
  async function parseFile(file, onProgress) {
    var parser = createParser();
    var reader = file.stream().getReader();
    var decoder = new TextDecoder("utf-8");
    var leftover = "";
    var read = 0;
    for (;;) {
      var step = await reader.read();
      if (step.done) break;
      read += step.value.length;
      var text = leftover + decoder.decode(step.value, { stream: true });
      var start = 0;
      var nl;
      while ((nl = text.indexOf("\n", start)) >= 0) {
        var end = nl > start && text.charCodeAt(nl - 1) === 13 ? nl - 1 : nl;
        parser.line(text.slice(start, end));
        start = nl + 1;
      }
      leftover = text.slice(start);
      if (onProgress) onProgress(read / file.size);
    }
    if (leftover) parser.line(leftover);
    return parser.finish();
  }

  var api = { createParser: createParser, parseFile: parseFile, splitFields: splitFields, END_GRACE_MS: END_GRACE_MS };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.CZLogParser = api;
})(typeof self !== "undefined" ? self : this);
