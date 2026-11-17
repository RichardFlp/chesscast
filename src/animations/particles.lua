local A = require("src.assets.assets")
local Pal = require("src.utils.palette")

local Particles = {}
Particles.__index = Particles

local floor, random, sin, cos, pi = math.floor, love.math.random, math.sin, math.cos, math.pi

function Particles.new(max)
    local p = setmetatable({ max = max or 2048, n = 0 }, Particles)
    p.x, p.y, p.vx, p.vy, p.life, p.age, p.size, p.col, p.grav, p.drag, p.kind = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
    p.batch = love.graphics.newSpriteBatch(A.pixel, p.max, "stream")
    p.intensity = 1
    return p
end

function Particles:add(x, y, vx, vy, life, size, col, grav, drag, kind)
    local i = self.n + 1
    if i > self.max then
        i = random(self.max)
    else
        self.n = i
    end
    self.x[i], self.y[i], self.vx[i], self.vy[i] = x, y, vx, vy
    self.life[i], self.age[i], self.size[i], self.col[i] = life, 0, size or 4, col or Pal.C
    self.grav[i], self.drag[i], self.kind[i] = grav or 0, drag or 0, kind or 0
end

function Particles:burst(x, y, count, speed, cols, life, size, grav)
    count = math.floor(count * self.intensity + 0.5)
    for _ = 1, count do
        local a = random() * pi * 2
        local s = speed * (0.3 + random() * 0.7)
        self:add(x, y, cos(a) * s, sin(a) * s, (life or 0.8) * (0.5 + random() * 0.5),
            (size or 4) * (random() < 0.3 and 2 or 1), cols[random(#cols)], grav or 0, 2.5, 0)
    end
end

function Particles:sparkle(x, y, w, h, count, cols, speed)
    count = math.floor(count * self.intensity + 0.5)
    for _ = 1, count do
        self:add(x + random() * w, y + random() * h, (random() - 0.5) * 40, -(speed or 60) * (0.5 + random()),
            0.6 + random() * 0.8, random() < 0.25 and 6 or 4, cols[random(#cols)], -20, 1, 1)
    end
end

function Particles:update(dt)
    local i = 1
    local x, y, vx, vy, life, age, size, col, grav, drag, kind =
        self.x, self.y, self.vx, self.vy, self.life, self.age, self.size, self.col, self.grav, self.drag, self.kind
    while i <= self.n do
        age[i] = age[i] + dt
        if age[i] >= life[i] then
            local n = self.n
            x[i], y[i], vx[i], vy[i], life[i], age[i], size[i], col[i], grav[i], drag[i], kind[i] =
                x[n], y[n], vx[n], vy[n], life[n], age[n], size[n], col[n], grav[n], drag[n], kind[n]
            self.n = n - 1
        else
            local d = 1 - drag[i] * dt
            if d < 0 then d = 0 end
            vx[i] = vx[i] * d
            vy[i] = (vy[i] + grav[i] * dt) * d
            x[i] = x[i] + vx[i] * dt
            y[i] = y[i] + vy[i] * dt
            i = i + 1
        end
    end
end

function Particles:draw()
    local b = self.batch
    b:clear()
    local x, y, life, age, size, col, kind = self.x, self.y, self.life, self.age, self.size, self.col, self.kind
    for i = 1, self.n do
        local t = age[i] / life[i]
        local c = col[i]
        local a = 1 - t * t
        local s = size[i]
        if kind[i] == 1 then

            if t > 0.5 then s = 2 end
            a = (floor(age[i] * 20) % 3 == 0) and a * 0.4 or a
        elseif t > 0.6 and s > 2 then
            s = s - 2
        end
        b:setColor(c[1], c[2], c[3], a)
        b:add(floor(x[i] / 2) * 2 - s / 2, floor(y[i] / 2) * 2 - s / 2, 0, s, s)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(b)
end

function Particles:clear() self.n = 0 end

return Particles
