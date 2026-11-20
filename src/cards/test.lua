local Config = require("src.config")
local Board = require("src.chess.board")
local Defs = require("src.cards.defs")
local S = require("src.cards.spells")
local Layer = require("src.cards.layer")
local OPENING = S.OPENING

local T = {}
local P, N, B, R, Q, K = Board.P, Board.N, Board.B, Board.R, Board.Q, Board.K

local function sqn(name) return Board.sq(name:byte(1) - 97, name:byte(2) - 49) end

local function fakeLayer(b)
    local L = {
        match = { board = b },
        manaOf = { [1] = 3, [-1] = 3 },
        castThisTurn = { [1] = false, [-1] = false },
        ward = { [1] = 0, [-1] = 0 },
        double = {}, lastSpell = {},
        drawn = 0, gained = 0, added = nil, snap = nil,
    }
    function L:snapshotFor() return self.snap end
    function L:drawCards(_, n) self.drawn = self.drawn + n end
    function L:gainMana(_, n) self.gained = self.gained + n end
    function L:addCard(_, d) self.added = d; return true end
    return L
end

local function integrity(b)
    local seen = {}
    local kings = { [1] = 0, [-1] = 0 }
    for s = 1, 64 do
        local pc, id = b.p[s], b.id[s]
        if pc == 0 then
            if id ~= 0 then return false, "id on empty square " .. Board.name(s) end
        else
            if id == 0 or seen[id] then return false, "bad id on " .. Board.name(s) end
            seen[id] = true
            local side = pc > 0 and 1 or -1
            if math.abs(pc) == K then
                kings[side] = kings[side] + 1
                if b.king[side] ~= s then return false, "king index wrong" end
            end
            if math.abs(pc) == P and (Board.RANK[s] == 0 or Board.RANK[s] == 7) then
                return false, "pawn on edge rank " .. Board.name(s)
            end
        end
    end
    if kings[1] ~= 1 or kings[-1] ~= 1 then return false, "king count" end
    local c = b.castle
    local function has(bitv) return math.floor(c / bitv) % 2 == 1 end
    if has(1) and (b.p[sqn("e1")] ~= K or b.p[sqn("h1")] ~= R) then return false, "castle K" end
    if has(2) and (b.p[sqn("e1")] ~= K or b.p[sqn("a1")] ~= R) then return false, "castle Q" end
    if has(4) and (b.p[sqn("e8")] ~= -K or b.p[sqn("h8")] ~= -R) then return false, "castle k" end
    if has(8) and (b.p[sqn("e8")] ~= -K or b.p[sqn("a8")] ~= -R) then return false, "castle q" end
    if b.ep ~= 0 then
        local pawnSq = b.ep - 8 * b.side
        if b.p[b.ep] ~= 0 or b.p[pawnSq] ~= -P * b.side then return false, "stale ep" end
    end
    return true
end
T.integrity = integrity

local function hasMove(b, from, to)
    local list, n = b:legalMoves({})
    for i = 1, n do
        local m = list[i]
        if Board.from(m) == from and Board.to(m) == to then return true, m end
    end
    return false
end

local function play(b, uci)
    local ok, m = hasMove(b, sqn(uci:sub(1, 2)), sqn(uci:sub(3, 4)))
    assert(ok, "illegal test move " .. uci)
    b:play(m)
    b:removeExpired()
end

local function contains(list, s)
    for _, v in ipairs(list) do if v == s then return true end end
    return false
end

local function cast(L, slug, a, c, ctx)
    local b = L.match.board
    local side = b.side
    local def = Defs.bySlug[slug]
    local ok, why = S.castable(b, side, def, L, ctx)
    if not ok then return false, why end
    local nb
    ok, nb = S.check(b, side, def, a and sqn(a), c and sqn(c), ctx)
    if not ok then return false, "check refused" end
    Defs.restore(b, nb)
    if def.after then def.after(L, side) end
    return true
end

