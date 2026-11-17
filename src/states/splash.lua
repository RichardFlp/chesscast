local M = require("src.states.manager")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")

local Splash = {}
local WORD = "FUNERALPIXELS"
local T_IN, T_HOLD, T_END = 0.07, 2.6, 3.4

function Splash:enter() self.t = 0; self.done = false end

local function finish(self)
    if self.done then return end
    self.done = true
    M.switch("menu")
end

function Splash:update(dt)
    self.t = self.t + dt
    if self.t >= T_END then finish(self) end
end

function Splash:draw()
    local t = self.t
    Pal.set(Pal.N); love.graphics.rectangle("fill", 0, 0, 1920, 1080)
    local cx = 960

    local a = math.min(1, t / 0.5)
    local ease = 1 - (1 - a) ^ 3
    Text.print("MADE BY", cx, 470 - (1 - ease) * 60, 3, Pal.B, "center", nil, a)

    local k = 8
    local total = Text.width(WORD, k)
    local x = cx - total / 2
    for i = 1, #WORD do
        local ch = WORD:sub(i, i)
        local lt = t - 0.5 - (i - 1) * T_IN
        local w = Text.width(ch, k)
        if lt > 0 then
            local p = math.min(1, lt / 0.35)
            local bounce = math.abs(math.sin(p * math.pi * 1.5)) * (1 - p) * 90
            local col = (lt < 0.12) and Pal.C or (i % 2 == 0 and Pal.C or Pal.B)
            Text.print(ch, x + w / 2, 540 - bounce, k, col, "center", Pal.I)
        end
        x = x + w
    end

    local bt = math.max(0, math.min(1, (t - 1.6) / 0.6))
    local half = (total / 2) * (1 - (1 - bt) ^ 3)
    Pal.set(Pal.I); love.graphics.rectangle("fill", cx - half, 660, half * 2, 8)

    if bt >= 1 then
        local sp = ((t - 2.2) * 1.2) % 1
        Pal.set(Pal.C); love.graphics.rectangle("fill", math.floor((cx - total / 2 + sp * total) / 8) * 8, 660, 24, 8)
    end

    if t > T_HOLD then
        Pal.set(Pal.N, math.min(1, (t - T_HOLD) / (T_END - T_HOLD)))
        love.graphics.rectangle("fill", 0, 0, 1920, 1080)
    end
end

function Splash:keypressed() finish(self) end
function Splash:mousepressed() finish(self) end

return Splash
