local Board = require("src.chess.board")

local P, N, B, R, Q, K = Board.P, Board.N, Board.B, Board.R, Board.Q, Board.K
local FILE, RANK, sq = Board.FILE, Board.RANK, Board.sq
local abs = math.abs

local D = {}
D.VAL = { 1, 3, 3, 5, 9, 0 }
local VAL = D.VAL

D.SCHOOLS = { "ARCANE", "PROTECTION", "BLOOD", "TIME" }

local function mine(b, side, s) local pc = b.p[s]; return pc ~= 0 and (pc > 0) == (side > 0) end
local function theirs(b, side, s) local pc = b.p[s]; return pc ~= 0 and (pc > 0) ~= (side > 0) end
local function kind(b, s) return abs(b.p[s]) end
local function edgeRank(s) return RANK[s] == 0 or RANK[s] == 7 end

local function collect(fn)
    local t = {}
    for s = 1, 64 do if fn(s) then t[#t + 1] = s end end
    return t
end

local function movePiece(b, from, to)
    local pc = b.p[from]
    b.p[to], b.id[to] = pc, b.id[from]
    b.p[from], b.id[from] = 0, 0
    if abs(pc) == K then b.king[pc > 0 and 1 or -1] = to end
end

local function destroy(b, s)
    local pc = b.p[s]
    local owner = pc > 0 and 1 or -1
    local list = b.captured[owner]
    list[#list + 1] = { t = abs(pc), id = b.id[s] }
    b.st[b.id[s]] = nil
    b.p[s], b.id[s] = 0, 0
    b.half = 0
end
D.destroy = destroy

local function ownNonKing(b, side)
    return collect(function(s) return mine(b, side, s) and kind(b, s) ~= K end)
end

local function enemyTargets(b, side, filter)
    return collect(function(s)
        return theirs(b, side, s) and kind(b, s) ~= K and not b:isProtected(s) and (not filter or filter(kind(b, s), s))
    end)
end

local function ownOf(b, side, t)
    return collect(function(s) return b.p[s] == t * side end)
end

local function bestLost(b, side)
    local list = b.captured[side]
    local best, bi = -1, nil
    for i = #list, 1, -1 do
        local t = list[i].t
        if t ~= Q and t ~= K and VAL[t] > best then best, bi = VAL[t], i end
    end
    return bi
end
D.bestLost = bestLost

function D.restore(dst, src)
    local c = src:clone()
    for k, v in pairs(c) do dst[k] = v end
end

local cards = {}
local function card(t) cards[#cards + 1] = t; return t end

card {
    slug = "teleport", name = "TELEPORT", school = "ARCANE", cost = 2, endsTurn = true, tag = "*TELEPT",
    desc = "Move one of your pieces (not the king) to any empty square. Ends your turn.",
    prompt1 = "PICK A PIECE TO TELEPORT", prompt2 = "PICK AN EMPTY SQUARE",
    pick1 = ownNonKing,
    pick2 = function(b, side, a)
        local pawn = kind(b, a) == P
        return collect(function(s) return b.p[s] == 0 and not (pawn and edgeRank(s)) end)
    end,
    apply = function(b, side, a, c) movePiece(b, a, c); return true end,
}

card {
    slug = "swap", name = "SWAP", school = "ARCANE", cost = 2,
    desc = "Two of your pieces (not the king) trade places. You still move.",
    prompt1 = "PICK THE FIRST PIECE", prompt2 = "PICK THE PIECE TO SWAP WITH",
    pick1 = ownNonKing,
    pick2 = function(b, side, a)
        return collect(function(s)
            if s == a or not mine(b, side, s) or kind(b, s) == K then return false end
            if kind(b, a) == P and edgeRank(s) then return false end
            if kind(b, s) == P and edgeRank(a) then return false end
            return kind(b, s) ~= kind(b, a)
        end)
    end,
    apply = function(b, side, a, c)
        b.p[a], b.p[c] = b.p[c], b.p[a]
        b.id[a], b.id[c] = b.id[c], b.id[a]
        return true
    end,
}

local function pullTo(side, s)
    local t = s - 8 * side
    if t < 1 or t > 64 then return nil end
    return t
end

card {
    slug = "magnetic_pull", name = "MAGNETIC PULL", school = "ARCANE", cost = 1,
    desc = "Pull an enemy piece one square toward your side. You still move.",
    prompt1 = "PICK AN ENEMY PIECE TO PULL",
    pick1 = function(b, side)
        return enemyTargets(b, side, function(t, s)
            local to = pullTo(side, s)
            return to ~= nil and b.p[to] == 0 and not (t == P and edgeRank(to))
        end)
    end,
    apply = function(b, side, a)
        local to = pullTo(side, a)
        if not to or b.p[to] ~= 0 then return false end
        movePiece(b, a, to)
        return true
    end,
}

card {
    slug = "reverse_gravity", name = "REVERSE GRAVITY", school = "ARCANE", cost = 2,
    desc = "Every enemy pawn that can steps one square backward. You still move.",
    apply = function(b, side)
        local e = -side
        local moved = 0

        local s0, s1, ds = 1, 64, 1
        if e == -1 then s0, s1, ds = 64, 1, -1 end
        for s = s0, s1, ds do
            if b.p[s] == P * e then
                local to = s - 8 * e
                if to >= 1 and to <= 64 and b.p[to] == 0 and RANK[to] ~= (e == 1 and 0 or 7) then
                    movePiece(b, s, to)
                    moved = moved + 1
                end
            end
        end
        b.ep = 0
        return moved > 0
    end,
}

card {
    slug = "rooks_gambit", name = "ROOK'S GAMBIT", school = "ARCANE", cost = 2, endsTurn = true, tag = "*GAMBIT",
    desc = "Your king and one of your rooks swap places. Ends your turn.",
    prompt1 = "PICK A ROOK",
    pick1 = function(b, side) return ownOf(b, side, R) end,
    apply = function(b, side, a)
        local k = b.king[side]
        if b.p[a] ~= R * side then return false end
        b.p[a], b.p[k] = b.p[k], b.p[a]
        b.id[a], b.id[k] = b.id[k], b.id[a]
        b.king[side] = a
        return true
    end,
}

card {
    slug = "double_strike", name = "DOUBLE STRIKE", school = "ARCANE", cost = 3,
    desc = "Move twice this turn, from move 6 on. The piece that moved first rests, and no bonus move after a check.",
    can = function(st, side) return not st.double[side] and st.match.board.ply >= 10 end,
    apply = function() return true end,
    after = function(layer, side) layer.double[side] = true end,
    aiBonus = 140,
}

card {
    slug = "shield", name = "SHIELD", school = "PROTECTION", cost = 1,
    desc = "One of your pieces cannot be captured for 2 enemy turns. You still move.",
    prompt1 = "PICK A PIECE TO SHIELD",
    pick1 = function(b, side)
        return collect(function(s) return mine(b, side, s) and kind(b, s) ~= K and not b:status(b.id[s], "shield") end)
    end,
    apply = function(b, side, a) b:setStatus(b.id[a], "shield", b.ply + 4); return true end,
}

card {
    slug = "dispel", name = "DISPEL", school = "PROTECTION", cost = 1,
    desc = "Remove enemy shields, berserk, sanctuaries and last stands, and free your frozen pieces.",
    apply = function(b, side)
        local any = false
        local ply = b.ply
        for s = 1, 64 do
            local id = b.id[s]
            local e = id ~= 0 and b.st[id]
            if e then
                if theirs(b, side, s) then
                    if (e.shield and e.shield > ply) or (e.berserk and e.berserk > ply) then any = true end
                    e.shield, e.berserk = nil, nil
                else
                    if e.frozen and e.frozen > ply then any = true end
                    e.frozen = nil
                end
                if not (e.shield or e.frozen or e.berserk) then b.st[id] = nil end
            end
        end
        for i = #b.zones, 1, -1 do
            if b.zones[i].owner == -side then
                if b.zones[i].untilPly > ply then any = true end
                table.remove(b.zones, i)
            end
        end
        if b.lastStand[-side] > ply or b.epAny[-side] > ply or b.fog[side] > ply then any = true end
        b.lastStand[-side], b.epAny[-side], b.fog[side] = 0, 0, 0
        return any
    end,
}

card {
    slug = "sanctuary", name = "SANCTUARY", school = "PROTECTION", cost = 2,
    desc = "Bless a 3x3 area: your pieces inside cannot be captured for 2 enemy turns.",
    prompt1 = "PICK THE CENTRE OF THE SANCTUARY",
    pick1 = function(b, side)
        return collect(function(s)
            for dr = -1, 1 do
                for df = -1, 1 do
                    local f, r = FILE[s] + df, RANK[s] + dr
                    if f >= 0 and f <= 7 and r >= 0 and r <= 7 then
                        local t = sq(f, r)
                        if mine(b, side, t) and kind(b, t) ~= K then return true end
                    end
                end
            end
            return false
        end)
    end,
    apply = function(b, side, a)
        b.zones[#b.zones + 1] = { owner = side, f = FILE[a], r = RANK[a], untilPly = b.ply + 4 }
        return true
    end,
}

card {
    slug = "fog_of_war", name = "FOG OF WAR", school = "PROTECTION", cost = 1,
    desc = "For 2 turns, enemy bishops, rooks and queens move at most 2 squares.",
    apply = function(b, side)
        if b.fog[-side] > b.ply + 2 then return false end
        b.fog[-side] = b.ply + 4
        return true
    end,
}

card {
    slug = "checkmates_grace", name = "CHECKMATE'S GRACE", school = "PROTECTION", cost = 3, endsTurn = true, tag = "*GRACE",
    desc = "Your king leaps to a safe empty square up to 2 squares away. Ends your turn.",
    prompt1 = "PICK A SAFE SQUARE FOR THE KING",
    pick1 = function(b, side)
        local k = b.king[side]
        return collect(function(s) return b.p[s] == 0 and Board.dist(s, k) <= 2 end)
    end,
    apply = function(b, side, a)
        if b.p[a] ~= 0 then return false end
        movePiece(b, b.king[side], a)
        return true
    end,
}

card {
    slug = "counterspell", name = "COUNTERSPELL", school = "PROTECTION", cost = 1,
    desc = "Ward yourself: the next spell your opponent casts within 2 turns fizzles.",
    can = function(st, side) return not (st.ward[side] > st.match.board.ply) end,
    apply = function() return true end,
    after = function(layer, side) layer.ward[side] = layer.match.board.ply + 4 end,
    aiBonus = 70,
}

card {
    slug = "sacrifice", name = "SACRIFICE", school = "BLOOD", cost = 2,
    desc = "Destroy one of your pieces, then an enemy piece of equal or lower value.",
    prompt1 = "PICK A PIECE TO SACRIFICE", prompt2 = "PICK AN ENEMY OF EQUAL OR LOWER VALUE",
    pick1 = ownNonKing,
    pick2 = function(b, side, a)
        local v = VAL[kind(b, a)]
        return enemyTargets(b, side, function(t) return VAL[t] <= v end)
    end,
    apply = function(b, side, a, c)
        if not mine(b, side, a) or not theirs(b, side, c) then return false end
        destroy(b, a)
        destroy(b, c)
        return true
    end,
}

card {
    slug = "resurrection", name = "RESURRECTION", school = "BLOOD", cost = 3,
    desc = "Bring back your most valuable lost piece (not a queen) on your first two ranks.",
    prompt1 = "PICK WHERE IT RETURNS",
    can = function(st, side) return bestLost(st.match.board, side) ~= nil end,
    pick1 = function(b, side)
        local i = bestLost(b, side)
        if not i then return {} end
        local t = b.captured[side][i].t
        local r1, r2 = side == 1 and 0 or 7, side == 1 and 1 or 6
        return collect(function(s)
            if b.p[s] ~= 0 then return false end
            if t == P then return RANK[s] == r2 end
            return RANK[s] == r1 or RANK[s] == r2
        end)
    end,
    apply = function(b, side, a)
        local i = bestLost(b, side)
        if not i or b.p[a] ~= 0 then return false end
        local c = table.remove(b.captured[side], i)
        b.p[a], b.id[a] = c.t * side, c.id
        b.st[c.id] = nil
        return true
    end,
}

card {
    slug = "berserk", name = "BERSERK", school = "BLOOD", cost = 2,
    desc = "A pawn, knight, bishop or rook also moves like a queen until your next turn ends.",
    prompt1 = "PICK A PIECE TO ENRAGE",
    pick1 = function(b, side)
        return collect(function(s)
            local t = kind(b, s)
            return mine(b, side, s) and t ~= K and t ~= Q and not b:status(b.id[s], "berserk")
        end)
    end,
    apply = function(b, side, a) b:setStatus(b.id[a], "berserk", b.ply + 3); return true end,
}

card {
    slug = "blood_pact", name = "BLOOD PACT", school = "BLOOD", cost = 0,
    desc = "Sacrifice one of your pawns: draw 2 cards and gain 1 mana.",
    prompt1 = "PICK A PAWN TO SACRIFICE",
    pick1 = function(b, side) return ownOf(b, side, P) end,
    apply = function(b, side, a)
        if b.p[a] ~= P * side then return false end
        destroy(b, a)
        return true
    end,
    after = function(layer, side)
        layer:drawCards(side, 2)
        layer:gainMana(side, 1)
    end,
    aiBonus = 130,
}

card {
    slug = "rebirth", name = "REBIRTH", school = "BLOOD", cost = 2,
    desc = "One of your pawns is reborn as a knight. You still move.",
    prompt1 = "PICK A PAWN",
    pick1 = function(b, side) return ownOf(b, side, P) end,
    apply = function(b, side, a)
        if b.p[a] ~= P * side then return false end
        b.p[a] = N * side
        return true
    end,
}

card {
    slug = "last_stand", name = "LAST STAND", school = "BLOOD", cost = 2,
    desc = "For 2 enemy turns, your pieces next to your king cannot be captured.",
    can = function(st, side)
        local b = st.match.board
        local k = b.king[side]
        for _, s in ipairs(Board.KING_STEPS[k]) do
            if mine(b, side, s) then return true end
        end
        return false
    end,
    apply = function(b, side)
        b.lastStand[side] = b.ply + 4
        return true
    end,
}

card {
    slug = "time_rewind", name = "TIME REWIND", school = "TIME", cost = 3,
    desc = "The board returns to how it was at the start of your previous turn. You still move.",
    can = function(st, side) return st:snapshotFor(side) ~= nil end,
    apply = function(b, side, a, c, ctx)
        local snap = ctx and ctx.snapshot
        if not snap or snap.side ~= side then return false end
        D.restore(b, snap)
        return true
    end,
}

card {
    slug = "freeze", name = "FREEZE", school = "TIME", cost = 1,
    desc = "An enemy piece cannot move on its next turn.",
    prompt1 = "PICK AN ENEMY PIECE TO FREEZE",
    pick1 = function(b, side)
        return enemyTargets(b, side, function(_, s) return not b:status(b.id[s], "frozen") end)
    end,
    apply = function(b, side, a) b:setStatus(b.id[a], "frozen", b.ply + 2); return true end,
}

card {
    slug = "haste", name = "HASTE", school = "TIME", cost = 1,
    desc = "One of your pawns steps forward one square for free. You still move.",
    prompt1 = "PICK A PAWN TO HASTEN",
    pick1 = function(b, side)
        return collect(function(s)
            if b.p[s] ~= P * side then return false end
            local to = s + 8 * side
            return to >= 1 and to <= 64 and b.p[to] == 0 and not edgeRank(to)
        end)
    end,
    apply = function(b, side, a)
        local to = a + 8 * side
        if b.p[a] ~= P * side or b.p[to] ~= 0 then return false end
        movePiece(b, a, to)
        b.ep = 0
        return true
    end,
}

card {
    slug = "en_passant", name = "EN PASSANT", school = "TIME", cost = 1,
    desc = "This turn and next, your pawns may capture any enemy pawn beside them en passant.",
    apply = function(b, side)
        if b.epAny[side] > b.ply then return false end
        b.epAny[side] = b.ply + 3
        return true
    end,
}

card {
    slug = "temporal_echo", name = "TEMPORAL ECHO", school = "TIME", cost = 1,
    desc = "Add a copy of the last spell you cast to your hand.",
    can = function(st, side)
        local last = st.lastSpell[side]
        return last ~= nil and last.slug ~= "temporal_echo"
    end,
    apply = function() return true end,

    after = function(layer, side) layer:addCard(side, layer.lastSpell[side]) end,
    aiBonus = 45,
}

card {
    slug = "meteor", name = "METEOR", school = "TIME", cost = 3, endsTurn = true, tag = "*METEOR",
    desc = "Destroy an unprotected enemy pawn, knight, bishop or rook. Ends your turn.",
    prompt1 = "PICK AN ENEMY PIECE TO DESTROY",
    pick1 = function(b, side) return enemyTargets(b, side, function(t) return t ~= Q end) end,
    apply = function(b, side, a)
        if not theirs(b, side, a) or kind(b, a) == Q or kind(b, a) == K or b:isProtected(a) then return false end
        destroy(b, a)
        return true
    end,
}

D.list = cards
D.bySlug = {}
D.byName = {}
for i, c in ipairs(cards) do
    D.bySlug[c.slug] = c
    D.byName[c.name] = c
    c.index = i
    c.available = c.apply ~= nil
    c.steps = c.pick2 and 2 or (c.pick1 and 1 or 0)
end

return D