local function fen(f) local b = Board.fromFEN(f); return b, fakeLayer(b) end

local CASES = {}
local function case(name, fn) CASES[#CASES + 1] = { name, fn } end

case("teleport", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "teleport", "b1", "d4")
    return ok and b.p[sqn("d4")] == N and b.p[sqn("b1")] == 0 and b.side == -1
end)
case("teleport pinned piece refused", function()
    local b = Board.fromFEN("4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1")
    local def = Defs.bySlug.teleport

    local t = S.secondTargets(b, 1, def, sqn("e2"), {})
    for _, c in ipairs(t) do
        if Board.FILE[c] ~= 4 or Board.RANK[c] > 5 then return false end
    end
    return #t == 4
end)
case("swap", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "swap", "b1", "c1")
    return ok and b.p[sqn("b1")] == B and b.p[sqn("c1")] == N and b.side == 1
end)
case("swap pawn to back rank refused", function()
    local b = Board.fromFEN(Board.START_FEN)
    local def = Defs.bySlug.swap
    return not contains(S.secondTargets(b, 1, def, sqn("e2"), {}), sqn("b1"))
end)
case("magnetic pull", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "magnetic_pull", "e7")
    return ok and b.p[sqn("e6")] == -P and b.p[sqn("e7")] == 0
