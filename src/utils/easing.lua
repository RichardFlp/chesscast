local E = {}

function E.linear(t) return t end
function E.inQuad(t) return t * t end
function E.outQuad(t) return 1 - (1 - t) * (1 - t) end
function E.inOutQuad(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end
function E.outCubic(t) return 1 - (1 - t) ^ 3 end
function E.inCubic(t) return t * t * t end
function E.inOutCubic(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end

local c1, c3 = 1.70158, 2.70158
function E.outBack(t) return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2 end
function E.inBack(t) return c3 * t * t * t - c1 * t * t end

function E.outElastic(t)
    if t <= 0 then return 0 elseif t >= 1 then return 1 end
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end

function E.outBounce(t)
    local n, d = 7.5625, 2.75
    if t < 1 / d then return n * t * t
    elseif t < 2 / d then t = t - 1.5 / d; return n * t * t + 0.75
    elseif t < 2.5 / d then t = t - 2.25 / d; return n * t * t + 0.9375
    else t = t - 2.625 / d; return n * t * t + 0.984375 end
end

return E
