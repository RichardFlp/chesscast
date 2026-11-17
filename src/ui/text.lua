local A = require("src.assets.assets")
local Pal = require("src.utils.palette")

local Text = {}
local floor = math.floor

function Text.font(k) return A.font[k] or A.font[2] end

local capTop = {}
function Text.init()
    for k, f in pairs(A.font) do
        local top = 0
        local ok, r = pcall(love.font.newTrueTypeRasterizer,
            "assets/fonts/PixelEmulator-xq08.ttf", A.FONT_SIZES[k], "mono", 1)
        if ok then
            local _, by = r:getGlyphData("H"):getBearing()
            top = f:getBaseline() - by
        end
        capTop[k] = top
    end
end

function Text.capTop(k) return capTop[k] or 0 end

function Text.width(s, k) return Text.font(k):getWidth(s) end
function Text.height(k) return 7 * k end

function Text.print(s, x, y, k, col, align, shadow, alpha)
    local f = Text.font(k)
    love.graphics.setFont(f)
    local w = f:getWidth(s)
    if align == "center" then x = x - w / 2 elseif align == "right" then x = x - w end
    x, y = floor(x / k + 0.5) * k, floor(y + 0.5)

    local top = y - (capTop[k] or 0)
    if shadow then
        Pal.set(shadow, alpha)
        love.graphics.print(s, x + k, top + k)
    end
    Pal.set(col or Pal.C, alpha)
    love.graphics.print(s, x, top)
    return w
end

function Text.wrap(s, x, y, k, col, width, lineGap, align, alpha)
    local f = Text.font(k)
    local _, lines = f:getWrap(s, width)
    local lh = 7 * k + (lineGap or 3 * k)
    for i, line in ipairs(lines) do
        local lx = x
        if align == "center" then lx = x + width / 2 end
        Text.print(line, lx, y + (i - 1) * lh, k, col, align, nil, alpha)
    end
    return #lines, #lines * lh - (lineGap or 3 * k)
end

function Text.lines(s, k, width)
    local _, lines = Text.font(k):getWrap(s, width)
    return lines
end

return Text