end)
case("magnetic pull never the king", function()
    local b = Board.fromFEN("8/8/8/4k3/8/8/8/4K3 w - - 0 1")
    return #S.firstTargets(b, 1, Defs.bySlug.magnetic_pull, {}) == 0
end)
case("magnetic pull cannot give check", function()

    local b = Board.fromFEN("4k3/3n4/8/8/B7/8/8/K7 w - - 0 1")
    return not contains(S.firstTargets(b, 1, Defs.bySlug.magnetic_pull, {}), sqn("d7"))
end)
case("reverse gravity", function()
    local b, L = fen("4k3/8/8/4p3/8/8/8/4K3 w - - 0 1")
    local ok = cast(L, "reverse_gravity")
    return ok and b.p[sqn("e6")] == -P
end)
case("rook's gambit", function()
    local b, L = fen("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
    local ok = cast(L, "rooks_gambit", "a1")
    return ok and b.p[sqn("a1")] == K and b.p[sqn("e1")] == R and b.castle == 0 and b.side == -1
end)
case("rook's gambit into check refused", function()
    local b = Board.fromFEN("r3k3/8/8/8/8/8/8/R3K3 w - - 0 1")
    local _, L = b, fakeLayer(b)
    return not cast(L, "rooks_gambit", "a1")
end)
case("no spells in the opening", function()
    local b, L = fen(Board.START_FEN)
    S.OPENING = OPENING
    local early = S.castable(b, 1, Defs.bySlug.shield, L, {})
    b.ply = OPENING
    local late = S.castable(b, 1, Defs.bySlug.shield, L, {})
    S.OPENING = 0
    return not early and late
end)
case("double strike", function()
    local b, L = fen(Board.START_FEN)
    if cast(L, "double_strike") then return false end
    b.ply = 10
    local ok = cast(L, "double_strike")
    return ok and L.double[1] == true
end)
case("shield", function()
    local b, L = fen("4k3/8/8/4p3/3N4/8/8/4K3 w - - 0 1")
    if not cast(L, "shield", "d4") then return false end
    play(b, "e1e2")
    return not hasMove(b, sqn("e5"), sqn("d4"))
end)
case("dispel", function()
    local b, L = fen("4k3/8/8/4p3/3N4/8/8/4K3 b - - 0 1")
    b:setStatus(b.id[sqn("e5")], "shield", b.ply + 4)
    b.side = 1
    local ok = cast(L, "dispel")
    return ok and not b:isProtected(sqn("e5"))
end)
case("dispel with nothing to remove refused", function()
    local _, L = fen(Board.START_FEN)
    return not cast(L, "dispel")
end)
case("sanctuary", function()
    local b, L = fen("4k3/8/8/4p3/3N4/8/8/4K3 w - - 0 1")
    if not cast(L, "sanctuary", "c3") then return false end
    play(b, "e1e2")
    return not hasMove(b, sqn("e5"), sqn("d4"))
end)
case("fog of war", function()
    local b, L = fen("r3k3/8/8/8/8/8/8/4K3 w - - 0 1")
    if not cast(L, "fog_of_war") then return false end
    play(b, "e1e2")
    local list, n = b:legalMoves({})
    for i = 1, n do
        local m = list[i]
        if Board.from(m) == sqn("a8") and Board.dist(sqn("a8"), Board.to(m)) > 2 then return false end
    end
    return hasMove(b, sqn("a8"), sqn("a6"))
end)
case("checkmate's grace", function()
    local b, L = fen("4k3/8/8/8/8/8/8/r3K3 w - - 0 1")
    local t = S.firstTargets(b, 1, Defs.bySlug.checkmates_grace, {})
    if contains(t, sqn("g1")) or contains(t, sqn("d1")) or not contains(t, sqn("e3")) then return false end
    local ok = cast(L, "checkmates_grace", "e3")
    return ok and b.king[1] == sqn("e3") and b.side == -1
end)
case("counterspell", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "counterspell")
    return ok and L.ward[1] > b.ply
end)
case("sacrifice", function()
    local b, L = fen(Board.START_FEN)
    if contains(S.secondTargets(b, 1, Defs.bySlug.sacrifice, sqn("b1"), {}), sqn("d8")) then return false end
    local ok = cast(L, "sacrifice", "b1", "c8")
    return ok and b.p[sqn("b1")] == 0 and b.p[sqn("c8")] == 0 and #b.captured[1] == 1 and #b.captured[-1] == 1
end)
case("resurrection", function()
    local b, L = fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    b.captured[1] = { { t = N, id = 98 }, { t = R, id = 99 }, { t = Q, id = 97 } }
    local ok = cast(L, "resurrection", "a1")
    return ok and b.p[sqn("a1")] == R and b.id[sqn("a1")] == 99 and #b.captured[1] == 2
end)
case("resurrection needs a lost piece", function()
    local _, L = fen(Board.START_FEN)
    return not cast(L, "resurrection", "a3")
end)
case("berserk", function()
    local b, L = fen("4k3/8/8/8/8/8/8/N3K3 w - - 0 1")
    if not cast(L, "berserk", "a1") then return false end
    return hasMove(b, sqn("a1"), sqn("a5")) and hasMove(b, sqn("a1"), sqn("b3"))
end)
case("blood pact", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "blood_pact", "a2")
    return ok and b.p[sqn("a2")] == 0 and L.drawn == 2 and L.gained == 1
end)
case("rebirth", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "rebirth", "d2")
    return ok and b.p[sqn("d2")] == N
