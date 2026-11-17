local Spring = {}
Spring.__index = Spring

local STEP = 1 / 240

function Spring.new(x, k, d)
    return setmetatable({ x = x or 0, v = 0, target = x or 0, k = k or 200, d = d or 20, acc = 0 }, Spring)
end

function Spring:update(dt)
    if dt > 0.1 then dt = 0.1 end
    local acc = self.acc + dt
    local x, v, t, k, d = self.x, self.v, self.target, self.k, self.d
    while acc >= STEP do
        v = v + (-k * (x - t) - d * v) * STEP
        x = x + v * STEP
        acc = acc - STEP
    end
    self.x, self.v, self.acc = x, v, acc
    return x
end

function Spring:snap(x)
    self.x, self.target, self.v = x, x, 0
end

function Spring:kick(v) self.v = self.v + v end

function Spring:settled(eps)
    eps = eps or 0.01
    return math.abs(self.x - self.target) < eps and math.abs(self.v) < eps * 10
end

return Spring
