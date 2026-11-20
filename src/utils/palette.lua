local Pal = {}

local function hex(h)
    return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, 1 }
end

Pal.N = hex("#112E81")
Pal.I = hex("#4647AE")
Pal.B = hex("#4382DF")
Pal.C = hex("#AACCD6")
Pal.RD = hex("#70121E")
Pal.R = hex("#C4242C")
Pal.RL = hex("#ECD8C6")
Pal.K = hex("#000000")

local setColor = love.graphics and love.graphics.setColor

function Pal.set(c, a)
    setColor(c[1], c[2], c[3], a or 1)
end

return Pal
