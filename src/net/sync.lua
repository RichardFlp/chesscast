local Board = require("src.chess.board")
local Defs = require("src.cards.defs")
local S = require("src.cards.spells")
local Config = require("src.config")

local Sync = {}
Sync.__index = Sync

local function split(blob)
    local lines = {}
    if type(blob) ~= "string" then return lines end
    for line in blob:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    return lines
end

Sync.split = split

local function validSquare(n)
    return n and n >= 1 and n <= 64
end

local function validSide(n)
    return n == 1 or n == -1
end

local function validClock(n)
    return n and n >= 0 and n <= Config.net.maxClock
end

local function validPiece(n)
    return n == 0 or (n >= Board.N and n <= Board.Q)
end

local function validTarget(s)
    if s == "-" then return true end
    local n = tonumber(s)
    return validSquare(n)
end

function Sync.cleanName(s)
    local valid = Config.net.nameChars
    local out = {}
    for c in (s or ""):upper():gmatch("[A-Z0-9]") do
        if valid:find(c, 1, true) and #out < Config.net.nameLength then
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

function Sync.header(seed, spells, clock, hostSide, name, rating)
    local line = string.format("S %d %d %d %d %s", seed, spells and 1 or 0, clock, hostSide, name or "")
    if rating ~= nil then line = line .. " " .. tostring(rating) end
    return line
end

function Sync.parseHeader(line)
    if type(line) ~= "string" then return nil end
    local seed, spells, clock, side, name, rating = line:match(
        "^S (%d+) (%d) (%d+) (%-?%d) ?(%w*)%s*(%d*)%s*$"
    )
    if not seed or not clock or not side then return nil end

    seed = tonumber(seed)
    clock = tonumber(clock)
    side = tonumber(side)
    rating = tonumber(rating)
    if seed < 1 or seed > Config.net.maxSeed then return nil end
    if spells ~= "0" and spells ~= "1" then return nil end
    if not validClock(clock) or not validSide(side) then return nil end
    if rating and (rating < Config.net.ratingMin or rating > Config.net.ratingMax) then return nil end

    name = Sync.cleanName(name)
    return {
        seed = seed,
        spells = spells == "1",
        clock = clock,
        hostSide = side,
        name = name ~= "" and name or nil,
        rating = rating,
    }
end

function Sync.parseAction(raw)
    if type(raw) ~= "string" then return nil end
    if #raw > Config.net.maxAction then return nil end

    local kind = raw:sub(1, 1)
    if kind == "M" then
        local from, to, promo, clock = raw:match("^M (%d+) (%d+) (%d+) (%S+)$")
        if not from or not to or not promo or not clock then return nil end
        from, to, promo, clock = tonumber(from), tonumber(to), tonumber(promo), tonumber(clock)
        if not validSquare(from) or not validSquare(to) then return nil end
        if not validPiece(promo) or not validClock(clock) then return nil end
        return { kind = "M", from = from, to = to, promo = promo, clock = clock }
    elseif kind == "C" then
        local slug, a, c, clock = raw:match("^C (%S+) (%S+) (%S+) (%S+)$")
        if not slug or not a or not c or not clock then return nil end
        if not Defs.bySlug[slug] then return nil end
        if not validTarget(a) or not validTarget(c) then return nil end
        clock = tonumber(clock)
        if not validClock(clock) then return nil end
        return { kind = "C", slug = slug, a = a, c = c, clock = clock }
    elseif kind == "R" or kind == "T" or kind == "A" then
        local side = raw:match("^[RTA] (%-?%d+)$")
        side = tonumber(side)
        if not validSide(side) then return nil end
        return { kind = kind, side = side }
    end

    return nil
end

function Sync.new(game, session, role, lines)
    lines = lines or {}
    local s = setmetatable({}, Sync)
    s.game, s.session, s.role = game, session, role
    s.log = role == "host" and lines or nil
    s.known = 1
    s.queue, s.qi, s.qn = {}, 1, 0
    s.header = lines[1]
    s.lastBeat = love.timer.getTime()
    if session then session.heard = s.lastBeat end
    if role == "guest" then s:merge(lines) else s.known = #lines end
    return s
end

