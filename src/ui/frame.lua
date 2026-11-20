local Config = require("src.config")
local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")

local Frame = {}
local F = Config.ui.frame

function Frame.panel(x, y, w, h, title)
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", x + F.shadow, y + F.shadow, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.panel_large:draw(x, y, w, h, Config.ui.scale)
    if title then
        local tw = Text.width(title, F.titleScale) + F.titlePad
        local tx = math.floor((x + w / 2 - tw / 2) / 2) * 2
        Pal.set(Pal.N)
        love.graphics.rectangle("fill", tx + F.shadow / 2, y + F.titleY + F.shadow / 2, tw, F.titleH)
        love.graphics.setColor(1, 1, 1, 1)
        A.ui.dialogue:draw(tx, y + F.titleY, tw, F.titleH, Config.ui.scale)
        Text.print(title, x + w / 2, y + F.titleTextY, F.titleScale, Pal.C, "center", Pal.N)
    end
end

function Frame.diamond(cx, cy, r, col)
    Pal.set(col or Pal.C)
    for i = 0, r - 1, 2 do
        love.graphics.rectangle("fill", cx - (r - i), cy - i - 2, (r - i) * 2, 2)
        love.graphics.rectangle("fill", cx - (r - i), cy + i, (r - i) * 2, 2)
    end
end

function Frame.divider(x, y, w)
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.divider_h:draw(x, y, w, 16, 2)
end

return Frame
