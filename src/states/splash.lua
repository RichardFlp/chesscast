local Config = require("src.config")
local M = require("src.states.manager")
local Screen = require("src.utils.screen")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Frame = require("src.ui.frame")

local Splash = {}
local WORD = Config.app.studio
local CONTRIBUTOR = Config.app.contributor
local SPLASH = Config.ui.splash
local T_IN, T_HOLD, T_END = 0.07, SPLASH.hold, SPLASH.hold + SPLASH.fade

local WORD_K = 8
local CREDIT_K = 2
local CREDIT_Y = 628
local CREDIT_AND = "AND "
local CREDIT_TEXT = CONTRIBUTOR and (CREDIT_AND .. CONTRIBUTOR) or nil
local CREDIT_LEN = CREDIT_TEXT and #CREDIT_TEXT or 0
local T_CREDIT = 2.35
local T_STEP = 0.05
local T_CURSOR = 1.95
local T_CURSOR_END = T_CREDIT + CREDIT_LEN * T_STEP + 0.4

local BLOCK = 16
local CORE_Y = 540
local PULL = 0.32

local function buildBlocks()
    local cx, cy = Screen.W / 2, CORE_Y
    local wordW = Text.width(WORD, WORD_K)
    local madeW = Text.width("MADE BY", 3)
    local bands = {
        { cx - madeW / 2, 448, madeW, 44 },
        { cx - wordW / 2, 498, wordW, 104 },
        { cx - wordW / 2, 652, wordW, 20 },
    }
    if CONTRIBUTOR then
        local credW = Text.width(CREDIT_TEXT, CREDIT_K)
        bands[#bands + 1] = { cx - credW / 2, 612, credW, 32 }
    end
    local rng = love.math.newRandomGenerator(1919)
    local blocks, seen, far = {}, {}, 1
    for _, b in ipairs(bands) do
        for gy = math.floor(b[2] / BLOCK), math.ceil((b[2] + b[4]) / BLOCK) - 1 do
            for gx = math.floor(b[1] / BLOCK), math.ceil((b[1] + b[3]) / BLOCK) - 1 do
                local key = gx .. ":" .. gy
                if not seen[key] then
                    seen[key] = true
                    local x, y = gx * BLOCK, gy * BLOCK
                    local dx, dy = x + BLOCK / 2 - cx, y + BLOCK / 2 - cy
                    local d = math.sqrt(dx * dx + dy * dy)
                    blocks[#blocks + 1] = {
                        x = x, y = y, dist = d,
                        col = rng:random() < 0.3 and Pal.B or Pal.C,
                        delay = 0,
                    }
                    if d > far then far = d end
                end
            end
        end
    end
    for _, b in ipairs(blocks) do
        b.delay = (1 - b.dist / far) * 0.32 + rng:random() * 0.06
    end
    return blocks
end

function Splash:enter()
    self.t = 0
    self.done = false
    self.cw = CREDIT_TEXT and Text.width(CREDIT_TEXT, CREDIT_K) or 0
    self.blocks = buildBlocks()
end

local function finish(self)
    if self.done then return end
    self.done = true
    M.switch("menu")
end

function Splash:update(dt)
    self.t = self.t + dt
    if self.t >= T_END then finish(self) end
end

local function drawCredit(self, cx, t)
    if not CREDIT_TEXT then return end
    local x = cx - self.cw / 2
    local shown, reveal = 0, x
    for i = 1, CREDIT_LEN do
        local ch = CREDIT_TEXT:sub(i, i)
        local w = Text.width(ch, CREDIT_K)
        local ct = t - T_CREDIT - (i - 1) * T_STEP
        if ct > 0 then
            local p = math.min(1, ct / 0.16)
            local col = (i <= #CREDIT_AND) and Pal.B or Pal.C
            Text.print(ch, x + w / 2, CREDIT_Y, CREDIT_K, col, "center", nil, p)
            shown = i
            reveal = x + w
        end
        x = x + w
    end

    if t >= T_CURSOR and t < T_CURSOR_END then
        local typing = shown > 0 and shown < CREDIT_LEN
        if typing or (math.floor(t * 6) % 2 == 0) then
            local cur = (shown == 0) and (cx - self.cw / 2 - 12) or reveal
            Pal.set(Pal.C, 0.9)
            love.graphics.rectangle("fill", math.floor(cur / 2) * 2, CREDIT_Y - 2, 8, 16)
        end
    end

end

local function drawCollapse(self, t)
    local p = t - T_HOLD
    if p < 0 then return end
    local cx, cy = Screen.W / 2, CORE_Y
    local blocks = self.blocks
    for i = 1, #blocks do
        local b = blocks[i]
        local bt = p - b.delay
        if bt >= 0 then
            Pal.set(Pal.N)
            love.graphics.rectangle("fill", b.x, b.y, BLOCK, BLOCK)
            local u = bt / PULL
            if u < 1 then
                local e = u * u
                local x = b.x + (cx - BLOCK / 2 - b.x) * e
                local y = b.y + (cy - BLOCK / 2 - b.y) * e
                local s = math.max(4, math.floor(BLOCK * (1 - 0.7 * u) / 2) * 2)
                local a = u > 0.7 and (1 - (u - 0.7) / 0.3) or 1
                Pal.set(u > 0.5 and Pal.C or b.col, a)
                love.graphics.rectangle("fill",
                    math.floor((x + (BLOCK - s) / 2) / 2) * 2,
                    math.floor((y + (BLOCK - s) / 2) / 2) * 2, s, s)
            end
        end
    end

    local cp = math.max(0, math.min(1, (p - 0.22) / 0.3))
    if cp > 0 then
        local r = 4 + math.floor(20 * cp + math.sin(p * 42) * 3)
        Frame.diamond(cx, cy, r + 7, Pal.N)
        Frame.diamond(cx, cy, r, Pal.C)
        Frame.diamond(cx, cy, math.floor(r * 0.45), Pal.B)
    end

    local fp = (p - 0.55) / 0.25
    if fp > 0 and fp < 1 then
        Pal.set(Pal.C, math.sin(fp * math.pi) * 0.7)
        love.graphics.rectangle("fill", 0, 0, Screen.W, Screen.H)
    end
end

function Splash:draw()
    local t = self.t
    Pal.set(Pal.N); love.graphics.rectangle("fill", 0, 0, Screen.W, Screen.H)
    local cx = Screen.W / 2

    local a = math.min(1, t / 0.5)
    local ease = 1 - (1 - a) ^ 3
    Text.print("MADE BY", cx, 470 - (1 - ease) * 60, 3, Pal.B, "center", nil, a)

    local k = WORD_K
    local total = Text.width(WORD, k)
    local x = cx - total / 2
    for i = 1, #WORD do
        local ch = WORD:sub(i, i)
        local lt = t - 0.5 - (i - 1) * T_IN
        local w = Text.width(ch, k)
        if lt > 0 then
            local p = math.min(1, lt / 0.35)
            local bounce = math.abs(math.sin(p * math.pi * 1.5)) * (1 - p) * 90
            local col = (lt < 0.12) and Pal.C or (i % 2 == 0 and Pal.C or Pal.B)
            Text.print(ch, x + w / 2, Screen.H / 2 - bounce, k, col, "center", Pal.I)
        end
        x = x + w
    end

    drawCredit(self, cx, t)
    drawCollapse(self, t)
end

local function skip(self)
    if self.done or self.t < SPLASH.skipAfter then return end
    finish(self)
end

function Splash:keypressed() skip(self) end
function Splash:mousepressed() skip(self) end

return Splash
