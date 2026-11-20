# Adding a spell card

This guide walks through adding a new spell card to ChessCast, from the definition to the art, tests and release.

A card touches three places:

| What | Where |
|---|---|
| Rules (targets, effect, cost) | `src/cards/defs.lua` |
| Art (64×96 PNG) | `assets/cards/<slug>.png` |
| Test expectations | `src/cards/test.lua` |

Nothing else needs registering. The hand, the standard deck, the tooltip, the move list, the CPU and online play all read from `Defs.list` automatically. Role cards are the exception: they live in `Defs.roles` and use the rare-deal path described in section 5.

## 1. Define the card

Cards live in `src/cards/defs.lua` as `card { ... }` blocks. Add yours after the existing ones in its school (see section 5 for why the position matters).

```lua
card {
    slug = "frost_nova", name = "FROST NOVA", school = "TIME", cost = 2,
    desc = "Freeze every enemy piece next to one of your pieces. You still move.",
    prompt1 = "PICK ONE OF YOUR PIECES",
    pick1 = ownNonKing,
    apply = function(b, side, a)
        local any = false
        for s = 1, 64 do
            if theirs(b, side, s) and kind(b, s) ~= K and not b:isProtected(s)
                and math.max(abs(FILE[s] - FILE[a]), abs(RANK[s] - RANK[a])) == 1 then
                b:setStatus(b.id[s], "frozen", b.ply + 2)
                any = true
            end
        end
        return any
    end,
}
```

### Fields

| Field | Required | Meaning |
|---|---|---|
| `slug` | yes | Unique lowercase id. It is also the art filename and the online wire id. |
| `name` | yes | Uppercase display name. It must be unique, because the sidebar looks cards up with `Defs.byName`. |
| `school` | yes | One of `ARCANE`, `PROTECTION`, `BLOOD`, `TIME` (`D.SCHOOLS`). |
| `role` | no | `true` for a role card. Role cards are kept out of `Defs.deck`, display as ROLE, and can be dealt by the rare roll. |
| `cost` | yes | Mana cost, from 0 to `Config.ui.card.maxMana`. |
| `desc` | yes | Tooltip text. End it with "You still move." or "Ends your turn." to match the other cards. |
| `apply(b, side, a, c, ctx)` | yes | Changes the board. Return `true` if it worked and `false` to refuse. A card without `apply` is shown as NOT AVAILABLE. |
| `endsTurn` | no | `true` if casting the card replaces your move. |
| `tag` | with `endsTurn` | The move-list text, such as `"*TELEPT"`. Keep it short and start it with `*`. |
| `pick1(b, side, ctx)` | no | Returns a list of squares the player can click first. |
| `prompt1` | with `pick1` | The text shown while picking the first square. |
| `pick2(b, side, a, ctx)` | no | Returns a list of second squares, given the first square `a`. |
| `prompt2` | with `pick2` | The text shown while picking the second square. |
| `can(layer, side)` | no | A precondition outside the board, such as "once per game" or "you have lost a piece". |
| `after(layer, side)` | no | Runs after a successful cast, for effects outside the board (cards, mana, flags). |
| `aiBonus` | no | Extra score the CPU gives this card, for effects its board search can't see, such as drawing cards. |

`index`, `available` and `steps` (0, 1 or 2 targets) are filled in automatically at the bottom of `defs.lua`. Don't set them yourself.

### Target count

- **No targets:** leave out `pick1` and `pick2`. `apply(b, side)` receives `a = nil`.
- **One target:** give `pick1`. `apply(b, side, a)`.
- **Two targets:** give `pick1` and `pick2`. `apply(b, side, a, c)`.

### Rules for `apply`

`apply` runs on a **clone** of the board inside `S.check` (`src/cards/spells.lua`). The game uses the result only if every check below passes, so `apply` can change the clone freely:

- Both kings must still exist.
- The caster must not be left in check. This only applies if they weren't already in check, or if the card ends the turn.
- If the card does **not** end the turn, it must not give check, and the caster must still have a legal move.

The same check filters the squares from `pick1` and `pick2`. Your pick functions can therefore return candidates broadly, and illegal ones never light up.

Each cast must give the same result from the same squares. Don't call `math.random` or `love.math.random` inside `apply`. Online, both clients run `apply` separately and would end up with different boards.

## 2. Board API cheat sheet

The local helpers at the top of `defs.lua` are in scope for every card:

| Helper | What it does |
|---|---|
| `mine(b, side, s)` / `theirs(b, side, s)` | Checks whether square `s` holds your piece or the enemy's |
| `kind(b, s)` | The piece type on `s` (`P N B R Q K` = 1 to 6) |
| `collect(fn)` | Lists every square from 1 to 64 where `fn(s)` is true |
| `ownNonKing(b, side)` | Your pieces, without the king (a ready-made `pick1`) |
| `enemyTargets(b, side, filter)` | Enemy pieces that aren't kings and aren't protected, optionally filtered with `filter(type, s)` |
| `ownOf(b, side, type)` | Your pieces of one type |
| `movePiece(b, from, to)` | Moves a piece and keeps its id and the king tracking correct |
| `destroy(b, s)` | Removes a piece and adds it to the captured list |
| `edgeRank(s)` | True on rank 1 or 8. Never place a pawn there. |
| `bestLost(b, side)` | Your most valuable captured piece that isn't a queen |

Board fields:

