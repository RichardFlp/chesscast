local Config = require("src.config")

local NineSlice = {}
NineSlice.__index = NineSlice

local floor = math.floor

function NineSlice.new(image, l, t, r, b)
    local w, h = image:getDimensions()
    local self = setmetatable({ image = image, l = l, t = t, r = r, b = b, w = w, h = h }, NineSlice)
    local xs = { 0, l, w - r, w }
    local ys = { 0, t, h - b, h }
    self.quads = {}
    for j = 1, 3 do
        for i = 1, 3 do
            local qw, qh = xs[i + 1] - xs[i], ys[j + 1] - ys[j]
            if qw > 0 and qh > 0 then
                self.quads[(j - 1) * 3 + i] = love.graphics.newQuad(xs[i], ys[j], qw, qh, w, h)
            end
        end
    end
    self.xs, self.ys = xs, ys
    return self
end

function NineSlice:draw(x, y, w, h, s)
    s = s or Config.ui.scale
    x, y = floor(x / s + 0.5) * s, floor(y / s + 0.5) * s
    w, h = floor(w / s + 0.5) * s, floor(h / s + 0.5) * s
    local l, t, r, b = self.l * s, self.t * s, self.r * s, self.b * s
    local minW, minH = l + r, t + b
    if w < minW then w = minW end
    if h < minH then h = minH end
    local cw, ch = w - l - r, h - t - b
    local centerW, centerH = self.w - self.l - self.r, self.h - self.t - self.b
    local centerSW, centerSH = cw / centerW, ch / centerH
    local x1, x2, x3 = x, x + l, x + w - r
    local y1, y2, y3 = y, y + t, y + h - b
    local q = self.quads
    local draw = love.graphics.draw
    local img = self.image

    if q[1] then draw(img, q[1], x1, y1, 0, s, s) end
    if q[2] and cw > 0 then draw(img, q[2], x2, y1, 0, centerSW, s) end
    if q[3] then draw(img, q[3], x3, y1, 0, s, s) end
    if ch > 0 then
        if q[4] then draw(img, q[4], x1, y2, 0, s, centerSH) end
        if q[5] and cw > 0 then draw(img, q[5], x2, y2, 0, centerSW, centerSH) end
        if q[6] then draw(img, q[6], x3, y2, 0, s, centerSH) end
    end
    if q[7] then draw(img, q[7], x1, y3, 0, s, s) end
    if q[8] and cw > 0 then draw(img, q[8], x2, y3, 0, centerSW, s) end
    if q[9] then draw(img, q[9], x3, y3, 0, s, s) end
end

return NineSlice
