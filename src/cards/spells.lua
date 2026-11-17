local Board = require("src.chess.board")
local Defs = require("src.cards.defs")

local S = {}

function S.tidy(b)
    b:sanitizeCastling()
    local ep = b.ep
    if ep ~= 0 then
        local pawnSq = ep - 8 * b.side
        if b.p[ep] ~= 0 or pawnSq < 1 or pawnSq > 64 or b.p[pawnSq] ~= -Board.P * b.side then b.ep = 0 end
    end
end

function S.check(board, side, def, a, c, ctx)
    if board.side ~= side then return false end
    local wasCheck = board:inCheck(side)
    local b = board:clone()
    if not def.apply(b, side, a, c, ctx) then return false end
    S.tidy(b)
    if b.king[side] == 0 or b.king[-side] == 0 then return false end

    if b:inCheck(side) and (def.endsTurn or not wasCheck) then return false end
    if def.endsTurn then
        b:passTurn()
        b:removeExpired()
    else
        if b:inCheck(-side) then return false end
        if not b:hasLegalMove() then return false end
    end
    return true, b
end

local function filterSecond(board, side, def, a, ctx, earlyOut)
    local cands = def.pick2(board, side, a, ctx)
    local out = {}
    for _, c in ipairs(cands) do
        if S.check(board, side, def, a, c, ctx) then
            out[#out + 1] = c
            if earlyOut then return out end
        end
    end
    return out
end

function S.secondTargets(board, side, def, a, ctx)
    return filterSecond(board, side, def, a, ctx, false)
end

function S.firstTargets(board, side, def, ctx)
    local out = {}
    if not def.pick1 then return out end
    for _, a in ipairs(def.pick1(board, side, ctx)) do
        if def.pick2 then
            if #filterSecond(board, side, def, a, ctx, true) > 0 then out[#out + 1] = a end
        elseif S.check(board, side, def, a, nil, ctx) then
            out[#out + 1] = a
        end
    end
    return out
end

S.OPENING = 8

function S.castable(board, side, def, state, ctx, skipTargets)
    if not def.available then return false, "NOT AVAILABLE" end
    if board.side ~= side then return false, "NOT YOUR TURN" end
    if board.ply < S.OPENING then return false, "NO SPELLS IN THE OPENING" end
    if state.castThisTurn[side] then return false, "ONE SPELL PER TURN" end
    if state.manaOf[side] < def.cost then return false, "NOT ENOUGH MANA" end
    if def.can and not def.can(state, side) then return false, "NO VALID USE" end
    if skipTargets then return true end
    if def.steps == 0 then
        if not S.check(board, side, def, nil, nil, ctx) then return false, "NO VALID USE" end
    elseif #S.firstTargets(board, side, def, ctx) == 0 then
        return false, "NO VALID TARGET"
    end
    return true
end

S.restore = Defs.restore
return S