function Sync:merge(lines)
    for i = self.known + 1, #lines do
        self:push(lines[i])
    end
    if #lines > self.known then self.known = #lines end
end

function Sync:push(action)
    self.qn = self.qn + 1
    self.queue[self.qn] = action
end

local function outOfTurn(action)
    local kind = action:sub(1, 1)
    return kind == "R" or kind == "T" or kind == "A"
end

local function remoteAction(sync, parsed)
    local remote = -sync.game.match.human
    if parsed.kind == "T" and not sync.game.match.timed then return false end
    if parsed.kind == "M" or parsed.kind == "C" then
        return sync.game.match.board.side == remote
    end
    return parsed.side == remote
end

Sync.remoteAction = remoteAction

function Sync:validRemote(action)
    local parsed = Sync.parseAction(action)
    if not parsed or not Sync.remoteAction(self, parsed) then return false end
    local match = self.game.match
    if parsed.kind == "R" then return true end
    if parsed.kind == "A" then
        return not match.result or match.result.reason == "AFK"
    end
    if parsed.kind == "T" then return match.timed end
    if parsed.kind == "M" then
        return match:findMove(parsed.from, parsed.to, parsed.promo) ~= nil
    end
    local layer = self.game.spells
    local def = layer and Defs.bySlug[parsed.slug]
    if not def then return false end
    local side = match.board.side
    local held = false
    for _, cv in ipairs(layer.hand[side] or {}) do
        if cv.def == def then held = true; break end
    end
    if not held then return false end
    local ctx = layer.ctxFor and layer:ctxFor(side) or nil
    if not S.castable(match.board, side, def, layer, ctx, true) then return false end
    local a, c = tonumber(parsed.a), tonumber(parsed.c)
    if def.steps == 0 then
        return S.check(match.board, side, def, nil, nil, ctx) ~= nil
    elseif def.steps == 1 then
        if not a then return false end
        for _, s in ipairs(S.firstTargets(match.board, side, def, ctx)) do
            if s == a then return true end
        end
        return false
    end
    if not a or not c then return false end
    for _, s in ipairs(S.secondTargets(match.board, side, def, a, ctx)) do
        if s == c then return true end
    end
    return false
end

function Sync:broadcast()
    if self.session and self.log then
        self.session:sendMove(table.concat(self.log, "\n"))
    end
end

