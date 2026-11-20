local Config = require("src.config")
local Screen = require("src.utils.screen")
local Pal = require("src.utils.palette")

local T = { a = 0, state = "idle", speed = Config.ui.transitionSpeed, callback = nil }

function T.start(callback)
    if T.state == "out" then return end
    T.state = "out"
    T.callback = callback
end

function T.busy() return T.state == "out" end

function T.update(dt)
    if T.state == "out" then
        T.a = T.a + dt * T.speed
        if T.a >= 1 then
            T.a = 1
            T.state = "in"
            local cb = T.callback
            T.callback = nil
            if cb then cb() end
        end
    elseif T.state == "in" then
        T.a = T.a - dt * T.speed
        if T.a <= 0 then T.a = 0; T.state = "idle" end
    end
end

function T.draw()
    if T.a <= 0 then return end
    Pal.set(Pal.N, T.a)
    love.graphics.rectangle("fill", -16, -16, Screen.W + 32, Screen.H + 32)
end

return T
