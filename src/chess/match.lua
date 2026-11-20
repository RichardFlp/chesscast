local Board = require("src.chess.board")
local Config = require("src.config")

local Match = {}
Match.__index = Match

local VALUE = {}
for i = Board.P, Board.K do
    VALUE[i] = math.floor(Board.VALUE[i] / Board.VALUE_SCALE + 0.5)
end

function Match.new(opts)
    local m = setmetatable({}, Match)
    m.opts = opts
    m.board = opts.fen and Board.fromFEN(opts.fen) or Board.new()
    m.mode = opts.mode or "cpu"
    m.human = opts.human or 1
    m.spells = opts.spells ~= false
    m.players = {}
    for _, side in ipairs({ 1, -1 }) do
        local cpu = m.mode == "cpu" and side ~= m.human
        local remote = m.mode == "online" and side ~= m.human
        local name = side == 1 and "WHITE" or "BLACK"
        if cpu then name = "CPU" elseif remote then name = "RIVAL"
        elseif m.mode ~= "local" then name = "YOU" end
        if opts.names and opts.names[side] then name = opts.names[side] end
        m.players[side] = { side = side, cpu = cpu, remote = remote, name = name }
    end
    m.timed = (opts.clock or 0) > 0
    m.clock = { [1] = opts.clock or 0, [-1] = opts.clock or 0 }
    m.history = {}
    m.reps = {}
    m.result = nil
    m.lastMove = nil
    m.legal = {}
    m.legalN = 0
    m.lastKey = nil
    m:recordPosition()
    m:refresh()
    m:checkResult()
    return m
end

function Match:isCPU(side) return self.players[side].cpu end
function Match:isRemote(side) return self.players[side].remote end

function Match:isLocal(side) return not (self.players[side].cpu or self.players[side].remote) end
function Match:sideToMove() return self.board.side end

function Match:recordPosition()
    local k = self.board:key()
    self.reps[k] = (self.reps[k] or 0) + 1
    self.lastKey = k
    return self.reps[k]
end

function Match:notePosition()
    local k = self.board:key()
    if k ~= self.lastKey then self:recordPosition() end
    return self.reps[k] or 0
end

function Match:rewind(hist, reps)
    local h = self.history
    for i = #h, (hist or #h) + 1, -1 do h[i] = nil end
    if reps then
        self.reps = {}
        for k, v in pairs(reps) do self.reps[k] = v end
    end
    self.lastKey = self.board:key()
end

function Match:refresh()
    local b = self.board
    local _, n = b:legalMoves(self.legal)
    self.legalN = n
    self.check = b:inCheck(b.side)
    self.checkSq = self.check and b.king[b.side] or nil
end

function Match:movesFrom(s, out)
    local n = 0
    for i = 1, self.legalN do
        local m = self.legal[i]
        if Board.from(m) == s then n = n + 1; out[n] = m end
    end
    for i = n + 1, #out do out[i] = nil end
    return n
end

function Match:findMove(from, to, promo)
    for i = 1, self.legalN do
        local m = self.legal[i]
        local f, t, p = Board.decode(m)
        if f == from and t == to and (promo == nil or p == promo) then return m end
    end
    return nil
end

function Match:isLegal(m)
    for i = 1, self.legalN do if self.legal[i] == m then return true end end
    return false
end

function Match:playMove(m)
    local b = self.board
    local side = b.side
    local from, to, promo, flag = Board.decode(m)
    local san = b:san(m, self.legal)
    local mover = b.p[from]
    local captured, capId = b:play(m)
    b:removeExpired()
    self.lastMove = { from = from, to = to }
    self:recordPosition()
    self:refresh()
    self:checkResult()
    if self.result and self.result.reason == "CHECKMATE" then san = san .. "#"
    elseif self.check then san = san .. "+" end
    local entry = {
        side = side, no = math.floor((b.ply - 1) / 2) + 1, san = san,
        spell = self.pendingSpell,
    }
    self.pendingSpell = nil
    self.history[#self.history + 1] = entry
    return {
        move = m, from = from, to = to, side = side, piece = mover, captured = captured, capId = capId,
        promo = promo, castle = flag == 3 or flag == 4, ep = flag == 2, san = san, check = self.check,
    }
end

function Match:positionChanged()
    self.board:sanitizeCastling()
    self:refresh()
    if not self.result then self:notePosition() end
    self:checkResult()
end

function Match:checkResult()
    if self.result then return self.result end
    local b = self.board
    if self.legalN == 0 then
        if self.check then
            self.result = { winner = -b.side, reason = "CHECKMATE" }
        else
            self.result = { winner = 0, reason = "STALEMATE" }
        end
    elseif b:insufficientMaterial() then
        self.result = { winner = 0, reason = "INSUFFICIENT MATERIAL" }
    elseif b.half >= Config.chess.fiftyMove then
        self.result = { winner = 0, reason = "FIFTY MOVES" }
    elseif (self.reps[b:key()] or 0) >= 3 then
        self.result = { winner = 0, reason = "REPETITION" }
    end
    return self.result
end

function Match:resign(side)
    if not self.result then self.result = { winner = -side, reason = "RESIGNED" } end
end

function Match:tick(dt)
    if not self.timed or self.result then return false end
    local side = self.board.side
    self.clock[side] = self.clock[side] - dt
    if self.clock[side] <= 0 then
        self.clock[side] = 0

        if not self.players[side].remote then
            self:flag(side)
            return true
        end
    end
    return false
end

function Match:flag(side)
    if self.result then return end
    self.clock[side] = 0

    local winner = -side
    local canMate = not self.board:insufficientMaterial()
    if canMate then
        canMate = false
        local p = self.board.p
        for s = 1, 64 do
            local pc = p[s]
            if pc * winner > 0 and math.abs(pc) ~= Board.K then canMate = true; break end
        end
    end
    self.result = { winner = canMate and winner or 0, reason = "TIMEOUT" }
end

function Match:materialDiff(side)
    local d = 0
    local p = self.board.p
    for s = 1, 64 do
        local pc = p[s]
        if pc ~= 0 then d = d + (pc > 0 and VALUE[pc] or -VALUE[-pc]) end
    end
    return d * side
end

return Match
