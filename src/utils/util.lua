local U = {}

function U.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.round(x) return math.floor(x + 0.5) end
function U.sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
function U.inRect(px, py, x, y, w, h) return px >= x and py >= y and px < x + w and py < y + h end

function U.approach(cur, target, rate, dt)
    return target + (cur - target) * math.exp(-rate * dt)
end

function U.shuffle(t, rng)
    rng = rng or love.math.random
    for i = #t, 2, -1 do
        local j = rng(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function U.copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

function U.formatClock(sec)
    if sec < 0 then sec = 0 end
    if sec < 10 then
        return string.format("0:%04.1f", sec)
    end
    local s = math.ceil(sec)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

return U
