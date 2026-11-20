// Run after `npm ci`; Wrangler installs esbuild.
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";

const here = dirname(fileURLToPath(import.meta.url));
const built = await esbuild.build({
  entryPoints: [join(here, "entry.ts")],
  bundle: true,
  platform: "node",
  format: "esm",
  alias: { partyserver: join(here, "partyserver-stub.mjs") },
  write: false,
});
const url = "data:text/javascript;base64," + Buffer.from(built.outputFiles[0].text).toString("base64");
const { Room, RELAY } = await import(url);

function makeRoom() {
  const room = new Room();
  room.name = RELAY.rankedQueuePrefix + "BLITZ";
  return room;
}

function addPlayer(room, id) {
  const player = {
    id,
    messages: [],
    send(message) {
      this.messages.push(message);
    },
  };
  room.connections.set(id, player);
  return player;
}

function matches(player) {
  return player.messages.filter((message) => message.startsWith("Q "));
}

function check(name, condition) {
  console.log(`  ${name.padEnd(48)} ${condition ? "ok" : "FAIL"}`);
  assert.ok(condition, name);
}

function testEqualElo(room) {
  const players = Array.from({ length: 5 }, (_, i) => addPlayer(room, `equal-${i}`));
  for (const player of players) room.onMessage(player, "Q\n1200");

  check("five equal-Elo players leave one waiter", room.waiting.length === 1);
  check("the last equal-Elo player is waiting", players[4].messages.join("") === "W");
  const offers = players.slice(0, 4).map((player) => matches(player));
  check("four equal-Elo players are paired", offers.every((offer) => offer.length === 1));
  const codes = offers.map((offer) => offer[0].split(" ")[1]);
  check("equal-Elo pairs share two rooms", new Set(codes).size === 2
    && codes[0] === codes[1] && codes[2] === codes[3]);
  check("host offer carries both ratings", offers[0][0].endsWith(" H 1200 1200"));
  check("guest offer carries both ratings", offers[1][0].endsWith(" G 1200 1200"));
}

function timedRoom() {
  const room = makeRoom();
  const clock = { now: 0 };
  room.now = () => clock.now;
  return { room, clock };
}

function testInitialRange() {
  const room = makeRoom();
  const low = addPlayer(room, "initial-low");
  const high = addPlayer(room, "initial-high");
  room.onMessage(low, `Q\n100`);
  room.onMessage(high, `Q\n${100 + RELAY.ratingRange}`);
  check("ratings inside 100 pair immediately", room.waiting.length === 0
    && matches(low).length === 1 && matches(high).length === 1);

  const narrow = makeRoom();
  const first = addPlayer(narrow, "narrow-low");
  const second = addPlayer(narrow, "narrow-high");
  narrow.onMessage(first, `Q\n100`);
  narrow.onMessage(second, `Q\n${100 + RELAY.ratingRange + 1}`);
  check("ratings just outside 100 wait", narrow.waiting.length === 2
    && matches(first).length === 0 && matches(second).length === 0);
}

function testExpandedRange() {
  const { room, clock } = timedRoom();
  const low = addPlayer(room, "expanded-low");
  const high = addPlayer(room, "expanded-high");
  room.onMessage(low, "Q\n100");
  room.onMessage(high, `Q\n${100 + RELAY.ratingRangeExpanded}`);
  check("expanded range waits before one minute", room.waiting.length === 2
    && matches(low).length === 0 && matches(high).length === 0);

  clock.now = RELAY.ratingExpandMs;
  room.onMessage(low, "I\nHB");
  check("expanded range pairs after one minute", room.waiting.length === 0
    && matches(low).length === 1 && matches(high).length === 1);
}

function testExpandedLimit() {
  const { room, clock } = timedRoom();
  const low = addPlayer(room, "limit-low");
  const high = addPlayer(room, "limit-high");
  room.onMessage(low, "Q\n100");
  room.onMessage(high, `Q\n${100 + RELAY.ratingRangeExpanded + 1}`);
  clock.now = RELAY.ratingExpandMs * 10;
  room.onMessage(low, "I\nHB");
  check("outside expanded range never pairs", room.waiting.length === 2
    && matches(low).length === 0 && matches(high).length === 0);
}

function testMixedWait() {
  const { room, clock } = timedRoom();
  const low = addPlayer(room, "mixed-low");
  const high = addPlayer(room, "mixed-high");
  room.onMessage(low, "Q\n100");
  clock.now = RELAY.ratingExpandMs / 2;
  room.onMessage(high, `Q\n${100 + RELAY.ratingRangeExpanded}`);
  clock.now = RELAY.ratingExpandMs;
  room.onMessage(high, "I\nHB");
  check("short wait keeps the narrow range", room.waiting.length === 2
    && matches(low).length === 0 && matches(high).length === 0);

  clock.now = RELAY.ratingExpandMs * 1.5;
  room.onMessage(low, "I\nHB");
  check("both waiters must expand", room.waiting.length === 0
    && matches(low).length === 1 && matches(high).length === 1);
}

function testDuplicateQueue(room) {
  const first = addPlayer(room, "duplicate-a");
  const second = addPlayer(room, "duplicate-b");
  room.onMessage(first, "Q\n1200");
  room.onMessage(first, "Q\n1200");
  check("duplicate enqueue replaces the waiter", first.messages.join("") === "WW"
    && room.waiting.length === 1);
  room.onMessage(second, "Q\n1200");
  check("duplicate enqueue still matches once", room.waiting.length === 0
    && matches(first).length === 1 && matches(second).length === 1);
}

function testDisconnect(room) {
  const first = addPlayer(room, "disconnect-a");
  const second = addPlayer(room, "disconnect-b");
  room.onMessage(first, "Q\n1200");
  room.onMessage(second, "Q\n1400");
  room.onClose(first);
  check("disconnect removes only that waiter", room.waiting.length === 1
    && room.waiting[0].id === second.id);
  const third = addPlayer(room, "disconnect-c");
  room.onMessage(third, "Q\n1200");
  check("out-of-range waiter stays waiting", room.waiting.length === 2
    && third.messages.join("") === "W");
  const fourth = addPlayer(room, "disconnect-d");
  room.onMessage(fourth, "Q\n1400");
  check("compatible waiter matches after cleanup", room.waiting.length === 1
    && room.waiting[0].id === third.id && matches(fourth).length === 1);
}

function testHundredPlayers(room) {
  const players = Array.from({ length: 100 }, (_, i) => addPlayer(room, `load-${i}`));
  for (const player of players) room.onMessage(player, "Q\n1200");

  check("hundred players are fully paired", room.waiting.length === 0);
  const offers = players.map((player) => matches(player));
  check("every player receives one match", offers.every((offer) => offer.length === 1));
  const codes = offers.map((offer) => offer[0].split(" ")[1]);
  const counts = new Map();
  for (const code of codes) counts.set(code, (counts.get(code) ?? 0) + 1);
  check("hundred players form fifty rooms", counts.size === 50);
  check("every room has exactly two players", [...counts.values()].every((count) => count === 2));
}

console.log("relay queue stress tests");
testEqualElo(makeRoom());
testInitialRange();
testExpandedRange();
testExpandedLimit();
testMixedWait();
testDuplicateQueue(makeRoom());
testDisconnect(makeRoom());
testHundredPlayers(makeRoom());
console.log("\nRELAY QUEUE STRESS TESTS PASSED");
