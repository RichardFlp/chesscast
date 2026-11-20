local Config = require("src.config")
local Screen = require("src.utils.screen")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local Button = require("src.ui.button")
local CardTip = require("src.ui.cardtip")
local U = require("src.utils.util")

local HV = {}
HV.__index = HV

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

local H = Config.ui.history
local PX, PY, PW, PH = H.x, H.y, H.w, H.h
local LIST_X, LIST_Y, LIST_W, LIST_H = H.listX, H.listY, H.listW, H.listH
local NO_X = H.noX
local COL_X = H.colX
local COL_W = H.colW
local LINE_H = H.lineH
local CHIP_H = H.chipH
local GAP = H.gap
HV.COL_X, HV.LIST_Y, HV.LINE_H = COL_X, LIST_Y, LINE_H

local function rect(x, y, w, h) lg.rectangle("fill", x, y, w, h) end

function HV.new(game)
    local h = setmetatable({ game = game }, HV)
    h.scroll, h.maxScroll = 0, 0
    h.ver = -1
    h.rows = {}
    h.mx, h.my = 0, 0
    local back = H.back
    h.back = Button.new { x = Screen.W / 2 - back.w / 2, y = Screen.H - back.bottom, w = back.w, h = back.h,
        label = "BACK", style = "primary", backSound = true,
        onClick = function() game:closeHistory() end }
    return h
end

local function layoutCell(items)
    local x, line = 0, 0
    for _, it in ipairs(items) do
        local w
        if it.kind == "spell" then
            w = Text.width(it.def.name, 2) + 28 + (it.countered and Text.width("COUNTERED", 2) + 12 or 0)
        elseif it.kind == "note" then
            w = Text.width(it.text, 2)
        else
            w = Text.width(it.san, 3)
        end
        if x > 0 and x + w > COL_W then x, line = 0, line + 1 end
        it.x, it.line, it.w = x, line, w
        x = x + w + GAP
    end
    return line + 1
end

