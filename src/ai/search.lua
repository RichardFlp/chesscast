local Board = require("src.chess.board")
local Eval = require("src.ai.eval")
local bit = require("src.utils.bit")
local band, rshift = bit.band, bit.rshift

local Search = {}
Search.MATE = 100000
local MATE, INF = 100000, 1000000
local MAXPLY = 64
local VALUE = Board.VALUE
local abs = math.abs
local random = (love and love.math and love.math.random) or math.random
local evaluate = Eval.evaluate

local now = (love and love.timer and love.timer.getTime) or os.clock

Search.LEVELS = {
    { name = "EASY", depth = 1, qs = false, time = 0.3, noise = 220, blunder = 0.35, cast = 0.25, spellNoise = 300, spellDepth = 0 },
    { name = "MEDIUM", depth = 2, qs = false, time = 0.6, noise = 90, blunder = 0.12, cast = 0.5, spellNoise = 120, spellDepth = 0 },
    { name = "HARD", depth = 3, qs = true, time = 1.2, noise = 25, blunder = 0.04, cast = 0.8, spellNoise = 40, spellDepth = 1 },
}

function Search.level(l)
    if type(l) == "table" then return l end
    return Search.LEVELS[l] or Search.LEVELS[2]
end

local Job = {}
Job.__index = Job

local function newState(board, level)
    local S = setmetatable({
        b = board, level = level, nodes = 0, stop = false,
        lists = {}, scores = {}, killers1 = {}, killers2 = {}, history = {},
        frameEnd = math.huge, deadline = math.huge, coroutine = false,
    }, Job)
    for i = 0, MAXPLY + 1 do
        S.lists[i], S.scores[i] = {}, {}
        S.killers1[i], S.killers2[i] = 0, 0
    end
    for i = 1, 4096 do S.history[i] = 0 end
    return S
end

local function checkTime(S)
    local t = now()
    if t >= S.deadline then S.stop = true; return end
    if S.coroutine and t >= S.frameEnd then coroutine.yield() end
end

local function scoreMoves(S, b, list, scores, n, ply)
    local p = b.p
    local k1, k2, hist = S.killers1[ply], S.killers2[ply], S.history
    for i = 1, n do
        local m = list[i]
        local sc
        local from, to = band(m, 63) + 1, band(rshift(m, 6), 63) + 1
        local victim = p[to]
        local flag = rshift(m, 15)
        local promo = band(rshift(m, 12), 7)
        if victim ~= 0 or flag == 2 then
            local vt = victim ~= 0 and abs(victim) or 1
            sc = 1000000 + VALUE[vt] * 10 - (VALUE[abs(p[from])] or 0) / 10
        elseif promo > 0 then
            sc = 900000 + VALUE[promo]
        elseif m == k1 then
            sc = 800000
        elseif m == k2 then
            sc = 799000
        else
            sc = hist[band(m, 4095) + 1]
        end
        scores[i] = sc
    end
end

local function pick(list, scores, i, n)
    local best, bi = scores[i], i
    for j = i + 1, n do
        if scores[j] > best then best, bi = scores[j], j end
    end
    if bi ~= i then
        list[i], list[bi] = list[bi], list[i]
        scores[i], scores[bi] = scores[bi], scores[i]
    end
    return list[i]
end

local function quiesce(S, b, alpha, beta, ply)
    S.nodes = S.nodes + 1
    if band(S.nodes, 1023) == 0 then checkTime(S) end
    if S.stop then return 0 end
    local stand = evaluate(b) * b.side
    if stand >= beta then return stand end
    if stand > alpha then alpha = stand end
    if ply >= MAXPLY then return stand end
    local list, scores = S.lists[ply], S.scores[ply]
    local n = b:gen(list, true)
    scoreMoves(S, b, list, scores, n, ply)
    local p = b.p
    for i = 1, n do
        local m = pick(list, scores, i, n)
        local victim = p[band(rshift(m, 6), 63) + 1]

        local gain = victim ~= 0 and VALUE[abs(victim)] or 100
        if band(rshift(m, 12), 7) > 0 then gain = gain + 800 end
        if stand + gain + 200 >= alpha then
            local mover = b.side
            b:make(m)
            if not b:inCheck(mover) then
                local sc = -quiesce(S, b, -beta, -alpha, ply + 1)
                b:unmake()
                if S.stop then return 0 end
                if sc >= beta then return sc end
                if sc > alpha then alpha = sc end
            else
                b:unmake()
            end
        end
    end
    return alpha
end

