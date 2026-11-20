local Config = require("src.config")
local Screen = require("src.utils.screen")
local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local U = require("src.utils.util")
local Board = require("src.chess.board")
local Defs = require("src.cards.defs")

local Sidebar = {}
Sidebar.__index = Sidebar

Sidebar.W = Config.ui.sidebar.width
local W = Sidebar.W
local lg = love.graphics
local floor, sin, min, max = math.floor, math.sin, math.min, math.max

Sidebar.SLOT_W, Sidebar.SLOT_H = Config.ui.sidebar.slotW, Config.ui.sidebar.slotH
local SLOT_X, SLOT_Y = Config.ui.sidebar.slotX, Config.ui.sidebar.slotY
local HIST_LINES = Config.ui.sidebar.histLines
local BOX_Y, BOX_H = Config.ui.sidebar.boxY, Config.ui.sidebar.boxH
local COL2, COL3 = Config.ui.sidebar.col2, Config.ui.sidebar.col3

function Sidebar.new(o)
    local s = setmetatable(o, Sidebar)
    s.clockStr, s.clockKey = "", -1
    s.histLines, s.histCount = {}, -1
    s.scroll = 0
    s.t = 0
    s.glow = 0
    s.mx, s.my = -1, -1
    s.boxHover, s.tipDef = false, nil
    return s
end

function Sidebar:slotRect(i)
    local c = (i - 1) % 2 + 1
    local r = floor((i - 1) / 2) + 1
    return self.x + SLOT_X[c], SLOT_Y[r], Sidebar.SLOT_W, Sidebar.SLOT_H
end

function Sidebar:boxHit(x, y)
    return U.inRect(x, y, self.x, BOX_Y, W, BOX_H)
end

