local Config = require("src.config")
local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Spring = require("src.utils.spring")
local Audio = require("src.audio.audio")
local U = require("src.utils.util")

local Button = {}
Button.__index = Button

function Button.new(o)
    local b = setmetatable(o, Button)
    b.h = b.h or Config.ui.button.height
    b.w = b.w or Config.ui.button.width
    b.textScale = b.textScale or Config.ui.button.textScale
    b.style = b.style or "secondary"
    b.hover, b.pressed, b.focus = false, false, false
    b.sx = Spring.new(0, 260, 16)
    b.sy = Spring.new(0, 260, 16)
    b.ss = Spring.new(1, 300, 14)
    b.mark = Spring.new(0, 200, 18)
    b.t = love.math.random() * 10
    b.hoverShift = b.hoverShift or Config.ui.button.hoverShift
    return b
end

function Button:contains(mx, my)
    return U.inRect(mx, my, self.x, self.y, self.w, self.h)
end

function Button:update(dt, mx, my)
    self.t = self.t + dt
    local over = not self.disabled and self:contains(mx, my)
    local active = over or self.focus
    if active and not self.hover then
        Audio.play("ui_hover", 0.95 + love.math.random() * 0.1)
        self.ss:kick(1.2)
    end
    self.hover = active
    self.sx.target = active and self.hoverShift or 0
    self.sy.target = active and -4 or 0
    self.mark.target = active and 1 or 0
    if self.pressed then self.sy.target = 2 end
    self.sx:update(dt); self.sy:update(dt); self.ss:update(dt); self.mark:update(dt)
end

function Button:mousepressed(mx, my, btn)
    if btn == 1 and not self.disabled and self:contains(mx, my) then
        self.pressed = true
        self.ss:kick(-1.5)
        return true
    end
    return false
end

function Button:mousereleased(mx, my, btn)
    if btn ~= 1 or not self.pressed then return false end
    self.pressed = false
    if self:contains(mx, my) then
        self:activate()
        return true
    end
    return false
end

function Button:activate()
    if self.disabled then return end
    Audio.play(self.backSound and "ui_back" or "ui_click")
    self.ss:kick(2.5)
    if self.onClick then self.onClick(self) end
end

function Button:draw()
    local x = math.floor((self.x + self.sx.x) / 2 + 0.5) * 2
    local y = math.floor((self.y + self.sy.x) / 2 + 0.5) * 2
    local s = self.ss.x
    local w, h = self.w, self.h
    local cx, cy = x + w / 2, y + h / 2
    w = math.floor(w * s / 2 + 0.5) * 2
    h = math.floor(h * (1 + (s - 1) * 0.5) / 2 + 0.5) * 2
    x, y = math.floor((cx - w / 2) / 2 + 0.5) * 2, math.floor((cy - h / 2) / 2 + 0.5) * 2

    Pal.set(Pal.N)
    love.graphics.rectangle("fill", x + 6, y + 6, w, h)

    local face
    if self.disabled then face = A.ui.button_disabled
    elseif self.hover or self.pressed then face = A.ui.button_primary
    else face = self.style == "primary" and A.ui.button_primary or A.ui.button_secondary end
    love.graphics.setColor(1, 1, 1, 1)
    local press = self.pressed and 2 or 0
    face:draw(x, y + press, w, h - press, 2)

    local m = self.mark.x
    if m > 0.02 then
        local mx = x - 28 + (1 - m) * -20
        local my = y + h / 2
        Pal.set(Pal.C, U.clamp(m, 0, 1))
        local bob = math.floor(math.sin(self.t * 6) * 1.5 + 0.5) * 2
        love.graphics.polygon("fill", mx, my - 10 + bob, mx + 10, my + bob, mx, my + 10 + bob, mx - 10, my + bob)
        Pal.set(Pal.N, U.clamp(m, 0, 1))
        love.graphics.rectangle("fill", mx - 2, my - 2 + bob, 4, 4)
    end

    local k = self.textScale
    local tc = self.disabled and Pal.I or Pal.C
    local shadow = (self.hover or self.pressed) and Pal.I or Pal.N
    if self.hover and not self.disabled then tc = Pal.C end
    local ty = y + press + (h - press) / 2 - 7 * k / 2 - (self.tag and 8 or 0) - 2
    Text.print(self.label, x + w / 2, ty, k, tc, "center", shadow)
    if self.tag then
        Text.print(self.tag, x + w / 2, ty + 7 * k + 8, 2, self.disabled and Pal.I or Pal.N, "center")
    end
end

return Button