- **Squares** are 1 to 64, with `1 = a1`, `8 = h1` and `64 = h8`. `FILE[s]` and `RANK[s]` count from 0. `sq(f, r)` goes the other way.
- **`side`** is `1` for white and `-1` for black. `b.p[s]` holds `type * side`, so positive values are white and `0` is an empty square.
- **`b.id[s]`** is a stable piece id, used as the key for statuses. Keep `b.p` and `b.id` in step whenever you move something (or use `movePiece`).
- **`b.king[side]`** is the king's square. Update it if a king moves.

Statuses are stored per piece id and expire on their own:

```lua
b:setStatus(b.id[s], "shield" | "frozen" | "berserk" | "pawned", untilPly)
b:status(b.id[s], "frozen")
b:isProtected(s)
```

`b:isProtected(s)` covers shields, sanctuary zones and Last Stand. A status stays active while `untilPly > b.ply`, and `b.ply` goes up by one every half-move. In practice:

- `b.ply + 2` lasts through the opponent's next turn (as Freeze does).
- `b.ply + 4` lasts through two opponent turns (as Shield and Sanctuary do).
- `b.ply + 6` lasts through three opponent turns (as Jester's Curse does).

Other board state that cards use: `b.zones` (sanctuary squares), `b.fog[side]`, `b.lastStand[side]`, `b.epAny[side]`, `b.captured[side]`.

### Effects outside the board (`can` / `after`)

`can` and `after` receive the card layer (`src/cards/layer.lua`). These layer members are useful:

| Member | Use |
|---|---|
| `layer.match.board` | The live board (read only in `can`) |
| `layer.manaOf[side]`, `layer:gainMana(side, n)` | Mana |
| `layer:drawCards(side, n)`, `layer:addCard(side, def)` | Cards in hand (capped by `Config.ui.card.maxHand`) |
| `layer.lastSpell[side]` | The last card that side cast |

For a once-per-game flag, add a field to the layer's constructor (look at how `double` and `ward` are set up next to `manaOf`), check it in `can` and set it in `after`.

## 3. Art

1. Make a **64×96 PNG** with transparency at `assets/cards/<slug>.png`. `Config.assets.imageSizes` holds the source size; `Config.ui.card` holds the in-game size.
2. Use the shared card frame: copy any existing card and redraw only the inside. Stick to the four palette colours:

   | Colour | RGB |
   |---|---|
   | Dark | `17, 46, 129` |
   | Mid | `70, 71, 174` |
   | Bright | `67, 130, 223` |
   | Light | `170, 204, 214` |

3. Keep the filename equal to the slug. Art loading reads `Defs.list` automatically; a missing file shows a placeholder rather than crashing.

## 4. Tests

The suite checks every card for a unique slug and name, a known school, `apply` and art.
Add at least one case for the new card next to the others. `fen()` gives you a board and a fake layer, and `cast()` runs the real castable → check → restore → `after` path:

```lua
case("frost nova", function()
    local b, L = fen("4k3/8/8/3p4/3N4/8/8/4K3 w - - 0 20")
    local ok = cast(L, "frost_nova", "d4")
    return ok and b:status(b.id[sqn("d5")], "frozen")
end)
```

Use a ply past `Config.cards.opening` in the FEN, or the cast is refused with NO SPELLS IN THE OPENING (`S.OPENING`). Then run:

```bash
love . --test
```

It must end with `ALL TESTS PASSED`. The suite also runs random games that cast every card, which catches crashes in `pick` and `apply`.

## 5. Online play and the deck

- Online casts are sent as `C <slug> <a> <c>` (`src/net/sync.lua`). The receiving client looks up `Defs.bySlug` and runs `apply` itself. **Both players need a build that includes the card.** Never rename an existing slug.
- Each standard deck is one copy of every card in `Defs.deck`, shuffled with the room's seed. The deck order therefore depends on the order of `Defs.deck`, so adding or moving a normal card breaks online games between old and new builds. Ship a new card as a release that all platforms update to together (Web, Windows, Linux and Android).
- Role cards are not in the standard deck. At the start of the game, each player has a 1 in `Config.cards.roleOdds` chance to receive one random card from `Defs.roles` in their opening hand. The roll uses `layer.rng` when the game has a seed, so both online clients make the same decision.

## 6. Try it and ship it

1. Run `love .`, start a game against the CPU, play 4 moves each so spells unlock, and get the card into your hand. Check the tooltip, the target highlights, the effect and the move-list entry.
2. Run the tests (section 4).
3. Package with the usual LÖVE build steps.

## 7. Cards that need more than this

Some designs don't fit the framework above. Plan these with the team before building them:

- **Role cards.** Set `role = true`, add the 64×96 art, and tune `Config.cards.roleOdds` deliberately. The card stays out of `Defs.deck`; the seeded rare-deal path in `Layer` can put it in an opening hand. Do not add a role card to `Defs.deck` as well.
- **Changing piece types for a few turns.** Jester's Curse shows the pattern: keep the real type in `b.p`, add a `"pawned"` status on the piece id, and let that status change movement, attacks, castling, display and CPU evaluation until it expires. The engine assumes exactly one king per side, so never write a temporary king or pawn into `b.p` when the original must return.
- **Effects that wait for a later turn** (delayed damage, triggers when a piece moves). Look at how `Board:removeExpired` and zones work, and keep any new state inside `Board:clone()` so `S.check` and the CPU can see it.
