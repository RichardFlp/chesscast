# ChessCast

Chess with spells, built with [LÖVE](https://love2d.org) 11.4 in plain Lua. Each side earns
mana and can cast one spell card per turn on top of its normal move. It has a vs-CPU mode, a
15-level campaign, local hot-seat play and online rooms.

Play it on itch: https://funeralpixels.itch.io/chesscast

## Running

Install LÖVE 11.4 or newer, then run it from the repository root:

```bash
love .
```

On Windows, if `love` is not on your PATH:

```bash
"C:/Program Files/LOVE/love.exe" .
```

Command-line flags (handled in `main.lua`):

| Flag | What it does |
|---|---|
| `--test` | Runs the headless test suites and exits with code 0 or 1 |
| `--server host:port` | Points the native online client at another Roomie server |
| `--auto <name>` | Runs a scripted driver from `src/debug/<name>.lua` (not in the repo, see below) |

The `ROOMIE_SERVER` environment variable does the same thing as `--server`.

## Tests

```bash
love . --test
```

This runs `src/chess/test.lua` (move generation and perft), `src/cards/test.lua` (every spell)
and `src/ai/test.lua` (search). It opens no window and prints `ALL TESTS PASSED` when everything
passes. Run it before you push.

## Project layout

```
main.lua            LÖVE callbacks, state registration, --test / --auto handling
conf.lua            window, identity ("chessplus") and module setup
src/
  app.lua           settings, window and audio helpers, App.WEB flag
  chess/            rules engine: board.lua (64-square board, legal moves, check), match.lua (game flow, clock, mana)
  cards/            spells: defs.lua (every card), spells.lua (legality checks), layer.lua (spell state on top of a match)
  ai/               eval.lua and search.lua (alpha-beta that runs as a coroutine so it never blocks a frame)
  campaign/         levels.lua (units, levels, progress), path.lua (node positions on the map)
  states/           one file per screen, switched through manager.lua
  ui/               board view, sidebar, buttons, nineslice panels, text, tutorial overlay
  net/              online play: native TCP (roomie.lua, thread.lua) and browser WebSocket (webnet.lua, wsthread.lua)
  animations/       screen transition and particles
  audio/            sound and music playback
  assets/           image loading and atlases
  utils/            save file, virtual screen, springs, easing, palette, bit ops
assets/             art, audio and fonts used at runtime
relay/              Cloudflare Worker room relay for the browser build
web/index.html      page template for the love.js web build
```

## How it fits together

**Screens.** Every screen is a table registered in `main.lua` with
`M.register(name, state)`. States may define `enter(params)`, `leave`, `update(dt, mx, my)`,
`draw`, `keypressed`, `mousepressed` and so on. Change screens with `M.switch(name, params)`,
which plays the transition, or `M.set` to change instantly.

**Virtual screen.** Everything draws to a 1920×1080 canvas (`src/utils/screen.lua`) that is
scaled to the window. Mouse positions reach states already converted to that space, so lay
things out in 1920×1080 coordinates.

**Art style.** Pixel art drawn with nearest-neighbour filtering, mostly at 3× scale, using a
fixed 4-colour palette in `src/utils/palette.lua`:

| Name | Hex |
|---|---|
| `Pal.N` | `#112E81` |
| `Pal.I` | `#4647AE` |
| `Pal.B` | `#4382DF` |
| `Pal.C` | `#AACCD6` |

Set colours with `Pal.set(Pal.X)`. New art should stick to these four colours.

**Saving.** `src/utils/save.lua` holds the defaults and reads and writes the settings file in
LÖVE's save directory (`%APPDATA%/LOVE/chessplus` on Windows). If you add a setting, give it a
default there so older save files still load.

## Adding a spell

Spells live in `src/cards/defs.lua` as `card { ... }` entries:

```lua
card {
    slug = "swap", name = "SWAP", school = "ARCANE", cost = 2,
    desc = "Two of your pieces (not the king) trade places. You still move.",
    prompt1 = "PICK THE FIRST PIECE", prompt2 = "PICK THE PIECE TO SWAP WITH",
    pick1 = function(b, side) ... end,
    pick2 = function(b, side, a) ... end,
    apply = function(b, side, a, c) ... return true end,
}
```

- `pick1` and `pick2` return lists of candidate squares (1 to 64). Leave both out for a spell
  with no target, or leave out `pick2` for a single target.
- `apply` changes a cloned board and returns `true` on success. `src/cards/spells.lua` rejects
  any cast that leaves your own king in check or the opponent with no legal moves, so `apply`
  doesn't need to check for that.
- `endsTurn = true` means casting the spell uses up the move.
- `school` is one of `ARCANE`, `PROTECTION`, `BLOOD` or `TIME`.
- Card art is loaded from `assets/cards/<slug>.png` (64×96).

Add a test for the new spell to `src/cards/test.lua`.

## Campaign

`src/campaign/levels.lua` defines 3 units of 5 levels each. The last level of each unit is the
boss. Each level sets the CPU difficulty and which colour the player plays. Progress is the
`campaign` number in the save file.

The roadmap screen (`src/states/campaign.lua`) draws `assets/campaign/map.png` at 3× and places
the level nodes using the screen coordinates in `src/campaign/path.lua`. If you change the map
image, update `path.lua` so the nodes stay on the road. `eyes` in that file are the spots where
blinking eyes are drawn.

## Online play

- **Desktop and Android** connect over TCP to a Roomie server (`server.roomielib.com:8765`
  by default) on a background thread (`src/net/thread.lua`).
- **Browser build** can't open TCP, so it uses WebSockets to the PartyServer relay in
  `relay/`. The relay URL is `PARTY_URL` in `src/net/online.lua`.

To deploy your own relay, see `relay/README.md` (`npm install`, `npx wrangler login`,
`npx wrangler deploy`).

Moves and spell casts are sent as short text lines (`src/net/sync.lua`). Both clients run the
same game from a shared seed.

## Building

Builds are standard LÖVE packaging:

- **Desktop:** zip `main.lua`, `conf.lua`, `src/` and `assets/` into a `.love` file. On Windows,
  append it to `love.exe` together with the LÖVE DLLs.
- **Web:** use [love.js](https://github.com/Davidobot/love.js) with `web/index.html` as the page.
- **Android:** use [love-android](https://github.com/love2d/love-android).

Leave `src/debug/` and the `test.lua` files out of release builds. The build scripts and art
generators are kept outside this repository.

## Code style

- No comments in code. Use clear names and small functions instead.
- 4-space indentation, `local` everything, one module table per file returned at the end.
- Keep the 4-colour palette and pixel-perfect drawing (snap positions to whole pixels).
