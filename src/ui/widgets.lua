local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Spring = require("src.utils.spring")
local Audio = require("src.audio.audio")
local U = require("src.utils.util")

local W = {}

local Slider = {}
Slider.__index = Slider
W.Slider = Slider

function Slider.new(o)
    local s = setmetatable(o, Slider)
    s.h = 64
    s.knob = Spring.new(s.value, 400, 28)
    s.glow = Spring.new(0, 250, 18)
    s.dragging = false

    s.valueW = Text.width("100%", 3) + 28
    return s
end

function Slider:trackRect()
    return self.x + self.w - 520, self.y + 16, 520 - self.valueW - 8, 32
end

function Slider:update(dt, mx, my)
    local tx, ty, tw, th = self:trackRect()
    if self.dragging then
        local v = U.clamp((mx - tx - 8) / (tw - 16), 0, 1)
        v = math.floor(v * 20 + 0.5) / 20
        if v ~= self.value then
            self.value = v
            Audio.play("tick", 0.8 + v * 0.6)
            if self.onChange then self.onChange(v) end
        end
    end
    local over = U.inRect(mx, my, self.x, self.y, self.w, self.h)
    self.glow.target = (over or self.focus or self.dragging) and 1 or 0
    self.knob.target = self.value
    self.knob:update(dt); self.glow:update(dt)
end

function Slider:nudge(d)
    local v = U.clamp(math.floor((self.value + d) * 20 + 0.5) / 20, 0, 1)
    if v ~= self.value then
        self.value = v
        Audio.play("tick", 0.8 + v * 0.6)
        if self.onChange then self.onChange(v) end
    end
end

function Slider:mousepressed(mx, my, b)
    local tx, ty, tw, th = self:trackRect()
    if b == 1 and U.inRect(mx, my, tx - 16, ty - 16, tw + 32, th + 32) then
        self.dragging = true
        self:update(0, mx, my)
        return true
    end
    return false
end

function Slider:mousereleased() self.dragging = false end

function Slider:draw()
    local g = self.glow.x
    Text.print(self.label, self.x + 24 + g * 8, self.y + 22, 3, g > 0.5 and Pal.C or Pal.B, "left", Pal.N)
    local tx, ty, tw, th = self:trackRect()
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.slot:draw(tx - 4, ty - 4, tw + 8, th + 8, 2)

    local fillW = math.floor((tw - 16) * U.clamp(self.knob.x, 0, 1))
    for sx = 0, fillW - 1, 12 do
        Pal.set((sx / 12) % 2 == 0 and Pal.B or Pal.I)
        love.graphics.rectangle("fill", tx + 8 + sx, ty + 10, math.min(8, fillW - sx), 12)
    end

    local kx = math.floor((tx + 8 + fillW - 14) / 2) * 2
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", kx + 4, ty - 2 + 4, 28, th + 4)
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.button_primary:draw(kx, ty - 6 - math.floor(g * 2) * 2, 28, th + 8, 2)
    Text.print(string.format("%3d%%", math.floor(self.value * 100 + 0.5)), self.x + self.w, self.y + 22, 3, Pal.C, "right", Pal.N)
end

local Selector = {}
Selector.__index = Selector
W.Selector = Selector

function Selector.new(o)
    local s = setmetatable(o, Selector)
    s.h = 64
    s.glow = Spring.new(0, 250, 18)

    s.arrowL, s.arrowR = Spring.new(0, 900, 60), Spring.new(0, 900, 60)
    return s
end

function Selector:boxRect() return self.x + self.w - 520, self.y + 4, 520, 56 end

function Selector:update(dt, mx, my)
    local over = U.inRect(mx, my, self.x, self.y, self.w, self.h)
    self.glow.target = (over or self.focus) and 1 or 0
    self.glow:update(dt); self.arrowL:update(dt); self.arrowR:update(dt)
end

function Selector:step(d)
    if self.disabled then return end
    local n = #self.options
    self.index = (self.index - 1 + d) % n + 1
    if d < 0 then self.arrowL:kick(-260) else self.arrowR:kick(260) end
    Audio.play("ui_click", d < 0 and 0.9 or 1.1)
    if self.onChange then self.onChange(self.index, self.options[self.index]) end
end

function Selector:mousepressed(mx, my, b)
    if b ~= 1 then return false end
    local bx, by, bw, bh = self:boxRect()
    if U.inRect(mx, my, bx, by, bw / 2, bh) then self:step(-1); return true end
    if U.inRect(mx, my, bx + bw / 2, by, bw / 2, bh) then self:step(1); return true end
    return false
end

function Selector:mousereleased() end

local function arrow(x, y, dir, col)
    Pal.set(col)
    for i = 0, 4 do
        local h = (5 - i) * 4
        love.graphics.rectangle("fill", x + dir * i * 4 - (dir < 0 and 4 or 0), y - h, 4, h * 2)
    end
