local Config = require("src.config")
local bit = require("src.utils.bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local abs, floor = math.abs, math.floor

local Board = {}
Board.__index = Board

local P, N, B, R, Q, K = 1, 2, 3, 4, 5, 6
Board.P, Board.N, Board.B, Board.R, Board.Q, Board.K = P, N, B, R, Q, K
Board.VALUE = Config.chess.values
Board.VALUE_SCALE = Config.chess.valueScale
Board.LETTER = { "", "N", "B", "R", "Q", "K" }
Board.NAME = { "pawn", "knight", "bishop", "rook", "queen", "king" }

local FILE, RANK = {}, {}
for s = 1, 64 do FILE[s] = (s - 1) % 8; RANK[s] = floor((s - 1) / 8) end
Board.FILE, Board.RANK = FILE, RANK

local function sq(f, r) return r * 8 + f + 1 end
Board.sq = sq

function Board.name(s)
    return string.char(97 + FILE[s]) .. tostring(RANK[s] + 1)
end

function Board.dist(a, b)
    return math.max(abs(FILE[a] - FILE[b]), abs(RANK[a] - RANK[b]))
end

local DIRS = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
local RAYS = {}
for d = 1, 8 do
    RAYS[d] = {}
    for s = 1, 64 do
        local list, f, r = {}, FILE[s], RANK[s]
        while true do
            f, r = f + DIRS[d][1], r + DIRS[d][2]
            if f < 0 or f > 7 or r < 0 or r > 7 then break end
            list[#list + 1] = sq(f, r)
        end
        RAYS[d][s] = list
    end
end
local function steps(deltas)
    local t = {}
    for s = 1, 64 do
        local list = {}
        for _, d in ipairs(deltas) do
            local f, r = FILE[s] + d[1], RANK[s] + d[2]
            if f >= 0 and f <= 7 and r >= 0 and r <= 7 then list[#list + 1] = sq(f, r) end
        end
        t[s] = list
    end
    return t
end
local KNIGHT = steps({ { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } })
local KING = steps(DIRS)
Board.KNIGHT, Board.KING_STEPS, Board.RAYS = KNIGHT, KING, RAYS

local WK, WQ, BK, BQ = 1, 2, 4, 8
local CMASK = {}
for s = 1, 64 do CMASK[s] = 15 end
CMASK[sq(4, 0)] = 12; CMASK[sq(7, 0)] = 14; CMASK[sq(0, 0)] = 13
CMASK[sq(4, 7)] = 3; CMASK[sq(7, 7)] = 11; CMASK[sq(0, 7)] = 7

local function encode(from, to, promo, flag)
    return (from - 1) + lshift(to - 1, 6) + lshift(promo or 0, 12) + lshift(flag or 0, 15)
end
Board.encode = encode
function Board.decode(m)
    return band(m, 63) + 1, band(rshift(m, 6), 63) + 1, band(rshift(m, 12), 7), rshift(m, 15)
end
local decode = Board.decode
function Board.from(m) return band(m, 63) + 1 end
function Board.to(m) return band(rshift(m, 6), 63) + 1 end
function Board.promo(m) return band(rshift(m, 12), 7) end
function Board.flag(m) return rshift(m, 15) end

function Board.empty()
    local b = setmetatable({}, Board)
    b.p, b.id = {}, {}
    for s = 1, 64 do b.p[s] = 0; b.id[s] = 0 end
    b.side = 1
    b.castle = 0
    b.ep = 0
    b.half = 0
    b.ply = 0
    b.king = { [1] = 0, [-1] = 0 }
    b.nextId = 1
    b.st = {}
    b.zones = {}
    b.fog = { [1] = 0, [-1] = 0 }
    b.epAny = { [1] = 0, [-1] = 0 }
    b.lastStand = { [1] = 0, [-1] = 0 }
    b.captured = { [1] = {}, [-1] = {} }
    b.castleIds = {}
    b:_initUndo()
    return b
end

function Board:_initUndo()
    self.un = 0
    self.Um, self.Ucap, self.UcapId, self.UcapSq = {}, {}, {}, {}
    self.Ucastle, self.Uep, self.Uhalf, self.Upiece = {}, {}, {}, {}
end

function Board:put(s, piece)
    self.p[s] = piece
    if piece == 0 then self.id[s] = 0; return 0 end
    local id = self.nextId
    self.nextId = id + 1
    self.id[s] = id
    if abs(piece) == K then self.king[piece > 0 and 1 or -1] = s end
    return id
end

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
Board.START_FEN = START
local FEN_PIECE = { p = P, n = N, b = B, r = R, q = Q, k = K }

function Board.fromFEN(fen)
    local b = Board.empty()
    local parts = {}
    for w in fen:gmatch("%S+") do parts[#parts + 1] = w end
    local r, f = 7, 0
    for c in parts[1]:gmatch(".") do
        if c == "/" then r, f = r - 1, 0
        elseif c:match("%d") then f = f + tonumber(c)
        else
            local t = FEN_PIECE[c:lower()]
            b:put(sq(f, r), c:match("%u") and t or -t)
            f = f + 1
        end
    end
    b.side = (parts[2] == "b") and -1 or 1
    local c = parts[3] or "-"
    b.castle = 0
    if c:find("K") then b.castle = b.castle + WK end
    if c:find("Q") then b.castle = b.castle + WQ end
    if c:find("k") then b.castle = b.castle + BK end
    if c:find("q") then b.castle = b.castle + BQ end
    if parts[4] and parts[4] ~= "-" then
        b.ep = sq(parts[4]:byte(1) - 97, tonumber(parts[4]:sub(2)) - 1)
    end
    b.half = tonumber(parts[5] or "0") or 0
    b.ply = math.max(0, ((tonumber(parts[6] or "1") or 1) - 1) * 2) + (b.side == -1 and 1 or 0)
    for _, s in ipairs({ sq(4, 0), sq(7, 0), sq(0, 0), sq(4, 7), sq(7, 7), sq(0, 7) }) do
        b.castleIds[s] = b.id[s]
    end
    return b
end

function Board.new() return Board.fromFEN(START) end

function Board:clone()
    local b = setmetatable({}, Board)
    local p, id, sp, sid = {}, {}, self.p, self.id
    for s = 1, 64 do p[s] = sp[s]; id[s] = sid[s] end
    b.p, b.id = p, id
    b.side, b.castle, b.ep, b.half, b.ply, b.nextId = self.side, self.castle, self.ep, self.half, self.ply, self.nextId
    b.king = { [1] = self.king[1], [-1] = self.king[-1] }
    b.st = {}
    for k, v in pairs(self.st) do
        b.st[k] = { shield = v.shield, frozen = v.frozen, berserk = v.berserk, pawned = v.pawned }
    end
    b.zones = {}
    for i, z in ipairs(self.zones) do b.zones[i] = { owner = z.owner, f = z.f, r = z.r, untilPly = z.untilPly } end
    b.fog = { [1] = self.fog[1], [-1] = self.fog[-1] }
    b.epAny = { [1] = self.epAny[1], [-1] = self.epAny[-1] }
    b.lastStand = { [1] = self.lastStand[1], [-1] = self.lastStand[-1] }
    b.captured = { [1] = {}, [-1] = {} }
    for _, sd in ipairs({ 1, -1 }) do
        for i, c in ipairs(self.captured[sd]) do b.captured[sd][i] = { t = c.t, id = c.id, pawned = c.pawned } end
    end
    b.castleIds = {}
    for k, v in pairs(self.castleIds) do b.castleIds[k] = v end
    b:_initUndo()
    return b
end

function Board:status(id, key)
    local st = self.st[id]
    return st ~= nil and st[key] ~= nil and st[key] > self.ply
end

function Board:setStatus(id, key, untilPly)
    local st = self.st[id]
    if not st then st = {}; self.st[id] = st end
    st[key] = untilPly
end

function Board:isProtected(s)
    local pc = self.p[s]
    if pc == 0 then return false end

    local ply = self.ply
    local st = self.st[self.id[s]]
    if st and st.shield and st.shield > ply then return true end

    local side = pc > 0 and 1 or -1
    local zones = self.zones
    for i = 1, #zones do
        local z = zones[i]
        if z.owner == side and z.untilPly > ply and abs(FILE[s] - z.f) <= 1 and abs(RANK[s] - z.r) <= 1 then
            return true
        end
    end
    if self.lastStand[side] > ply and abs(pc) ~= K then
        local k = self.king[side]
        if abs(FILE[s] - FILE[k]) <= 1 and abs(RANK[s] - RANK[k]) <= 1 then return true end
    end
    return false
end

function Board:isAttacked(s, by)
    local p, st, ply, id = self.p, self.st, self.ply, self.id
    local function pawnedAt(src)
        local q = p[src]
        if q == 0 or (q > 0) ~= (by > 0) then return false end
        local e = st[id[src]]
        return e ~= nil and e.pawned ~= nil and e.pawned > ply
    end

    local f = FILE[s]
    local pr = RANK[s] - by
    if pr >= 0 and pr <= 7 then
        if f > 0 then
            local src = sq(f - 1, pr)
            if p[src] == by or pawnedAt(src) then return true end
        end
        if f < 7 then
            local src = sq(f + 1, pr)
            if p[src] == by or pawnedAt(src) then return true end
        end
    end
    local kn = KNIGHT[s]
    for i = 1, #kn do
        local src = kn[i]
        if p[src] == N * by and not pawnedAt(src) then return true end
    end
    local kg = KING[s]
    for i = 1, #kg do
        local src = kg[i]
        if p[src] == K * by and not pawnedAt(src) then return true end
    end
    local limit = (self.fog[by] > ply) and 2 or 8
    for d = 1, 8 do
        local ray = RAYS[d][s]
        local lim = #ray
        if lim > limit then lim = limit end
        local rook, queen = R * by, Q * by
        if d > 4 then rook = B * by end
        for i = 1, lim do
            local src = ray[i]
            local q = p[src]
            if q ~= 0 then
                local e = st[id[src]]
                local pawned = e ~= nil and e.pawned ~= nil and e.pawned > ply
                if not pawned and (q == rook or q == queen) then return true end
                if not pawned and q * by > 0 and q ~= K * by
                    and e and e.berserk and e.berserk > ply then return true end
                break
            end
        end
    end

    return false
end

function Board:inCheck(side)
    side = side or self.side
    local k = self.king[side]
    return k ~= 0 and self:isAttacked(k, -side)
end

local function addPawnMove(list, n, from, to, side, flag)
    local r = RANK[to]
    if r == 7 or r == 0 then
        for promo = Q, N, -1 do
            n = n + 1; list[n] = encode(from, to, promo, 0)
        end
    else
        n = n + 1; list[n] = encode(from, to, 0, flag or 0)
    end
    return n
end

function Board:gen(list, capsOnly)
    local n = 0
    local p, id, st = self.p, self.id, self.st
    local side, ply = self.side, self.ply
    local maxRange = (self.fog[side] > ply) and 2 or 8
    local epAny = self.epAny[side] > ply
    for s = 1, 64 do
        local pc = p[s]
        if pc ~= 0 and (pc > 0) == (side > 0) then
            local e = st[id[s]]
            local pawned = e ~= nil and e.pawned ~= nil and e.pawned > ply
            local t = pc * side
            if pawned then t = P end
            if not (e and e.frozen and e.frozen > ply) then
                local first = n + 1
                if t == P then
                    local fwd = s + 8 * side
                    local r = RANK[s]
                    if fwd >= 1 and fwd <= 64 then
                        if p[fwd] == 0 and not capsOnly
                            and not (pawned and (RANK[fwd] == 7 or RANK[fwd] == 0)) then
                            n = addPawnMove(list, n, s, fwd, side)
                            local startRank = side == 1 and 1 or 6
                            local dbl = fwd + 8 * side
                            if not pawned and r == startRank and p[dbl] == 0 then
                                n = n + 1; list[n] = encode(s, dbl, 0, 1)
                            end
                        end
                        local f = FILE[s]
                        for df = -1, 1, 2 do
                            local tf = f + df
                            if tf >= 0 and tf <= 7 then
                                local to = fwd + df
                                local q = p[to]
                                if q * side < 0 and not self:isProtected(to)
                                    and not (pawned and (RANK[to] == 7 or RANK[to] == 0)) then
                                    n = addPawnMove(list, n, s, to, side)
                                elseif q == 0 then
                                    local victim = s + df
                                    if to == self.ep or (epAny and p[victim] == -P * side) then
                                        if p[victim] == -P * side and not self:isProtected(victim) then
                                            n = n + 1; list[n] = encode(s, to, 0, 2)
                                        end
                                    end
                                end
                            end
                        end
                    end
                elseif t == N then
                    local kn = KNIGHT[s]
                    for i = 1, #kn do
                        local to = kn[i]
                        local q = p[to]
                        if q == 0 then
                            if not capsOnly then n = n + 1; list[n] = encode(s, to, 0, 0) end
                        elseif q * side < 0 and not self:isProtected(to) then
                            n = n + 1; list[n] = encode(s, to, 0, 0)
                        end
                    end
                elseif t == K then
                    local kg = KING[s]
                    for i = 1, #kg do
                        local to = kg[i]
                        local q = p[to]
                        if q == 0 then
                            if not capsOnly then n = n + 1; list[n] = encode(s, to, 0, 0) end
                        elseif q * side < 0 and not self:isProtected(to) then
                            n = n + 1; list[n] = encode(s, to, 0, 0)
                        end
                    end
                    if not capsOnly then n = self:_genCastles(list, n, s) end
                else
                    local d0, d1 = 1, 8
                    if t == B then d0 = 5 elseif t == R then d1 = 4 end
                    n = self:_genRays(list, n, s, d0, d1, maxRange, capsOnly, false)
                end
                if e and e.berserk and e.berserk > ply and not pawned and t ~= K and t ~= Q then
                    n = self:_genRays(list, n, s, 1, 8, maxRange, capsOnly, t == P, first)
                end
            end
        end
    end
    return n
end

function Board:_genRays(list, n, s, d0, d1, maxRange, capsOnly, pawn, dedupeFrom)
    local p, side = self.p, self.side
    local ownBack = side == 1 and 0 or 7
    for d = d0, d1 do
        local ray = RAYS[d][s]
        local lim = #ray
        if lim > maxRange then lim = maxRange end
        for i = 1, lim do
            local to = ray[i]
            local q = p[to]
            if q * side > 0 then break end
            local ok = q == 0 and not capsOnly or q ~= 0 and not self:isProtected(to)
            if ok and pawn and RANK[to] == ownBack then ok = false end
            if ok and dedupeFrom then
                for j = dedupeFrom, n do
                    if band(rshift(list[j], 6), 63) + 1 == to and band(list[j], 63) + 1 == s then ok = false; break end
                end
            end
            if ok then
                if pawn then n = addPawnMove(list, n, s, to, side)
                else n = n + 1; list[n] = encode(s, to, 0, 0) end
            end
            if q ~= 0 then break end
        end
    end
    return n
end

function Board:_genCastles(list, n, s)
    local p, side, c = self.p, self.side, self.castle
    local home = side == 1 and 0 or 7
    if s ~= sq(4, home) then return n end
    local kRight, qRight = side == 1 and WK or BK, side == 1 and WQ or BQ
    local enemy = -side
    if band(c, kRight) ~= 0
        and p[sq(7, home)] == R * side and p[sq(5, home)] == 0 and p[sq(6, home)] == 0
        and not self:status(self.id[sq(7, home)], "frozen")
        and not self:status(self.id[sq(7, home)], "pawned")
        and not self:isAttacked(s, enemy) and not self:isAttacked(sq(5, home), enemy)
        and not self:isAttacked(sq(6, home), enemy) then
        n = n + 1; list[n] = encode(s, sq(6, home), 0, 3)
    end
    if band(c, qRight) ~= 0
        and p[sq(0, home)] == R * side and p[sq(1, home)] == 0
        and p[sq(2, home)] == 0 and p[sq(3, home)] == 0
        and not self:status(self.id[sq(0, home)], "frozen")
        and not self:status(self.id[sq(0, home)], "pawned")
        and not self:isAttacked(s, enemy) and not self:isAttacked(sq(3, home), enemy)
        and not self:isAttacked(sq(2, home), enemy) then
        n = n + 1; list[n] = encode(s, sq(2, home), 0, 4)
    end
    return n
end

function Board:make(m)
    local from, to, promo, flag = decode(m)
    local p, id = self.p, self.id
    local side = self.side
    local u = self.un + 1
    self.un = u
    local capSq = to
    if flag == 2 then capSq = to - 8 * side end
    self.Um[u], self.Ucap[u], self.UcapId[u], self.UcapSq[u] = m, p[capSq], id[capSq], capSq
    self.Ucastle[u], self.Uep[u], self.Uhalf[u], self.Upiece[u] = self.castle, self.ep, self.half, p[from]
    local pc = p[from]
    local captured = p[capSq]
    local pawnMove = pc == P * side or self:status(id[from], "pawned")
    p[capSq] = 0; id[capSq] = 0
    p[to] = promo > 0 and promo * side or pc
    id[to] = id[from]
    p[from] = 0; id[from] = 0
    if pc == K * side then
        self.king[side] = to
        if flag == 3 then
            local rf, rt = to + 1, to - 1
            p[rt], id[rt], p[rf], id[rf] = p[rf], id[rf], 0, 0
        elseif flag == 4 then
            local rf, rt = to - 2, to + 1
            p[rt], id[rt], p[rf], id[rf] = p[rf], id[rf], 0, 0
        end
    end
    self.ep = (flag == 1) and (from + 8 * side) or 0
    self.castle = band(self.castle, CMASK[from], CMASK[to])
    if pawnMove or captured ~= 0 then self.half = 0 else self.half = self.half + 1 end
    self.side = -side
    self.ply = self.ply + 1
    return captured
end

function Board:unmake()
    local u = self.un
    self.un = u - 1
    local m = self.Um[u]
    local from, to, _, flag = decode(m)
    local p, id = self.p, self.id
    self.ply = self.ply - 1
    local side = -self.side
    self.side = side
    local pc = self.Upiece[u]
    id[from] = id[to]
    p[from] = pc
    p[to] = 0; id[to] = 0
    local capSq = self.UcapSq[u]
    p[capSq] = self.Ucap[u]; id[capSq] = self.UcapId[u]
    if pc == K * side then
        self.king[side] = from
        if flag == 3 then
            local rf, rt = to + 1, to - 1
            p[rf], id[rf], p[rt], id[rt] = p[rt], id[rt], 0, 0
        elseif flag == 4 then
            local rf, rt = to - 2, to + 1
            p[rf], id[rf], p[rt], id[rt] = p[rt], id[rt], 0, 0
        end
    end
    self.castle, self.ep, self.half = self.Ucastle[u], self.Uep[u], self.Uhalf[u]
end

function Board:passTurn()
    self.side = -self.side
    self.ply = self.ply + 1
    self.ep = 0
end

function Board:legalMoves(out)
    out = out or {}
    local buf = {}
    local n = self:gen(buf, false)
    local side = self.side
    local c = 0
    for i = 1, n do
        local m = buf[i]
        self:make(m)
        if not self:inCheck(side) then c = c + 1; out[c] = m end
        self:unmake()
    end
    for i = c + 1, #out do out[i] = nil end
    return out, c
end

function Board:hasLegalMove()
    local buf = {}
    local n = self:gen(buf, false)
    local side = self.side
    for i = 1, n do
        self:make(buf[i])
        local ok = not self:inCheck(side)
        self:unmake()
        if ok then return true end
    end
    return false
end

function Board:play(m)
    local side = self.side
    local u = self.un + 1
    local capSq = Board.flag(m) == 2 and Board.to(m) - 8 * side or Board.to(m)
    local priorCapId = self.id[capSq]
    local wasPawned = priorCapId ~= 0 and self:status(priorCapId, "pawned")
    local captured = self:make(m)
    local capId = self.UcapId[u]
    if captured ~= 0 then
        self.st[capId] = nil
        local list = self.captured[-side]
        list[#list + 1] = { t = abs(captured), id = capId, pawned = wasPawned }
    end
    self:_initUndo()
    return captured, capId
end

function Board:sanitizeCastling()
    local function keep(bitv, ks, rs)
        if band(self.castle, bitv) == 0 then return end
        if self.id[ks] ~= self.castleIds[ks] or self.id[rs] ~= self.castleIds[rs]
            or abs(self.p[ks]) ~= K or abs(self.p[rs]) ~= R then
            self.castle = band(self.castle, 15 - bitv)
        end
    end
    keep(WK, sq(4, 0), sq(7, 0)); keep(WQ, sq(4, 0), sq(0, 0))
    keep(BK, sq(4, 7), sq(7, 7)); keep(BQ, sq(4, 7), sq(0, 7))
end

function Board:findId(id)
    local ids = self.id
    for s = 1, 64 do if ids[s] == id then return s end end
    return nil
end

function Board:removeExpired()
    local ply = self.ply
    for k, e in pairs(self.st) do
        if e.shield and e.shield <= ply then e.shield = nil end
        if e.frozen and e.frozen <= ply then e.frozen = nil end
        if e.berserk and e.berserk <= ply then e.berserk = nil end
        if e.pawned and e.pawned <= ply then e.pawned = nil end
        if not (e.shield or e.frozen or e.berserk or e.pawned) then self.st[k] = nil end
    end
    for i = #self.zones, 1, -1 do
        if self.zones[i].untilPly <= ply then table.remove(self.zones, i) end
    end
end

local function pawnedAt(b, s)
    local pc = b.p[s]
    if pc == 0 then return false end
    local e = b.st[b.id[s]]
    return e ~= nil and e.pawned ~= nil and e.pawned > b.ply
end

local function pawnLike(b, s, side)
    local pc = b.p[s]
    if pc == 0 or pc * side < 0 then return false end
    return abs(pc) == P or pawnedAt(b, s)
end

local function epKey(b)
    local ep = b.ep
    if ep == 0 or b.p[ep] ~= 0 then return 0 end
    local side = b.side
    local victim = ep - 8 * side
    if victim < 1 or victim > 64 then return 0 end
    if b.p[victim] ~= -P * side then return 0 end
    local f = FILE[victim]
    for _, df in ipairs({ -1, 1 }) do
        local tf = f + df
        if tf >= 0 and tf <= 7 then
            local s = victim + df
            if pawnLike(b, s, side) and not b:status(b.id[s], "frozen") and not b:isProtected(victim) then
                local test = b:clone()
                test:make(encode(s, ep, 0, 2))
                if not test:inCheck(side) then return ep end
            end
        end
    end
    return 0
end

local function statusPart(b, s)
    local id = b.id[s]
    local e = id ~= 0 and b.st[id]
    if not e then return "" end
    local ply, parts = b.ply, {}
    if e.shield and e.shield > ply then parts[#parts + 1] = "S" .. e.shield end
    if e.frozen and e.frozen > ply then parts[#parts + 1] = "F" .. e.frozen end
    if e.berserk and e.berserk > ply then parts[#parts + 1] = "B" .. e.berserk end
    if e.pawned and e.pawned > ply then parts[#parts + 1] = "P" .. e.pawned end
    return table.concat(parts, ",")
end

local function activeUntil(v, ply)
    return v and v > ply and tostring(v) or "0"
end

function Board:key()
    local t = {}
    for s = 1, 64 do
        local st = statusPart(self, s)
        t[s] = string.char(self.p[s] + 72) .. (st ~= "" and ("(" .. st .. ")") or "")
    end
    t[65] = self.side == 1 and "w" or "b"
    t[66] = string.char(65 + self.castle)
    t[67] = tostring(epKey(self))
    local zones = {}
    for _, z in ipairs(self.zones) do
        if z.untilPly > self.ply then
            zones[#zones + 1] = string.format("%d:%d:%d:%d", z.owner, z.f, z.r, z.untilPly)
        end
    end
    table.sort(zones)
    t[68] = table.concat(zones, ";")
    t[69] = table.concat({
        activeUntil(self.fog[1], self.ply), activeUntil(self.fog[-1], self.ply),
        activeUntil(self.epAny[1], self.ply), activeUntil(self.epAny[-1], self.ply),
        activeUntil(self.lastStand[1], self.ply), activeUntil(self.lastStand[-1], self.ply),
    }, ",")
    local caps = {}
    for _, side in ipairs({ 1, -1 }) do
        local list = {}
        for _, c in ipairs(self.captured[side]) do
            list[#list + 1] = string.char(64 + c.t) .. (c.pawned and "p" or "")
        end
        table.sort(list)
        caps[#caps + 1] = (side == 1 and "W" or "B") .. table.concat(list, ",")
    end
    t[70] = table.concat(caps, "|")
    return table.concat(t)
end

function Board:insufficientMaterial()
    local minors, others = 0, 0
    local knight, bishopColor = false, nil
    local sameBishopColor = true
    for s = 1, 64 do
        local t = abs(self.p[s])
        if t == N then
            minors, knight = minors + 1, true
        elseif t == B then
            minors = minors + 1
            local color = (FILE[s] + RANK[s]) % 2
            if bishopColor == nil then bishopColor = color
            elseif bishopColor ~= color then sameBishopColor = false end
        elseif t ~= 0 and t ~= K then
            others = others + 1
        end
    end
    if others > 0 then return false end
    if minors <= 1 then return true end
    return not knight and sameBishopColor
end

function Board:san(m, legal)
    local from, to, promo, flag = decode(m)
    if flag == 3 then return "O-O" end
    if flag == 4 then return "O-O-O" end
    local pc = self.p[from]
    local t = abs(pc)
    if self:status(self.id[from], "pawned") then t = P end
    local capture = self.p[to] ~= 0 or flag == 2
    local s = ""
    if t == P then
        if capture then s = string.char(97 + FILE[from]) end
    else
        s = Board.LETTER[t]
        local sameFile, sameRank, other = false, false, false
        for _, o in ipairs(legal or {}) do
            local of, ot = decode(o)
            if ot == to and of ~= from and self.p[of] == pc then
                other = true
                if FILE[of] == FILE[from] then sameFile = true end
                if RANK[of] == RANK[from] then sameRank = true end
            end
        end
        if other then
            if not sameFile then s = s .. string.char(97 + FILE[from])
            elseif not sameRank then s = s .. tostring(RANK[from] + 1)
            else s = s .. Board.name(from) end
        end
    end
    if capture then s = s .. "x" end
    s = s .. Board.name(to)
    if promo > 0 then s = s .. "=" .. Board.LETTER[promo] end
    return s
end

return Board