function Sync:localAction(action)
    if self.role == "host" then
        local log = self.log
        log[#log + 1] = action
        self.known = #log
        -- Host publishes.
        self:broadcast()
    elseif outOfTurn(action) then
        self.session:sendInput("0|" .. action)
    else
        self.known = self.known + 1
        self.session:sendInput(self.known .. "|" .. action)
    end
end

function Sync:onMessage(message)
    local game = self.game

    if message.t == "peer_input" and message.blob == Config.net.rematchBlob then
        if game.match.result then game:rematchRequested() end
    elseif message.t == "peer_input" and self.role == "host" then
        local selfPeer = self.session and self.session.peer
        if (selfPeer and message.peer == selfPeer) or game.match.result then return end
        local raw = message.blob
        if type(raw) ~= "string" then return end
        if raw == Config.net.heartbeatBlob then return end

        local number, action = raw:match("^(%d+)|(.+)$")
        number = tonumber(number)
        if not number or not action then return end
        if action:sub(1, 2) == "N " then return end

        local parsed = Sync.parseAction(action)
        if not parsed or not Sync.remoteAction(self, parsed) then return end
        if self.qi > self.qn and not self:validRemote(action) then return end

        local log = self.log
        if number == #log + 1 or (number == 0 and outOfTurn(action)) then
            log[#log + 1] = action
            self.known = #log
            self:push(action)
        end
    elseif message.t == "peer_input" and self.role == "guest" then
        local raw = message.blob
        if type(raw) ~= "string" then return end
        local number, action = raw:match("^(%d+)|(.+)$")
        number = tonumber(number)
        if not number or not action then return end
        if number ~= self.known + 1 then return end
        local parsed = Sync.parseAction(action)
        if not parsed or not Sync.remoteAction(self, parsed) then return end
        if self.qi > self.qn and not self:validRemote(action) then return end
        self.known = number
        self:push(action)
    elseif message.t == "state" and self.role == "guest" then
        if type(message.blob) ~= "string" or #message.blob > Config.net.maxBlob then return end
        local lines = split(message.blob)
        if #lines == 0 then return end
        if lines[1] ~= self.header and Sync.parseHeader(lines[1]) then
            game:rematchStart(lines)
        else
            self:merge(lines)
        end
    elseif message.t == "peer_left" then
        game:netEnded("OPPONENT LEFT")
    elseif message.t == "closed" then
        game:netEnded("CONNECTION LOST")
    elseif message.t == "event" and (message.event == "kicked" or message.event == "banned") then
        game:netEnded("CONNECTION LOST")
    elseif message.t == "error" or message.t == "move_rejected" then
        print("relay: " .. tostring(message.message or message.reason))
    end
end

function Sync:apply(action, trustClock)
    if not self:validRemote(action) then return false end
    local parsed = Sync.parseAction(action)
    if not parsed then return false end

    local game = self.game
    local match = game.match
    if parsed.kind == "A" then
        if match.result then return match.result.reason == "AFK" end
        match.result = { winner = 0, reason = "AFK" }
        return true
    end
    if parsed.kind == "R" or parsed.kind == "T" then
        if parsed.kind == "R" then
            match:resign(parsed.side)
        else
            match:flag(parsed.side)
        end
        return true
    end

    if match.result then return true end

    local side = match.board.side
    if parsed.kind == "M" then
        local move = match:findMove(parsed.from, parsed.to, parsed.promo)
        if not move then return false end
        if trustClock and match.timed then match.clock[side] = parsed.clock end
        game.netApplying = true
        game:applyMove(move)
        game.netApplying = false
        return true
    elseif parsed.kind == "C" then
        local layer = game.spells
        if not layer then return false end
        local def = Defs.bySlug[parsed.slug]
        if not def then return false end
        local card
        for _, held in ipairs(layer.hand[side]) do
            if held.def == def then card = held; break end
        end
        if not card then return false end
        if trustClock and match.timed then match.clock[side] = parsed.clock end
        game.netApplying = true
        layer:beginCast(side, card, tonumber(parsed.a), tonumber(parsed.c))
        game.netApplying = false
        return true
    end

    return false
end

Sync.WARN_AFTER = Config.net.silenceWarn
Sync.DROP_AFTER = Config.net.silenceDrop

function Sync:silence()
    local session = self.session
    if not (session and session.heard) then return 0 end
    return love.timer.getTime() - session.heard
end

function Sync:beat(now)
    now = now or love.timer.getTime()
    if now - (self.lastBeat or 0) < Config.net.heartbeat then return false end
    self.lastBeat = now
    if not self.session then return false end
    if self.role == "host" then
        -- Guest keepalive.
        self:broadcast()
    else
        self.session:sendInput(Config.net.heartbeatBlob)
    end
    return true
end

function Sync:update()
    self:beat()
    while self.session do
        local message = self.session:poll()
        if not message then break end
        self:onMessage(message)
    end

    if self.session and self:silence() > Sync.DROP_AFTER then
        self.game:netEnded("OPPONENT DISCONNECTED")
        return
    end

    if self.over or self.qi > self.qn then return end
    local game = self.game
    if game.match.result then return end
    if not game.started or game.view:busy() or (game.spells and game.spells:busy()) then
        return
    end

    local action = self.queue[self.qi]
    self.queue[self.qi] = nil
    self.qi = self.qi + 1

    local trustClock = self.role == "guest"
    if not self:apply(action, trustClock) then
        if self.role == "host" then
            print("sync: ignored action " .. tostring(action))
        else
            self.game:netEnded("OUT OF SYNC")
        end
    end
end

function Sync:move(info, clock)
    local action = string.format("M %d %d %d %.2f", info.from, info.to, info.promo or 0, clock)
    self:localAction(action)
end

function Sync:cast(slug, a, c, clock)
    local action = string.format("C %s %s %s %.2f", slug, a and tostring(a) or "-", c and tostring(c) or "-", clock)
    self:localAction(action)
end

return Sync
