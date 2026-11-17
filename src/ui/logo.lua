local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")

local Logo = {}

local function drawWord(str, cx, y, k, t, phase)
    local f = A.font[1]
    love.graphics.setFont(f)
    local w = f:getWidth(str) * k
    local x = math.floor((cx - w / 2) / 2) * 2
    local top = Text.capTop(1) * k
    local h = k / 2
    for i = 1, #str do
        local ch = str:sub(i, i)
        local bob = math.floor(math.sin(t * 2.2 + i * 0.6 + phase) * 1.4 + 0.5) * h
        local ly = y + bob - top

        Pal.set(Pal.N)
        for dx = -1, 1 do
            for dy = -1, 4 do
                love.graphics.print(ch, x + dx * h, ly + dy * h, 0, k, k)
            end
        end
        Pal.set(Pal.I)
        love.graphics.print(ch, x, ly + k, 0, k, k)
        love.graphics.print(ch, x, ly + h, 0, k, k)
        Pal.set(Pal.C)
        love.graphics.print(ch, x, ly, 0, k, k)

        love.graphics.setScissor(x - k, y + bob + 4 * k, 10 * k, 3 * k)
        Pal.set(Pal.B)
        love.graphics.print(ch, x, ly, 0, k, k)
        love.graphics.setScissor()
        x = x + f:getWidth(ch) * k
    end
    return w
end

local function rune(cx, cy, t, phase)
    local p = math.floor((math.sin(t * 3 + phase) * 0.5 + 0.5) * 2.99) * 4
    local r = 24 + p
    local function dia(rr, col)
        Pal.set(col)
        love.graphics.polygon("fill", cx, cy - rr, cx + rr, cy, cx, cy + rr, cx - rr, cy)
    end
    dia(r + 7, Pal.N)
    dia(r, Pal.C)
    dia(r * 0.45, Pal.B)
end

function Logo.draw(cx, y, t)
    local k1, k2 = 16, 8
    drawWord("CHESS", cx, y, k1, t, 0)
    local y2 = y + 7 * k1 + 44
    local w2 = drawWord("CAST", cx, y2, k2, t, 2.5)
    local ry = y2 + 7 * k2 / 2
    rune(math.floor((cx - w2 / 2 - 64) / 2) * 2, ry, t, 0)
    rune(math.floor((cx + w2 / 2 + 56) / 2) * 2, ry, t, 1.6)
    return y2 + 7 * k2 + 16
end

return Logo