function Sidebar:update(dt, mx, my, log)
    self.t = self.t + dt
    self.mx, self.my = mx or -1, my or -1
    local active = self.match.board.side == self.side and not self.match.result
    self.glow = U.approach(self.glow, active and 1 or 0, 10, dt)

    local m = self.match
    if m.timed then
        local c = m.clock[self.side]
        local key = c < 10 and floor(c * 10) or math.ceil(c)
        if key ~= self.clockKey then
            self.clockKey = key
            self.clockStr = U.formatClock(c)
        end
    end

    local h = m.history
    if self.showHistory and #h ~= self.histCount then
        self.histCount = #h
        local rows = self.histLines
        for i = #rows, 1, -1 do rows[i] = nil end
        local i = 1
        while i <= #h do
            local e = h[i]

            local row = { e.no .. ".", "", "" }
            if e.side == 1 then
                row[2], row[4] = e.san, e.spell and Defs.byName[e.spell]
                local nxt = h[i + 1]
                if nxt and nxt.side == -1 then
                    row[3], row[5] = nxt.san, nxt.spell and Defs.byName[nxt.spell]
                    i = i + 1
                end
            else

                row[2] = "..."
                row[3], row[5] = e.san, e.spell and Defs.byName[e.spell]
            end
            i = i + 1
            rows[#rows + 1] = row
        end
        self.scroll = 0
    end

    mx, my = self.mx, self.my
    self.boxHover = self:boxHit(mx, my)
    self.tipDef = nil
    if not self.boxHover then return end
    local x = self.x
    if self.showHistory then
        local rows = self.histLines
        local last = #rows - self.scroll
        local first = max(1, last - HIST_LINES + 1)
        local r = floor((my - (BOX_Y + 40)) / 20)
        local row = rows[first + r]
        if r >= 0 and first + r <= last and row then
            if mx >= x + COL2 and mx < x + COL3 then self.tipDef = row[4]
            elseif mx >= x + COL3 then self.tipDef = row[5] end
        end
    elseif log then
        for i = 1, min(2, #log) do
            local yy = BOX_Y + 90 + (i - 1) * 20
            if my >= yy and my < yy + 20 then self.tipDef = log[#log - i + 1].def end
        end
    end
end

function Sidebar:wheel(dy, mx, my)
    if not self.showHistory then return false end
    if not self:boxHit(mx, my) then return false end
    local maxScroll = max(0, #self.histLines - HIST_LINES)
    self.scroll = U.clamp(self.scroll + (dy > 0 and 1 or -1), 0, maxScroll)
    return true
end

local function rect(x, y, w, h) lg.rectangle("fill", x, y, w, h) end

local function box(x, y, w, h)
    Pal.set(Pal.N)
    rect(x + 6, y + 6, w, h)
    lg.setColor(1, 1, 1, 1)
    A.ui.panel_small:draw(x, y, w, h, 2)
end

function Sidebar:drawBackdrop()
    local x = self.x
    Pal.set(Pal.N, 0.7)
    rect(x - 12, 0, W + 24, Screen.H)
    if self.right then

        Pal.set(Pal.I, 0.3)
        rect(x - 12, 0, W + 24, Screen.H)
        Pal.set(Pal.I, 0.5)
        for yy = 0, Screen.H, 24 do rect(x - 12, yy, W + 24, 2) end
    end
    Pal.set(self.right and Pal.I or Pal.B)
    rect(x - 12, 0, 4, Screen.H)
    rect(x + W + 8, 0, 4, Screen.H)
end

function Sidebar:drawPlate(statusText)
    local x, y, w, h = self.x, 12, W, 96
    box(x, y, w, h)

    local g = self.glow
    if g > 0.02 then
        local pulse = 0.65 + 0.35 * sin(self.t * 5)
        Pal.set(Pal.C, g * pulse)
        rect(x - 6, y - 6, w + 12, 4); rect(x - 6, y + h + 2, w + 12, 4)
        rect(x - 6, y - 2, 4, h + 4); rect(x + w + 2, y - 2, 4, h + 4)
    end
    local king = A.piece[self.side][Board.K]
    local ax = self.right and (x + w - 16 - 64) or (x + 16)
    Pal.set(Pal.N)
    rect(ax - 4, y + 12, 72, 72)
    Pal.set(self.right and Pal.I or Pal.B)
    rect(ax, y + 16, 64, 64)
    lg.setColor(1, 1, 1, 1)
    lg.draw(king, ax, y + 16, 0, 2, 2)
    local tx = self.right and (x + w - 96) or (x + 96)
    local align = self.right and "right" or "left"
    Text.print(self.name, tx, y + 22, 3, Pal.C, align, Pal.N)
    local sub, subColor = self.sub, Pal.B
    if self.rating then sub, subColor = "Elo " .. tostring(self.rating), Pal.C end
    Text.print(sub, tx, y + 60, 2, subColor, align)
    if statusText and g > 0.5 then

        local sx = self.right and (x + 24) or (x + w - 24)
        local salign = self.right and "left" or "right"
        local sw = Text.width(statusText, 2)
        local dx = self.right and (sx + sw + 14) or (sx - sw - 14)

        local free = w - 96 - Text.width(self.name, 3) - 24 - sw
        if free > 40 and floor(self.t * 2) % 2 == 0 then Frame.diamond(dx, y + 36, 6, Pal.C) end
        Text.print(statusText, sx, y + 28, 2, Pal.C, salign)
    end
end

function Sidebar:drawClock()
    local x, y, w, h = self.x, 124, W, 80
    box(x, y, w, h)
    local m = self.match
    if not m.timed then
        Text.print("NO CLOCK", x + w / 2, y + 30, 3, Pal.B, "center")
        return
    end
    local c = m.clock[self.side]
    local active = m.board.side == self.side and not m.result
    local col = active and Pal.C or Pal.B
    if active and c < 20 and floor(self.t * 3) % 2 == 0 then col = Pal.I end
    if active then

        local hx = self.right and (x + w - 36) or (x + 36)
        Frame.diamond(hx, y + 30, 8, Pal.C)
        Frame.diamond(hx, y + 50, 8, floor(self.t * 2) % 2 == 0 and Pal.B or Pal.I)
    end
    Text.print(self.clockStr, x + w / 2, y + 19, 6, col, "center", Pal.N)
end

function Sidebar:drawSlots(enabled)
    for i = 1, Config.ui.card.maxHand do
        local x, y, w, h = self:slotRect(i)
        lg.setColor(1, 1, 1, 1)
        A.ui.slot:draw(x, y, w, h, 2)
        Pal.set(Pal.N, 0.5)
        Frame.diamond(x + w / 2, y + h / 2, 12, Pal.N)
    end
    if not enabled then
        local cx = self.x + W / 2
        Pal.set(Pal.N, 0.75)
        rect(self.x + 48, 220, W - 96, 616)
        lg.setColor(1, 1, 1, 1)
        A.ui.tooltip:draw(cx - 140, 500, 280, 56, 2)
        Text.print("SPELLS OFF", cx, 520, 2, Pal.C, "center")
    end
end

function Sidebar:drawMana(mana, maxMana)
    local x, y, w, h = self.x, 852, W, 48
    box(x, y, w, h)
    local lx = self.right and (x + w - 24) or (x + 24)
    Text.print("MANA", lx, y + 17, 2, Pal.B, self.right and "right" or "left")
    for i = 1, maxMana do
        local cx = self.right and (x + w - 140 - (i - 1) * 56) or (x + 140 + (i - 1) * 56)
        local cy = y + 24
        Frame.diamond(cx, cy, 16, Pal.N)
        if i <= mana then
            Frame.diamond(cx, cy, 12, Pal.B)
            Frame.diamond(cx - 2, cy - 2, 6, Pal.C)
        else
            Frame.diamond(cx, cy, 12, Pal.I)
            Frame.diamond(cx, cy, 6, Pal.N)
        end
    end
end

local function boxHint(self, x, y, w, h, hx, align)
    if not self.boxHover then return end
    Pal.set(Pal.C)
    rect(x - 4, y - 4, w + 8, 2); rect(x - 4, y + h + 2, w + 8, 2)
    rect(x - 4, y - 2, 2, h + 4); rect(x + w + 2, y - 2, 2, h + 4)
    Text.print("CLICK: VIEW ALL", hx, y + 14, 2, Pal.C, align)
end

local function moveCell(s, def, x, y, col, hot)
    Text.print(s, x, y, 2, hot and Pal.C or col, "left")
    if def then
        local gx = x + Text.width(s, 2) + 10
        Frame.diamond(gx, y + 7, 5, hot and Pal.C or Pal.I)
    end
end

function Sidebar:drawHistory()
    local x, y, w, h = self.x, BOX_Y, W, BOX_H
    box(x, y, w, h)
    Text.print("MOVES", x + 20, y + 14, 2, Pal.B, "left")
    boxHint(self, x, y, w, h, x + w - 48, "right")
    local lines = self.histLines
    local n = #lines
    if n == 0 then
        Text.print("NO MOVES YET", x + 20, y + 44, 2, Pal.I, "left")
        return
    end
    local last = n - self.scroll
    local first = max(1, last - HIST_LINES + 1)
    local row = 0
    for i = first, last do
        local r = lines[i]
        local yy = y + 42 + row * 20
        local col = i == n and Pal.C or Pal.B
        Text.print(r[1], x + 20, yy, 2, Pal.N, "left")
        local tip = self.tipDef
        moveCell(r[2], r[4], x + COL2, yy, col, tip and tip == r[4] and self.mx < x + COL3)
        moveCell(r[3], r[5], x + COL3, yy, col, tip and tip == r[5] and self.mx >= x + COL3)
        row = row + 1
    end
    if n > HIST_LINES then

        Frame.diamond(x + w - 24, y + 22, 6, self.scroll < n - HIST_LINES and Pal.C or Pal.I)
        Frame.diamond(x + w - 24, y + h - 20, 6, self.scroll > 0 and Pal.C or Pal.I)
    end
end

function Sidebar:drawStatus(title, line1, line2, thinking, log)
    local x, y, w, h = self.x, BOX_Y, W, BOX_H
    box(x, y, w, h)
    Text.print(title, x + w - 20, y + 14, 2, Pal.B, "right")
    boxHint(self, x, y, w, h, x + 20, "left")
    if thinking then
        for i = 0, 2 do
            local up = (floor(self.t * 6) % 3 == i) and 4 or 0
            Frame.diamond(x + 30 + i * 22, y + 50 - up, 7, up > 0 and Pal.C or Pal.B)
        end
        Text.print(line1, x + 100, y + 44, 2, Pal.C, "left")
    else
        Text.print(line1, x + 20, y + 44, 2, Pal.C, "left")
    end
    if line2 then Text.print(line2, x + 20, y + 68, 2, Pal.B, "left") end
    if log then
        for i = 1, min(2, #log) do
            local e = log[#log - i + 1]
            local hot = e.def and e.def == self.tipDef
            Text.print(e.text, x + 20, y + 92 + (i - 1) * 20, 2, (i == 1 or hot) and Pal.C or Pal.B, "left")
            if hot then
                Pal.set(Pal.C)
                rect(x + 20, y + 108 + (i - 1) * 20, Text.width(e.text, 2), 2)
            end
        end
    end
end

return Sidebar
