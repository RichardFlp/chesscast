local Config = require("src.config")
local Screen = require("src.utils.screen")
local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local U = require("src.utils.util")

local CardTip = {}

local lg = love.graphics
local max = math.max
local C = Config.ui.cardtip

local function lines(def)
    if not def._lines then def._lines = Text.lines(def.desc, 2, C.width - 40) end
    return def._lines
end

function CardTip.size(def, reason)
    local w = max(C.width, Text.width(def.name, 3) + 92)
    local h = C.heightBase + #lines(def) * C.lineHeight + (reason and C.reasonHeight or 0)
    return w, h
end

function CardTip.draw(def, x, y, reason)
    local w, h = CardTip.size(def, reason)
    Pal.set(Pal.N, 0.8)
    lg.rectangle("fill", x + 8, y + 8, w, h)
    lg.setColor(1, 1, 1, 1)
    A.ui.tooltip:draw(x, y, w, h, 2)
    local role = def.role
    Text.print(def.name, x + 20, y + 20, 3, role and Pal.RL or Pal.C, "left", role and Pal.RD or Pal.N)
    Text.print(role and "ROLE" or def.school, x + 20, y + 54, 2, role and Pal.R or Pal.B, "left")
    local cx = x + w - 34
    Frame.diamond(cx, y + 30, 16, role and Pal.RD or Pal.N)
    Frame.diamond(cx, y + 30, 12, role and Pal.R or Pal.B)
    Text.print(tostring(def.cost), cx + 1, y + 23, 2, role and Pal.RL or Pal.C, "center")
    if def.endsTurn then Text.print("ENDS TURN", x + w - 20, y + 54, 2, role and Pal.R or Pal.C, "right") end
    for i, l in ipairs(lines(def)) do
        Text.print(l, x + 20, y + 84 + (i - 1) * Config.ui.cardtip.lineHeight, 2, Pal.C, "left")
    end
    if reason then
        Text.print(reason, x + 20, y + 90 + #lines(def) * Config.ui.cardtip.lineHeight, 2, Pal.B, "left")
    end
end

function CardTip.drawAtMouse(def, mx, my)
    local w, h = CardTip.size(def)
    local C = Config.ui.cardtip
    local x = mx + C.gap
    if x + w > Screen.W - C.edge then x = mx - C.gap - w end
    local y = U.clamp(my - h - 12, C.edge, Screen.H - C.edge - h)
    CardTip.draw(def, math.floor(x), math.floor(y))
end

return CardTip
