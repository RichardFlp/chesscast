local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Screen = require("src.utils.screen")
local Particles = require("src.animations.particles")

local BG = {}

local WAVES = [[
#ifdef GL_ES
#define HP highp
#else
#define HP
#endif
extern Image bayer;
extern float phase;
extern float amp;
extern vec3 ring;
extern float ringPow;
extern float px;
extern float dcell;
extern vec2 off;
extern vec4 cN;
extern vec4 cI;
extern vec4 cB;
extern vec4 cC;

float waves(HP vec2 p, HP float t) {
    HP float h = sin(p.x * 0.0090 + p.y * 0.0035 + t * 0.90);
    h += sin(p.x * -0.0055 + p.y * 0.0100 + t * 1.25) * 0.80;
    h += sin(length((p - vec2(960.0, 1600.0)) * 0.01) * 1.6 - t * 1.60) * 0.60;
    h += sin(p.x * 0.0190 - p.y * 0.0150 - t * 2.10) * 0.35;
    return h / 2.55;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    HP vec2 q = sc * px;
    HP vec2 p = floor(q / 4.0) * 4.0 + 2.0 + off;
    HP vec2 w = vec2(sin(p.y * 0.0060 + phase * 0.70), cos(p.x * 0.0050 - phase * 0.50)) * (36.0 + 24.0 * amp);
    float h = waves(p + w, phase) * amp;
    if (ringPow > 0.001) {
        HP float d = length((p - ring.xy) * 0.01) * 100.0;
        HP float r = min(ring.z, 30.0) * 620.0;
        float band = clamp((d - r) / 150.0, -8.0, 8.0);
        h += sin((d - r) * 0.055) * exp(-band * band) * ringPow * 1.6;
    }
    float v = 0.85 + h * 1.05;
    float th = Texel(bayer, (mod(floor(q / dcell), 4.0) + 0.5) / 4.0).r;
    float lvl = clamp(floor(v + th), 0.0, 3.0);
    if (lvl < 0.5) return cN;
    if (lvl < 1.5) return cI;
    if (lvl < 2.5) return cB;
    return cC;
}
]]

local shader, waveCanvas
local phase, boost = 0, 0
local ring = { -9999, -9999, 99 }
local ringPow = 0
local t = 0
local motes
local MOTE_COLS = { Pal.C, Pal.B, Pal.B, Pal.I }
local pieces = {
    { side = 1, t = 6, x = 150, y = 600, s = 10, ph = 0.0 },
    { side = -1, t = 5, x = 1500, y = 560, s = 10, ph = 1.7 },
    { side = 1, t = 3, x = 80, y = 250, s = 5, ph = 2.4 },
    { side = -1, t = 2, x = 1720, y = 200, s = 5, ph = 0.9 },
    { side = 1, t = 1, x = 400, y = 860, s = 4, ph = 3.1 },
    { side = -1, t = 4, x = 1400, y = 880, s = 4, ph = 4.0 },
}

function BG.init()
    motes = Particles.new(400)
    local ok, sh = pcall(love.graphics.newShader, WAVES)
    if ok then
        shader = sh
        shader:send("bayer", Screen.bayer)
        if Screen.lite then
            waveCanvas = love.graphics.newCanvas(512, 302, { dpiscale = 1 })
            waveCanvas:setFilter("nearest", "nearest")
            shader:send("px", 4); shader:send("dcell", 4); shader:send("off", { -64, -64 })
        else
            shader:send("px", 1); shader:send("dcell", 2); shader:send("off", { 0, 0 })
        end
        shader:send("cN", Pal.N); shader:send("cI", Pal.I)
        shader:send("cB", Pal.B); shader:send("cC", Pal.C)
    else
        print("wave shader unavailable: " .. tostring(sh))
    end
end

function BG.pulse(x, y, strength)
    strength = strength or 1
    boost = math.min(2.5, boost + strength)
    ring[1], ring[2], ring[3] = x, y, 0
    ringPow = math.min(2, ringPow + strength)
end

function BG.update(dt)
    t = t + dt
    phase = phase + dt * (1 + boost * 0.9)

    local k = math.exp(-dt * 1.4)
    boost = boost * k
    ringPow = ringPow * k
    ring[3] = ring[3] + dt
    if love.math.random() < dt * 30 then
        motes:add(love.math.random() * 1920, 1100, (love.math.random() - 0.5) * 20, -30 - love.math.random() * 60,
            6 + love.math.random() * 8, love.math.random() < 0.2 and 6 or 4,
            MOTE_COLS[love.math.random(#MOTE_COLS)], 0, 0, 1)
    end
    motes:update(dt)
end

function BG.draw(dim)
    if shader then
        shader:send("phase", phase)
        shader:send("amp", 1 + boost)
        shader:send("ring", ring)
        shader:send("ringPow", ringPow)
        love.graphics.setColor(1, 1, 1, 1)
        if waveCanvas then
            love.graphics.push("all")
            love.graphics.origin()
            love.graphics.setCanvas(waveCanvas)
            love.graphics.setShader(shader)
            love.graphics.rectangle("fill", 0, 0, 512, 302)
            love.graphics.pop()
            love.graphics.setShader()
            love.graphics.draw(waveCanvas, -64, -64, 0, 4, 4)
        else
            love.graphics.setShader(shader)
            love.graphics.rectangle("fill", -64, -64, 2048, 1208)
        end
        love.graphics.setShader(Screen.shader)
    else
        Pal.set(Pal.I)
        love.graphics.rectangle("fill", -64, -64, 2048, 1208)
        Pal.set(Pal.B, 0.35)
        for i = 0, 8 do
            local y = (i * 130 + phase * 40) % 1300 - 100
            love.graphics.rectangle("fill", 0, math.floor(y / 4) * 4, 1920, 24)
        end
    end

    for i = 0, 5 do
        Pal.set(Pal.N, 0.75 - i * 0.12)
        love.graphics.rectangle("fill", 0, i * 16, 1920, 16)
        love.graphics.rectangle("fill", 0, 1080 - (i + 1) * 16, 1920, 16)
    end

    for _, p in ipairs(pieces) do
        local img = A.piece[p.side][p.t]
        local bob = math.floor(math.sin(t * 0.8 + p.ph) * 6) * 2
        local x, y = p.x - 16 * p.s, p.y - 16 * p.s + bob
        Screen.flat(true)
        Pal.set(Pal.N)
        love.graphics.draw(img, x + p.s * 2, y + p.s * 2, 0, p.s, p.s)
        Pal.set(Pal.B)
        love.graphics.draw(img, x - p.s, y - p.s, 0, p.s, p.s)
        Pal.set(Pal.I)
        love.graphics.draw(img, x, y, 0, p.s, p.s)
        Screen.flat(false)
    end

    motes:draw()

    if dim then
        Pal.set(Pal.N, dim)
        love.graphics.rectangle("fill", 0, 0, 1920, 1080)
    end
end

return BG