end)
case("last stand", function()
    local b, L = fen("4k3/8/8/8/8/4p3/3N3P/4K3 w - - 0 1")
    if not cast(L, "last_stand") then return false end
    play(b, "h2h3")
    return not hasMove(b, sqn("e3"), sqn("d2"))
end)
case("time rewind", function()
    local b, L = fen(Board.START_FEN)
    local snap = b:clone()
    play(b, "e2e4"); play(b, "e7e5")
    L.snap = { board = snap, hist = 0 }
    local ok = cast(L, "time_rewind", nil, nil, { snapshot = snap })
    return ok and b.p[sqn("e2")] == P and b.p[sqn("e4")] == 0 and b.p[sqn("e7")] == -P and b.side == 1
end)
case("freeze", function()
    local b, L = fen(Board.START_FEN)
    if not cast(L, "freeze", "b8") then return false end
    play(b, "e2e4")
    return not hasMove(b, sqn("b8"), sqn("c6")) and hasMove(b, sqn("g8"), sqn("f6"))
end)
case("haste", function()
    local b, L = fen(Board.START_FEN)
    local ok = cast(L, "haste", "e2")
    return ok and b.p[sqn("e3")] == P and b.side == 1
end)
case("en passant", function()
    local b, L = fen("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1")
    if hasMove(b, sqn("e5"), sqn("d6")) then return false end
    if not cast(L, "en_passant") then return false end
    local ok, m = hasMove(b, sqn("e5"), sqn("d6"))
    if not ok then return false end
    b:play(m)
    return b.p[sqn("d5")] == 0 and b.p[sqn("d6")] == P
end)
case("temporal echo", function()
    local _, L = fen(Board.START_FEN)
    if cast(L, "temporal_echo") then return false end
    L.lastSpell[1] = Defs.bySlug.shield
    local ok = cast(L, "temporal_echo")
    return ok and L.added == Defs.bySlug.shield
end)
case("meteor", function()
    local b, L = fen(Board.START_FEN)
    local t = S.firstTargets(b, 1, Defs.bySlug.meteor, {})
    if contains(t, sqn("d8")) or contains(t, sqn("e8")) then return false end
    local ok = cast(L, "meteor", "b8")
    return ok and b.p[sqn("b8")] == 0 and b.side == -1
end)
case("meteor cannot hit a shielded piece", function()
    local b = Board.fromFEN(Board.START_FEN)
    b:setStatus(b.id[sqn("b8")], "shield", b.ply + 4)
    return not contains(S.firstTargets(b, 1, Defs.bySlug.meteor, {}), sqn("b8"))
end)
case("quick spell while in check must not ignore it", function()

    local b, L = fen("4r1k1/8/8/8/8/8/P7/4K3 w - - 0 1")
    if not cast(L, "haste", "a2") then return false end
    return b:inCheck(1) and b:hasLegalMove()
end)
case("spell ending the turn may not leave the caster in check", function()
    local b = Board.fromFEN("4r1k1/8/8/8/8/8/8/N3K3 w - - 0 1")
    local def = Defs.bySlug.teleport

    for _, c in ipairs(S.secondTargets(b, 1, def, sqn("a1"), {})) do
        if Board.FILE[c] ~= 4 then return false end
    end
    return #S.secondTargets(b, 1, def, sqn("a1"), {}) > 0
end)
case("one spell per turn and mana", function()
    local b, L = fen(Board.START_FEN)
    if not cast(L, "haste", "e2") then return false end
    L.castThisTurn[1] = true
    local ok, why = S.castable(b, 1, Defs.bySlug.haste, L, {})
    if ok or why ~= "ONE SPELL PER TURN" then return false end
    L.castThisTurn[1] = false
    L.manaOf[1] = 0
    ok, why = S.castable(b, 1, Defs.bySlug.haste, L, {})
    return not ok and why == "NOT ENOUGH MANA"
end)
case("spells refuse impossible targets", function()
    local b = Board.fromFEN(Board.START_FEN)
    local def = Defs.bySlug.teleport
    local king = S.check(b, 1, def, sqn("e1"), sqn("e3"), {})
    local occupied = S.check(b, 1, def, sqn("b1"), sqn("e1"), {})
    local valid = S.check(b, 1, def, sqn("b1"), sqn("d4"), {})
    return not king and not occupied and valid ~= nil
end)
case("fog of war limits distant checks", function()
    local b = Board.fromFEN("k3r3/8/8/8/8/8/8/4K3 w - - 0 1")
    if not b:inCheck(1) then return false end
    local ok, nb = S.check(b, 1, Defs.bySlug.fog_of_war, nil, nil, {})
    return ok and not nb:inCheck(1)
end)
case("fog of war keeps close checks", function()
    local b = Board.fromFEN("k7/8/8/8/8/4r3/8/4K3 w - - 0 1")
    if not b:inCheck(1) then return false end
    local ok, nb = S.check(b, 1, Defs.bySlug.fog_of_war, nil, nil, {})
    return ok and nb:inCheck(1)
end)
case("magnetic pull skips protected pieces", function()
    local b = Board.fromFEN(Board.START_FEN)
    b:setStatus(b.id[sqn("e7")], "shield", b.ply + 4)
    return not contains(S.firstTargets(b, 1, Defs.bySlug.magnetic_pull, {}), sqn("e7"))
end)
case("teleport keeps pawns off the back ranks", function()
    local b = Board.fromFEN(Board.START_FEN)
    local targets = S.secondTargets(b, 1, Defs.bySlug.teleport, sqn("e2"), {})
    for _, s in ipairs(targets) do
        if Board.RANK[s] == 0 or Board.RANK[s] == 7 then return false end
    end
    return #targets > 0
end)
case("teleport keeps pawned pieces off the back ranks", function()
    local b = Board.fromFEN("4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1")
    b:setStatus(b.id[sqn("e2")], "pawned", b.ply + 6)
    local targets = S.secondTargets(b, 1, Defs.bySlug.teleport, sqn("e2"), {})
    for _, s in ipairs(targets) do
        if Board.RANK[s] == 0 or Board.RANK[s] == 7 then return false end
    end
    return #targets > 0
end)
case("swap keeps pawned pieces off the back ranks", function()
    local b = Board.fromFEN("4k3/8/8/8/8/2B5/4Q3/R3K2R w KQ - 0 1")
    b:setStatus(b.id[sqn("e2")], "pawned", b.ply + 6)
    local targets = S.secondTargets(b, 1, Defs.bySlug.swap, sqn("e2"), {})
    for _, s in ipairs(targets) do
        if Board.RANK[s] == 0 or Board.RANK[s] == 7 then return false end
    end
    return #targets > 0
end)
case("magnetic pull keeps pawned pieces off the back ranks", function()
    local b = Board.fromFEN("k7/7K/8/8/8/8/4q3/8 w - - 0 1")
    b:setStatus(b.id[sqn("e2")], "pawned", b.ply + 6)
    return not contains(S.firstTargets(b, 1, Defs.bySlug.magnetic_pull, {}), sqn("e2"))
end)
case("capturing a pawned piece clears its status", function()
    local b = Board.fromFEN("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1")
    local id = b.id[sqn("d5")]
    b:setStatus(id, "pawned", b.ply + 6)
    play(b, "d2d5")
    local c = b.captured[-1][1]
    return b.st[id] == nil and c and c.pawned == true and c.t == Q
end)
case("haste needs an empty forward square", function()
    local b = Board.fromFEN("4k3/8/8/4p3/4P3/8/8/4K3 w - - 0 1")
    return not contains(S.firstTargets(b, 1, Defs.bySlug.haste, {}), sqn("e4"))
end)
case("haste cannot promote on the last rank", function()
    local b = Board.fromFEN("4k3/4P3/8/8/8/8/8/4K3 w - - 0 1")
    return #S.firstTargets(b, 1, Defs.bySlug.haste, {}) == 0
end)
case("meteor never targets a queen", function()
    local b = Board.fromFEN("3qk3/8/8/8/8/8/8/4K3 w - - 0 1")
    return not contains(S.firstTargets(b, 1, Defs.bySlug.meteor, {}), sqn("d8"))
end)
case("freeze never targets the king", function()
    local b = Board.fromFEN("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    return #S.firstTargets(b, 1, Defs.bySlug.freeze, {}) == 0
end)
case("reverse gravity with no legal retreat fails", function()
    local b = Board.fromFEN("4k3/4p3/4p3/8/8/8/8/4K3 w - - 0 1")
    return not S.check(b, 1, Defs.bySlug.reverse_gravity, nil, nil, {})
end)
case("shield expires after its duration", function()
    local b, L = fen("4k3/8/8/4p3/3N4/8/8/4K3 w - - 0 1")
    if not cast(L, "shield", "d4") then return false end
    local s = sqn("d4")
    if not b:isProtected(s) then return false end
    b.ply = b.ply + 3; b:removeExpired()
    local active = b:isProtected(s)
    b.ply = b.ply + 1; b:removeExpired()
    return active and not b:isProtected(s)
end)
case("freeze expires after one enemy turn", function()
    local b, L = fen(Board.START_FEN)
    if not cast(L, "freeze", "b8") then return false end
    local id = b.id[sqn("b8")]
    b.ply = b.ply + 1; b:removeExpired()
    local active = b:status(id, "frozen")
    b.ply = b.ply + 1; b:removeExpired()
    return active and not b:status(id, "frozen")
end)
case("fog expiry restores slider range", function()
    local b, L = fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    if not cast(L, "fog_of_war") then return false end
    local untilPly = b.fog[-1]
    b.ply = untilPly - 1
    if not (b.fog[-1] > b.ply) then return false end
    b.ply = untilPly
    return not (b.fog[-1] > b.ply)
end)
case("sanctuary expires", function()
    local b, L = fen("4k3/8/8/4p3/3N4/8/8/4K3 w - - 0 1")
    if not cast(L, "sanctuary", "c3") then return false end
    local z = b.zones[1]
    if not z then return false end
    b.ply = z.untilPly - 1; b:removeExpired()
    if #b.zones == 0 then return false end
    b.ply = z.untilPly; b:removeExpired()
    return #b.zones == 0
end)
case("time rewind needs a past turn", function()
    local b, L = fen(Board.START_FEN)
    b.ply = 10
    return not cast(L, "time_rewind")
end)
case("last stand needs an adjacent piece", function()
    local b, L = fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    b.ply = 10
    return not S.castable(b, 1, Defs.bySlug.last_stand, L, {})
end)
case("double strike opens on move six", function()
    local b, L = fen(Board.START_FEN)
    b.ply = 9
    local early = S.castable(b, 1, Defs.bySlug.double_strike, L, {})
    b.ply = 10
    local late = S.castable(b, 1, Defs.bySlug.double_strike, L, {})
    return not early and late and cast(L, "double_strike") and L.double[1] == true
end)
case("jester's curse pawns every enemy piece except the king", function()
    local b, L = fen("4k3/8/8/3q4/8/8/8/4K3 w - - 0 1")
    if not cast(L, "jesters_curse") then return false end
    local q, k = sqn("d5"), sqn("e8")
    if b.p[q] ~= -Q or b.p[k] ~= -K then return false end
    if not b:status(b.id[q], "pawned") or b:status(b.id[k], "pawned") then return false end
    if b.side ~= -1 then return false end
    return hasMove(b, q, sqn("d4")) and not hasMove(b, q, sqn("d1"))
end)
case("jester's curse reverts after three enemy turns", function()
    local b, L = fen("4k3/8/8/3q4/8/8/8/4K3 w - - 0 1")
    if not cast(L, "jesters_curse") then return false end
    local q, id = sqn("d5"), b.id[sqn("d5")]
    local untilPly = b.st[id].pawned
    b.ply = untilPly - 1
    b:removeExpired()
    if not b:status(id, "pawned") or hasMove(b, q, sqn("d1")) then return false end
    b.ply = untilPly
    b:removeExpired()
    return not b:status(id, "pawned") and b.p[q] == -Q and hasMove(b, q, sqn("d1"))
end)
case("jester's curse leaves enemy pawns alone", function()
    local b, L = fen("4k3/4p3/8/3q4/8/8/8/4K3 w - - 0 1")
    if not cast(L, "jesters_curse") then return false end
    local p = sqn("e7")
    return b.p[p] == -P and not b:status(b.id[p], "pawned") and hasMove(b, p, sqn("e5"))
end)
case("jester's curse removes the rook's check", function()
    local b, L = fen("4r2k/8/8/8/8/8/8/4K3 w - - 0 1")
    if not b:inCheck(1) or not cast(L, "jesters_curse") then return false end
    local r = sqn("e8")
    return not b:inCheck(1) and b.p[r] == -R and b:status(b.id[r], "pawned")
end)
case("a pawned rook attacks diagonally", function()
    local b = Board.fromFEN("7k/8/8/3r4/4K3/8/8/8 w - - 0 1")
    b:setStatus(b.id[sqn("d5")], "pawned", b.ply + 6)
    return b:isAttacked(sqn("e4"), -1) and not b:isAttacked(sqn("d1"), -1)
end)
case("a pawned piece cannot promote", function()
    local b = Board.fromFEN("4k3/8/8/8/8/8/1r6/4K3 b - - 0 1")
    local s = sqn("b2")
    b:setStatus(b.id[s], "pawned", b.ply + 6)
    return not hasMove(b, s, sqn("b1"))
end)
case("a pawned rook cannot castle", function()
    local b = Board.fromFEN("4k3/8/8/8/8/8/8/4K2R w K - 0 1")
    b:setStatus(b.id[sqn("h1")], "pawned", b.ply + 6)
    local list, n = b:legalMoves({})
    for i = 1, n do if Board.flag(list[i]) == 3 then return false end end
    return true
end)
case("pawned status survives cloning and expires", function()
    local b = Board.fromFEN("4k3/8/8/3q4/8/8/8/4K3 w - - 0 1")
    b:setStatus(b.id[sqn("d5")], "pawned", b.ply + 2)
    local c = b:clone()
    if not c:status(c.id[sqn("d5")], "pawned") then return false end
    c.ply = c.ply + 2
    c:removeExpired()
    return not c:status(c.id[sqn("d5")], "pawned")
end)

local FUZZ_FENS = {
    Board.START_FEN,
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N2N2/PP2BPPP/R2QKB1R w KQ - 0 8",
}

local function fuzz(log, seed, plies, cap)
    local rng = love.math.newRandomGenerator(seed)
    local tried, accepted, games = 0, 0, 0
    local function pick(list) return list[rng:random(#list)] end
    local function sample(list, n)
        for i = #list, 2, -1 do
            local j = rng:random(i)
            list[i], list[j] = list[j], list[i]
        end
        for i = #list, n + 1, -1 do list[i] = nil end
        return list
    end
    for _, f in ipairs(FUZZ_FENS) do
        games = games + 1
        local b = Board.fromFEN(f)
        local L = fakeLayer(b)
        local snaps = {}
        for _ = 1, plies do
            local side = b.side
            snaps[b.ply] = b:clone()
            local e = snaps[b.ply - 2]
            local ctx = { snapshot = e and e.side == side and e or nil }
            L.snap = ctx.snapshot and { board = ctx.snapshot } or nil
            L.lastSpell[side] = Defs.bySlug.shield
            local options = {}
            for _, def in ipairs(Defs.list) do
                local combos = {}
                if def.steps == 0 then
                    combos[1] = {}
                else
                    for _, a in ipairs(sample(def.pick1(b, side, ctx), cap)) do
                        if def.steps == 1 then
                            combos[#combos + 1] = { a }
                        else
                            for _, c in ipairs(sample(def.pick2(b, side, a, ctx), 3)) do
                                combos[#combos + 1] = { a, c }
                            end
                        end
                    end
                end
                for _, cb in ipairs(combos) do
                    tried = tried + 1
                    local can = not def.can or def.can(L, side)
                    local ok, nb = S.check(b, side, def, cb[1], cb[2], ctx)
                    if ok and can then
                        accepted = accepted + 1
                        local good, why = integrity(nb)
                        if not good then
                            log("fuzz: " .. def.slug .. " broke the board: " .. why)
                            return false
                        end
                        if nb:inCheck(side) and (def.endsTurn or not b:inCheck(side)) then
                            log("fuzz: " .. def.slug .. " left the caster in check")
                            return false
                        end
                        if not def.endsTurn and nb:inCheck(-side) then
                            log("fuzz: " .. def.slug .. " (quick) attacked the enemy king")
                            return false
                        end
                        options[#options + 1] = { def, nb }
                    end
                end
            end

            if #options > 0 and rng:random() < 0.45 then
                local o = pick(options)
                Defs.restore(b, o[2])
                if o[1].after then o[1].after(L, side) end
            end
            if b.side == side then
                local list, n = b:legalMoves({})
                if n == 0 then break end
                b:play(list[rng:random(n)])
                b:removeExpired()
                if b:inCheck(side) then
                    log("fuzz: a legal move left the mover in check")
                    return false
                end
            end
            local good, why = integrity(b)
            if not good then
                log("fuzz: game board broken: " .. why)
                return false
            end
            if not b:hasLegalMove() then break end
        end
    end
    log(string.format("cards fuzz: %d games, %d casts tried, %d accepted, all consistent", games, tried, accepted))
    return true
end

function T.run(log)
    log = log or print
    local ok = true
    local previousOpening = S.OPENING
    S.OPENING = 0

    local missing = 0
    local seenSlug, seenName, schools = {}, {}, {}
    for _, def in ipairs(Defs.list) do
        local art = love.filesystem.getInfo(Config.assets.cards .. def.slug .. ".png")
        if not def.available or not art then
            log("card " .. def.slug .. ": " .. (def.available and "missing art" or "UNAVAILABLE"))
            missing = missing + 1
        end
        if seenSlug[def.slug] then log("duplicate card slug: " .. def.slug); ok = false end
        if seenName[def.name] then log("duplicate card name: " .. def.name); ok = false end
        seenSlug[def.slug], seenName[def.name] = true, true
        schools[def.school] = (schools[def.school] or 0) + 1
    end
    if #Defs.list == 0 then log("no cards defined"); ok = false end
    if missing > 0 then ok = false end
    local standard, roleCards = 0, 0
    for _, def in ipairs(Defs.list) do
        if def.role then roleCards = roleCards + 1 else standard = standard + 1 end
    end
    if #Defs.roles == 0 then log("no role cards defined"); ok = false end
    if #Defs.deck ~= standard or #Defs.roles ~= roleCards or #Defs.deck + #Defs.roles ~= #Defs.list then
        log("standard and role decks do not partition Defs.list")
        ok = false
    end
    for _, def in ipairs(Defs.deck) do
        if def.role then log("role card in standard deck: " .. def.slug); ok = false end
    end
    local piles = setmetatable({ discard = { [1] = {} } }, Layer)
    piles:discardCard(1, Defs.roles[1])
    if #piles.discard[1] ~= 0 then log("role card entered discard pile"); ok = false end
    piles:discardCard(1, Defs.deck[1])
    if #piles.discard[1] ~= 1 or piles.discard[1][1] ~= Defs.deck[1] then
        log("standard card missing from discard pile")
        ok = false
    end
    for _, sc in ipairs(Defs.SCHOOLS) do
        if not schools[sc] then log("school " .. sc .. " has no cards"); ok = false end
    end
    for school in pairs(schools) do
        if not table.concat(Defs.SCHOOLS, " "):find(school, 1, true) then
            log("unknown card school: " .. tostring(school)); ok = false
        end
    end

    local passed = 0
    for _, c in ipairs(CASES) do
        local good, res = pcall(c[2])
        if good and res then
            passed = passed + 1
        else
            log("card case FAIL: " .. c[1] .. (good and "" or (" (" .. tostring(res) .. ")")))
            ok = false
        end
    end
    log(string.format("card cases: %d/%d passed", passed, #CASES))

    local t0 = os.clock()
    for _, seed in ipairs({ 1234, 77, 2026 }) do
        if not fuzz(log, seed, 70, 10) then ok = false; break end
    end
    log(string.format("cards fuzz took %.1fs", os.clock() - t0))
    S.OPENING = previousOpening
    return ok
end

return T