function HV:rebuild()
    local g = self.game
    local rows, byNo = {}, {}
    self.moves, self.spells = 0, 0
    for _, e in ipairs(g.timeline) do
        local no = floor(e.ply / 2) + 1
        local row = byNo[no]
        if not row then
            row = { no = no, noStr = no .. ".", cells = { [1] = {}, [-1] = {} } }
            byNo[no] = row
            rows[#rows + 1] = row
        end
        local cell = row.cells[e.side]
        cell[#cell + 1] = e
        if e.kind == "move" and not e.rewound then self.moves = self.moves + 1 end
        if e.kind == "spell" and not e.rewound then self.spells = self.spells + 1 end
    end
    table.sort(rows, function(a, b) return a.no < b.no end)
    local y = 0
    for _, row in ipairs(rows) do
        local lines = max(layoutCell(row.cells[1]), layoutCell(row.cells[-1]))
        row.y, row.h = y, lines * LINE_H
        y = y + row.h
    end
    self.rows = rows
    self.total = y
    self.maxScroll = max(0, y - LIST_H)
    self.summary = self.moves .. (self.moves == 1 and " MOVE" or " MOVES") .. "   " ..
        self.spells .. (self.spells == 1 and " SPELL" or " SPELLS")
end

function HV:open()
    self.ver = -1
    self:update(0, self.mx, self.my)
    self.scroll = self.maxScroll
end

function HV:update(dt, mx, my)
    self.mx, self.my = mx, my
    if self.ver ~= self.game.timelineVer then
        local atEnd = self.scroll >= self.maxScroll
        self.ver = self.game.timelineVer
        self:rebuild()
        if atEnd then self.scroll = self.maxScroll end
        self.scroll = U.clamp(self.scroll, 0, self.maxScroll)
    end
    self.back:update(dt, mx, my)

    self.tip = nil
    if U.inRect(mx, my, LIST_X, LIST_Y, LIST_W, LIST_H) then
        for _, row in ipairs(self.rows) do
            local ry = LIST_Y + row.y - self.scroll
            if my >= ry and my < ry + row.h then
                for side, cell in pairs(row.cells) do
                    for _, it in ipairs(cell) do
                        if it.kind == "spell" then
                            local ix, iy = COL_X[side] + it.x, ry + it.line * LINE_H + H.tooltipPadY
                            if U.inRect(mx, my, ix, iy, it.w, CHIP_H) then self.tip = it.def end
                        end
                    end
                end
            end
        end
    end
    self.wantHand = self.back.hover or self.tip ~= nil
end

function HV:wheel(dy)
    self.scroll = U.clamp(self.scroll - dy * LINE_H, 0, self.maxScroll)
end

function HV:keypressed(key)
    if key == "up" then self:wheel(1)
    elseif key == "down" then self:wheel(-1)
    elseif key == "pageup" then self.scroll = max(0, self.scroll - LIST_H)
    elseif key == "pagedown" then self.scroll = min(self.maxScroll, self.scroll + LIST_H)
    elseif key == "home" then self.scroll = 0
    elseif key == "end" then self.scroll = self.maxScroll
    elseif key == "return" or key == "kpenter" or key == "space" then self.game:closeHistory()
    end
end

function HV:mousepressed(x, y, b) return self.back:mousepressed(x, y, b) end
function HV:mousereleased(x, y, b) self.back:mousereleased(x, y, b) end

local function drawItem(it, x, y)
    local a = it.rewound and 0.45 or 1
    if it.kind == "spell" then
        local w = Text.width(it.def.name, 2) + 28
        Pal.set(Pal.N, a)
        rect(x + 4, y + 4, w, CHIP_H)
        Pal.set(it.countered and Pal.I or Pal.B, a)
        rect(x, y, w, CHIP_H)
        Pal.set(Pal.C, a)
        rect(x, y, w, 2); rect(x, y + CHIP_H - 2, w, 2); rect(x, y, 2, CHIP_H); rect(x + w - 2, y, 2, CHIP_H)
        Frame.diamond(x + 12, y + CHIP_H / 2 + 1, 4, Pal.C)
        Text.print(it.def.name, x + 20, y + 10, 2, Pal.C, "left", Pal.N, a)
        if it.countered then
            Pal.set(Pal.C, a)
            rect(x + 6, y + CHIP_H / 2, w - 12, 2)
            Text.print("COUNTERED", x + w + 12, y + 10, 2, Pal.B, "left", nil, a)
        end
        return
    elseif it.kind == "note" then
        Text.print(it.text, x, y + 10, 2, Pal.B, "left", nil, a)
    else
        Text.print(it.san, x, y + 6, 3, Pal.C, "left", Pal.N, a)
    end
    if it.rewound then
        Pal.set(Pal.C, 0.8)
        rect(x - 2, y + CHIP_H / 2, it.w + 4, 2)
    end
end

function HV:draw()
    local g = self.game
    Pal.set(Pal.N, 0.75)
    rect(0, 0, Screen.W, Screen.H)
    Frame.panel(PX, PY, PW, PH, "MATCH HISTORY")

    Text.print(self.summary, PX + 36, PY + 50, 2, Pal.B, "left")
    Text.print("HOVER A SPELL TO READ IT", PX + PW - 36, PY + 50, 2, Pal.B, "right")

    local m = g.match
    Text.print("#", NO_X, H.headY, 2, Pal.B, "left")
    for side, x in pairs(COL_X) do
        Frame.diamond(x + 8, H.nameY + 8, 8, side == 1 and Pal.C or Pal.N)
        Text.print(m.players[side].name, x + 26, H.nameY, 2, Pal.C, "left", Pal.N)
    end
    Pal.set(Pal.B)
    rect(LIST_X, H.headSepY, LIST_W, 2)

    if #self.rows == 0 then
        Text.print("NO MOVES YET", Screen.W / 2, LIST_Y + H.emptyY, 3, Pal.I, "center")
    else
        lg.setScissor(LIST_X, LIST_Y, LIST_W, LIST_H)
        for i, row in ipairs(self.rows) do
            local ry = LIST_Y + row.y - self.scroll
            if ry + row.h >= LIST_Y and ry < LIST_Y + LIST_H then
                if i % 2 == 0 then
                    Pal.set(Pal.I, 0.25)
                    rect(LIST_X, ry, LIST_W, row.h)
                end
                Text.print(row.noStr, NO_X, ry + 14, 2, Pal.B, "left")
                for side, cell in pairs(row.cells) do
                    if #cell == 0 then
                        Text.print("-", COL_X[side], ry + 14, 2, Pal.I, "left")
                    end
                    for _, it in ipairs(cell) do
                        drawItem(it, COL_X[side] + it.x, ry + it.line * LINE_H + 7)
                    end
                end
            end
        end
        lg.setScissor()

        if self.maxScroll > 0 then
            local bx = LIST_X + LIST_W - H.scrollBarX
            Pal.set(Pal.N)
            rect(bx, LIST_Y, H.scrollBarW, LIST_H)
            local th = max(40, LIST_H * LIST_H / self.total)
            local ty = LIST_Y + (LIST_H - th) * (self.scroll / self.maxScroll)
            Pal.set(Pal.B)
            rect(bx, floor(ty), H.scrollBarW, floor(th))
        end
    end
    Pal.set(Pal.B)
    rect(LIST_X, LIST_Y + LIST_H + 8, LIST_W, 2)

    self.back:draw()
    if self.tip then CardTip.drawAtMouse(self.tip, self.mx, self.my) end
end

return HV
