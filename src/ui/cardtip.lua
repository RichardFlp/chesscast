local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local U = require("src.utils.util")

local CardTip = {}

local lg = love.graphics
local max = math.max
local COST_STR = { [0] = "0", "1", "2", "3" }

local function lines(def)
    if not def._lines then def._lines = Text.lines(def.desc, 2, 300) end
    return def._lines
end

function CardTip.size(def, reason)

    local w = max(340, Text.width(def.name, 3) + 92)
    local h = 112 + #lines(def) * 22 + (reason and 30 or 0)
    return w, h
end

function CardTip.draw(def, x, y, reason)
    local w, h = CardTip.size(def, reason)
    Pal.set(Pal.N, 0.8)
    lg.rectangle("fill", x + 8, y + 8, w, h)
    lg.setColor(1, 1, 1, 1)
    A.ui.tooltip:draw(x, y, w, h, 2)
    Text.print(def.name, x + 20, y + 20, 3, Pal.C, "left", Pal.N)
    Text.print(def.school, x + 20, y + 54, 2, Pal.B, "left")
    local cx = x + w - 34
    Frame.diamond(cx, y + 30, 16, Pal.N)
    Frame.diamond(cx, y + 30, 12, Pal.B)
    Text.print(COST_STR[def.cost], cx + 1, y + 23, 2, Pal.C, "center")
    if def.endsTurn then Text.print("ENDS TURN", x + w - 20, y + 54, 2, Pal.C, "right") end
    for i, l in ipairs(lines(def)) do
        Text.print(l, x + 20, y + 84 + (i - 1) * 22, 2, Pal.C, "left")
    end
    if reason then
        Text.print(reason, x + 20, y + 90 + #lines(def) * 22, 2, Pal.B, "left")
    end
end

function CardTip.drawAtMouse(def, mx, my)
    local w, h = CardTip.size(def)
    local x = mx + 24
    if x + w > 1904 then x = mx - 24 - w end
    local y = U.clamp(my - h - 12, 16, 1064 - h)
    CardTip.draw(def, math.floor(x), math.floor(y))
end

return CardTip
