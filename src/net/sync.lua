local Defs = require("src.cards.defs")

local Sync = {}
Sync.__index = Sync

local function split(blob)
    local t = {}
    for line in blob:gmatch("[^\n]+") do t[#t + 1] = line end
    return t
end
Sync.split = split

function Sync.header(seed, spells, clock, hostSide, name)
    return string.format("S %d %d %d %d %s", seed, spells and 1 or 0, clock, hostSide, name or "")
end

function Sync.cleanName(s)
    return ((s or ""):upper():gsub("[^A-Z0-9]", "")):sub(1, 5)
end

function Sync.parseHeader(line)
    local seed, spells, clock, side, name = (line or ""):match("^S (%d+) (%d) (%d+) (%-?%d) ?(%w*)%s*$")
    if not seed then return nil end
    name = Sync.cleanName(name)
    return { seed = tonumber(seed), spells = spells == "1", clock = tonumber(clock), hostSide = tonumber(side),
        name = name ~= "" and name or nil }
end

function Sync.new(game, session, role, lines)
    local s = setmetatable({}, Sync)
    s.game, s.session, s.role = game, session, role
    s.log = role == "host" and lines or nil
    s.known = 1
    s.queue, s.qi, s.qn = {}, 1, 0
    s.header = lines[1]
    if role == "guest" then s:merge(lines) else s.known = #lines end
    return s
end

function Sync:merge(lines)
    for i = self.known + 1, #lines do self:push(lines[i]) end
    if #lines > self.known then self.known = #lines end
end

function Sync:push(a)
    self.qn = self.qn + 1
    self.queue[self.qn] = a
end

local function outOfTurn(a) return a:sub(1, 1) == "R" or a:sub(1, 1) == "T" end

function Sync:localAction(a)
    if Sync.trace then print("sync: send " .. a) end
    if self.role == "host" then
        local log = self.log
        log[#log + 1] = a
        self.known = #log
        self.session:sendMove(table.concat(log, "\n"))
    elseif outOfTurn(a) then
        self.session:sendInput("0|" .. a)
    else
        self.known = self.known + 1
        self.session:sendInput(self.known .. "|" .. a)
    end
end

function Sync:onMessage(m)
    local g = self.game
    if Sync.trace and m.t ~= "state" then print("sync: msg " .. m.t .. " " .. tostring(m.blob or m.reason or m.message or "")) end
    if m.t == "peer_input" and m.blob == "RM" then
        g:rematchRequested()
    elseif m.t == "peer_input" and self.role == "host" then
        local n, a = m.blob:match("^(%d+)|(.+)$")
        n = tonumber(n)
        if not n or a:sub(1, 2) == "N " then return end
        local log = self.log
        if n == #log + 1 or (n == 0 and outOfTurn(a)) then
            log[#log + 1] = a
            self.known = #log
            self:push(a)
            self.session:sendMove(table.concat(log, "\n"))
        else
            print("sync: unexpected action #" .. n .. " (log has " .. #log .. ")")
        end
    elseif m.t == "state" and self.role == "guest" then
        if Sync.trace then print("sync: state " .. #split(m.blob) .. " lines, known " .. self.known) end
        local lines = split(m.blob)
        if lines[1] ~= self.header and Sync.parseHeader(lines[1]) then
            g:rematchStart(lines)
        else
            self:merge(lines)
        end
    elseif m.t == "peer_left" then
        g:netEnded("OPPONENT LEFT")
    elseif m.t == "closed" then
        g:netEnded("CONNECTION LOST")
    elseif m.t == "event" and (m.event == "kicked" or m.event == "banned") then
        g:netEnded("CONNECTION LOST")
    elseif m.t == "error" or m.t == "move_rejected" then
        print("roomie: " .. tostring(m.message or m.reason))
    end
end

function Sync:apply(a)
    local g = self.game
    local match = g.match
    local kind = a:sub(1, 1)
    local f = {}
    for w in a:gmatch("%S+") do f[#f + 1] = w end
    if kind == "R" then
        match:resign(tonumber(f[2]))
        return true
    elseif kind == "T" then
        match:flag(tonumber(f[2]))
        return true
    end
    if match.result then return true end
    local side = match.board.side
    if kind == "M" then
        local mv = match:findMove(tonumber(f[2]), tonumber(f[3]), tonumber(f[4]))
        if not mv then return false end
        if f[5] and match.timed then match.clock[side] = tonumber(f[5]) end
        g.netApplying = true
        g:applyMove(mv)
        g.netApplying = false
        return true
    elseif kind == "C" then
        local L = g.spells
        if not L then return false end
        local def = Defs.bySlug[f[2]]
        local cv
        for _, c in ipairs(L.hand[side]) do if c.def == def then cv = c; break end end
        if not cv then return false end
        if f[5] and match.timed then match.clock[side] = tonumber(f[5]) end
        g.netApplying = true
        L:beginCast(side, cv, tonumber(f[3]), tonumber(f[4]))
        g.netApplying = false
        return true
    end
    return false
end

function Sync:update()
    while self.session do
        local m = self.session:poll()
        if not m then break end
        self:onMessage(m)
    end
    if self.over then return end
    local q = self.queue
    if self.qi > self.qn then return end
    local g = self.game
    if not g.started or g.view:busy() or (g.spells and g.spells:busy()) then return end
    local a = q[self.qi]
    q[self.qi] = nil
    self.qi = self.qi + 1
    if Sync.trace then print("sync: apply " .. a) end
    if not self:apply(a) then
        print("sync: could not apply '" .. a .. "'")
        g:netEnded("OUT OF SYNC")
    end
end

function Sync:move(info, clock)
    self:localAction(string.format("M %d %d %d %.2f", info.from, info.to, info.promo or 0, clock))
end

function Sync:cast(slug, a, c, clock)
    self:localAction(string.format("C %s %s %s %.2f", slug, a and tostring(a) or "-", c and tostring(c) or "-", clock))
end

return Sync
