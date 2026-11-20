local Board = require("src.chess.board")

local Eval = {}
local P = Board.P
local abs = math.abs

local RAW = {
    {
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0 },
    {
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50 },
    {
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20 },
    {
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0 },
    {
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20 },
    {
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20 },
}
local KING_END = {
    -50, -40, -30, -20, -20, -30, -40, -50,
    -30, -20, -10, 0, 0, -10, -20, -30,
    -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -30, 0, 0, 0, 0, -30, -30,
    -50, -30, -30, -30, -30, -30, -30, -50 }

local PST = { [1] = {}, [-1] = {} }
local KEND = { [1] = {}, [-1] = {} }
for t = 1, 6 do
    PST[1][t], PST[-1][t] = {}, {}
    for s = 1, 64 do
        local f, r = Board.FILE[s], Board.RANK[s]
        local wi = (7 - r) * 8 + f + 1
        local bi = r * 8 + f + 1
        PST[1][t][s] = Board.VALUE[t] + RAW[t][wi]
        PST[-1][t][s] = Board.VALUE[t] + RAW[t][bi]
        if t == 6 then
            KEND[1][s] = KING_END[wi]
            KEND[-1][s] = KING_END[bi]
        end
    end
end
Eval.PST = PST

local PHASE = { 0, 1, 1, 2, 4, 0 }

function Eval.evaluate(b)
    local p, ids, st, ply = b.p, b.id, b.st, b.ply
    local score, phase = 0, 0
    local bishops1, bishops2 = 0, 0
    for s = 1, 64 do
        local pc = p[s]
        if pc ~= 0 then
            local e = st[ids[s]]
            local pawned = e ~= nil and e.pawned ~= nil and e.pawned > ply
            local t = abs(pc)
            local et = (pawned and t ~= 6) and P or t
            if pc > 0 then
                if et ~= 6 then score = score + PST[1][et][s] end
                phase = phase + PHASE[et]
                if et == 3 then bishops1 = bishops1 + 1 end
            else
                if et ~= 6 then score = score - PST[-1][et][s] end
                phase = phase + PHASE[et]
                if et == 3 then bishops2 = bishops2 + 1 end
            end
            if e then
                local v = 0
                if e.shield and e.shield > ply then v = v + 25 end
                if e.berserk and e.berserk > ply and not pawned then v = v + 60 end
                if e.frozen and e.frozen > ply then v = v - 30 end
                if pc > 0 then score = score + v else score = score - v end
            end
        end
    end
    if bishops1 >= 2 then score = score + 30 end
    if bishops2 >= 2 then score = score - 30 end

    if phase > 24 then phase = 24 end
    local wk, bk = b.king[1], b.king[-1]
    if wk > 0 then
        score = score + (PST[1][6][wk] * phase + KEND[1][wk] * (24 - phase)) / 24
    end
    if bk > 0 then
        score = score - (PST[-1][6][bk] * phase + KEND[-1][bk] * (24 - phase)) / 24
    end
    return score
end

return Eval