end

function Selector:draw()
    local g = self.glow.x
    local labelCol = self.disabled and Pal.I or (g > 0.5 and Pal.C or Pal.B)
    Text.print(self.label, self.x + 24 + g * 8, self.y + 22, 3, labelCol, "left", Pal.N)
    local bx, by, bw, bh = self:boxRect()
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.panel_small:draw(bx, by, bw, bh, 2)
    local cy = by + bh / 2
    local col = self.disabled and Pal.I or Pal.C
    arrow(bx + 28 + math.floor(self.arrowL.x / 2) * 2, cy, -1, col)
    arrow(bx + bw - 28 + math.floor(self.arrowR.x / 2) * 2, cy, 1, col)
    Text.print(self.options[self.index], bx + bw / 2, cy - 10, 3, col, "center", Pal.N)
end

local Toggle = {}
Toggle.__index = Toggle
W.Toggle = Toggle

function Toggle.new(o)
    local t = setmetatable(o, Toggle)
    t.h = 64
    t.glow = Spring.new(0, 250, 18)
    t.pop = Spring.new(1, 600, 22)
    return t
end

function Toggle:boxRect() return self.x + self.w - 520, self.y + 4, 56, 56 end

function Toggle:update(dt, mx, my)
    self.over = U.inRect(mx, my, self.x, self.y, self.w, self.h)
    self.glow.target = (self.over or self.focus) and 1 or 0
    self.glow:update(dt); self.pop:update(dt)
end

function Toggle:activate()
    self.value = not self.value
    self.pop:kick(self.value and 9 or -6)
    Audio.play("ui_click", self.value and 1.15 or 0.9)
    if self.onChange then self.onChange(self.value) end
end
function Toggle:step() self:activate() end

function Toggle:mousepressed(mx, my, b)
    if b ~= 1 or not U.inRect(mx, my, self.x, self.y, self.w, self.h) then return false end
    self:activate()
    return true
end
function Toggle:mousereleased() end

local TICK = { { 0, 3 }, { 1, 4 }, { 2, 5 }, { 3, 4 }, { 4, 3 }, { 5, 2 }, { 6, 1 }, { 7, 0 } }

function Toggle:draw()
    local g = self.glow.x
    Text.print(self.label, self.x + 24 + g * 8, self.y + 22, 3, g > 0.5 and Pal.C or Pal.B, "left", Pal.N)
    local bx, by, bw, bh = self:boxRect()
    local k = self.pop.x
    local cx, cy = bx + bw / 2, by + bh / 2
    love.graphics.push()
    love.graphics.translate(cx, cy); love.graphics.scale(k, k); love.graphics.translate(-cx, -cy)
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.panel_small:draw(bx, by, bw, bh, 2)
    if self.value then
        for _, p in ipairs(TICK) do
            Pal.set(Pal.N); love.graphics.rectangle("fill", bx + 12 + p[1] * 4 + 2, by + 14 + p[2] * 4 + 2, 8, 8)
        end
        for _, p in ipairs(TICK) do
            Pal.set(Pal.C); love.graphics.rectangle("fill", bx + 12 + p[1] * 4, by + 14 + p[2] * 4, 8, 8)
        end
    end
    love.graphics.pop()
    local cap = self.value and self.captionOn or self.captionOff
    if cap then Text.print(cap, bx + bw + 24, by + 20, 2, self.value and Pal.C or Pal.I, "left") end
end

local Focus = {}
Focus.__index = Focus
W.Focus = Focus

function Focus.new(items) return setmetatable({ items = items, index = 0 }, Focus) end

function Focus:set(i)
    for j, it in ipairs(self.items) do it.focus = (j == i) end
    self.index = i
end

function Focus:clearIfMouse()
    if self.index ~= 0 then self:set(0) end
end

function Focus:keypressed(key)
    local n = #self.items
    if n == 0 then return false end
    local function move(d)
        local i = self.index
        for _ = 1, n do
            i = (i - 1 + d) % n + 1
            if i < 1 then i = n end
            if not self.items[i].disabled then break end
        end
        self:set(i)
    end
    if key == "down" or key == "s" or key == "tab" then move(1); return true end
    if key == "up" or key == "w" then
        if self.index == 0 then self:set(n + 1 > n and n or 1) else move(-1) end
        return true
    end
    local it = self.items[self.index]
    if not it then return false end
    if key == "return" or key == "kpenter" or key == "space" then
        if it.activate then it:activate() elseif it.step then it:step(1) end
        return true
    end
    if key == "left" or key == "a" then
        if it.nudge then it:nudge(-0.05) elseif it.step then it:step(-1) end
        return true
    end
    if key == "right" or key == "d" then
        if it.nudge then it:nudge(0.05) elseif it.step then it:step(1) end
        return true
    end
    return false
end

return W
