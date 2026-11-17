local ok, bit = pcall(require, "bit")
if ok and bit then return bit end

local floor = math.floor

local function band2(a, b)
    if b + 1 == 2 ^ floor(math.log(b + 1) / math.log(2) + 0.5) then return a % (b + 1) end
    local r, k = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + k end
        a, b, k = floor(a / 2), floor(b / 2), k * 2
    end
    return r
end

local B = {}
function B.band(a, b, ...)
    local r = band2(a, b)
    for i = 1, select("#", ...) do r = band2(r, (select(i, ...))) end
    return r
end
function B.bor(a, b)
    local r, k = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then r = r + k end
        a, b, k = floor(a / 2), floor(b / 2), k * 2
    end
    return r
end
function B.rshift(a, n) return floor(a / 2 ^ n) end
function B.lshift(a, n) return a * 2 ^ n end
return B
