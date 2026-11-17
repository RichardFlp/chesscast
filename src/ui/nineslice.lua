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
    s = s or 2
    x, y = floor(x / s + 0.5) * s, floor(y / s + 0.5) * s
    w, h = floor(w / s + 0.5) * s, floor(h / s + 0.5) * s
    local l, t, r, b = self.l * s, self.t * s, self.r * s, self.b * s
    local minW, minH = l + r, t + b
    if w < minW then w = minW end
    if h < minH then h = minH end
    local cw, ch = w - l - r, h - t - b
    local dx = { x, x + l, x + w - r }
    local dy = { y, y + t, y + h - b }
    local sw = { s, cw / (self.w - self.l - self.r), s }
    local sh = { s, ch / (self.h - self.t - self.b), s }
    local img, q = self.image, self.quads
    local draw = love.graphics.draw
    for j = 1, 3 do
        for i = 1, 3 do
            local quad = q[(j - 1) * 3 + i]
            if quad and (i ~= 2 or cw > 0) and (j ~= 2 or ch > 0) then
                draw(img, quad, dx[i], dy[j], 0, sw[i], sh[j])
            end
        end
    end
end

return NineSlice