local function negamax(S, b, depth, alpha, beta, ply)
    S.nodes = S.nodes + 1
    if band(S.nodes, 1023) == 0 then checkTime(S) end
    if S.stop then return 0 end
    if b.half >= 100 then return 0 end
    local side = b.side
    local inCheck = b:inCheck(side)
    if inCheck and ply < MAXPLY - 8 then depth = depth + 1 end
    if depth <= 0 then
        if S.level.qs == false then return evaluate(b) * side end
        return quiesce(S, b, alpha, beta, ply)
    end

    if alpha < -MATE + ply then alpha = -MATE + ply end
    if beta > MATE - ply then beta = MATE - ply end
    if alpha >= beta then return alpha end

    local list, scores = S.lists[ply], S.scores[ply]
    local n = b:gen(list, false)
    scoreMoves(S, b, list, scores, n, ply)
    local legal, best = 0, -INF
    local p = b.p
    for i = 1, n do
        local m = pick(list, scores, i, n)
        local quiet = p[band(rshift(m, 6), 63) + 1] == 0 and rshift(m, 15) ~= 2 and band(rshift(m, 12), 7) == 0
        b:make(m)
        if b:inCheck(side) then
            b:unmake()
        else
            legal = legal + 1
            local sc = -negamax(S, b, depth - 1, -beta, -alpha, ply + 1)
            b:unmake()
            if S.stop then return 0 end
            if sc > best then best = sc end
            if sc > alpha then
                alpha = sc
                if alpha >= beta then
                    if quiet then
                        if S.killers1[ply] ~= m then
                            S.killers2[ply] = S.killers1[ply]
                            S.killers1[ply] = m
                        end
                        local h = band(m, 4095) + 1
                        S.history[h] = S.history[h] + depth * depth
                    end
                    break
                end
            end
        end
    end
    if legal == 0 then
        return inCheck and (-MATE + ply) or 0
    end
    return best
end

local function searchRoot(S, depth, rootMoves, rootScores)
    local b = S.b
    local alpha = -INF
    local bestScore, bestMove = -INF, nil
    local exact = (S.level.noise or 0) > 0
    for i = 1, #rootMoves do
        local m = rootMoves[i]
        b:make(m)
        local sc
        if exact or i == 1 then
            sc = -negamax(S, b, depth - 1, -INF, INF, 1)
        else
            sc = -negamax(S, b, depth - 1, -alpha - 1, -alpha, 1)
            if not S.stop and sc > alpha then
                sc = -negamax(S, b, depth - 1, -INF, -alpha, 1)
            end
        end
        b:unmake()
        if S.stop then return nil end
        rootScores[i] = sc
        if sc > bestScore then bestScore, bestMove = sc, m end
        if sc > alpha then alpha = sc end
    end
    return bestMove, bestScore
end

function Job:run()
    local b, L = self.b, self.level
    local rootMoves, n = b:legalMoves({})
    self.legalCount = n
    if n == 0 then self.done = true; return end

    for i = n, 2, -1 do
        local j = random(i)
        rootMoves[i], rootMoves[j] = rootMoves[j], rootMoves[i]
    end
    self.move, self.score, self.depth = rootMoves[1], 0, 0
    local rootScores = {}
    local lastScores
    for depth = 1, L.depth do
        local m, sc = searchRoot(self, depth, rootMoves, rootScores)
        if not m then break end
        self.move, self.score, self.depth = m, sc, depth

        local order = {}
        for i = 1, n do order[i] = i end
        table.sort(order, function(x, y) return rootScores[x] > rootScores[y] end)
        local nm, ns = {}, {}
        for i = 1, n do nm[i] = rootMoves[order[i]]; ns[i] = rootScores[order[i]] end
        rootMoves, rootScores = nm, ns
        lastScores = ns
        rootScores = {}
        if abs(sc) > MATE - 100 then break end
    end

    if (L.noise or 0) > 0 and lastScores then
        local best, bm = -INF, self.move
        for i = 1, n do
            local sc = lastScores[i]
            if abs(sc) < MATE - 100 then sc = sc + (random() * 2 - 1) * L.noise end
            if sc > best then best, bm = sc, rootMoves[i] end
        end
        self.move = bm
        if L.blunder > 0 and random() < L.blunder and n > 1 then
            local k = random(n)
            if lastScores[k] > -MATE + 100 then self.move = rootMoves[k] end
        end
    end
    self.done = true
end

function Search.start(board, level)
    local S = newState(board:clone(), Search.level(level))
    S.startTime = now()
    S.deadline = S.startTime + S.level.time
    S.coroutine = true
    S.co = coroutine.create(function() S:run() end)
    return S
end

function Job:step(budget)
    if self.done then return true end
    self.frameEnd = now() + (budget or 0.008)
    local ok, err = coroutine.resume(self.co)
    if not ok then
        print("AI error: " .. tostring(err))
        self.done = true
    end
    return self.done
end

function Search.best(board, level, timeLimit)
    local S = newState(board:clone(), Search.level(level))
    S.deadline = now() + (timeLimit or S.level.time)
    S:run()
    return S.move, S.score, S.depth, S.nodes
end

function Search.score(board, depth, timeLimit, yielding, qs)
    local S = newState(board, { depth = depth, noise = 0, blunder = 0, qs = qs })
    S.deadline = now() + (timeLimit or 1)
    if yielding then S.coroutine, S.frameEnd = true, -1 end
    local sc = negamax(S, board, depth, -INF, INF, 0)
    return sc, S.nodes, S.stop
end

return Search
