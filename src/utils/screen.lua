local Config = require("src.config")
local Pal = require("src.utils.palette")

local Screen = {}
Screen.W, Screen.H = Config.screen.width, Config.screen.height
Screen.scale, Screen.ox, Screen.oy = 1, 0, 0
Screen.shakeX, Screen.shakeY = 0, 0
local os_ = love.system and love.system.getOS()
Screen.lite = os_ == "Android" or os_ == "iOS"
Screen.chromeOn = os_ == "Windows"
Screen.chromeH = 0

local DITHER = [[
extern Image bayer;
extern float cell;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc) * color;
    // Dithering only changes partially transparent pixels.
    if (c.a >= 1.0) return vec4(c.rgb, 1.0);
    vec2 p = floor(sc / cell);
    float t = Texel(bayer, (mod(p, 4.0) + 0.5) / 4.0).r;
    if (c.a <= 0.001 || c.a < t) discard;
    return vec4(c.rgb, 1.0);
}
]]

local FLAT = [[
extern Image bayer;
extern float cell;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float a = Texel(tex, tc).a * color.a;
    // Dithering only changes partially transparent pixels.
    if (a >= 1.0) return vec4(color.rgb, 1.0);
    vec2 p = floor(sc / cell);
    float t = Texel(bayer, (mod(p, 4.0) + 0.5) / 4.0).r;
    if (a <= 0.001 || a < t) discard;
    return vec4(color.rgb, 1.0);
}
]]

local CURSE_TINT = [[
extern float curse;

vec3 redGrade(vec3 c) {
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    vec3 red = mix(vec3(0.10, 0.004, 0.010), vec3(0.68, 0.035, 0.060), smoothstep(0.02, 0.62, lum));
    red = mix(red, vec3(1.0, 0.52, 0.48), smoothstep(0.55, 0.92, lum));
    red *= smoothstep(0.0, 0.07, lum);
    return mix(c, red, curse);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc) * color;
    return vec4(redGrade(c.rgb), c.a);
}
]]

local curseOn, curseMix = false, 0

function Screen.init()
    Screen.canvas = love.graphics.newCanvas(Screen.W, Screen.H, { dpiscale = 1 })
    Screen.canvas:setFilter("nearest", "nearest")
    local M = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
    local d = love.image.newImageData(4, 4)
    for i = 0, 15 do
        local v = (M[i + 1] + 0.5) / 16
        d:setPixel(i % 4, math.floor(i / 4), v, v, v, 1)
    end
    local bayer = love.graphics.newImage(d)
    bayer:setFilter("nearest", "nearest")
    bayer:setWrap("repeat", "repeat")
    Screen.bayer = bayer
    Screen.shader = love.graphics.newShader(DITHER)
    Screen.shader:send("bayer", bayer)
    Screen.shader:send("cell", Config.ui.ditherCell)
    Screen.flatShader = love.graphics.newShader(FLAT)
    Screen.flatShader:send("bayer", bayer)
    Screen.flatShader:send("cell", Config.ui.ditherCell)
    Screen.tintShader = love.graphics.newShader(CURSE_TINT)
    Screen.tintShader:send("curse", 0)
    Screen.resize(love.graphics.getDimensions())
end

function Screen.setCurse(on)
    curseOn = on == true
end

function Screen.resize(w, h)
    local chrome = 0
    if Screen.chromeOn and love.window and love.window.getFullscreen and not love.window.getFullscreen() then
        chrome = Config.ui.chrome.height
    end
    Screen.chromeH = chrome

    local avail = math.max(1, h - chrome)
    local s = math.min(w / Screen.W, avail / Screen.H)

    local snapped = math.floor(s * 2 + 1e-6) / 2
    if snapped > 0 and s - snapped < Config.ui.snap then s = snapped end
    Screen.scale = s
    Screen.ox = math.floor((w - Screen.W * s) / 2)
    Screen.oy = chrome + math.floor((avail - Screen.H * s) / 2)
end

function Screen.toVirtual(x, y)
    return (x - Screen.ox) / Screen.scale, (y - Screen.oy) / Screen.scale
end

function Screen.mouse()
    return Screen.toVirtual(love.mouse.getPosition())
end

function Screen.begin()
    love.graphics.setCanvas(Screen.canvas)
    love.graphics.clear(Pal.N)
    love.graphics.setShader(Screen.shader)
    love.graphics.push()
    love.graphics.translate(math.floor(Screen.shakeX + 0.5) * 2, math.floor(Screen.shakeY + 0.5) * 2)
end

function Screen.flat(on)
    love.graphics.setShader(on and Screen.flatShader or Screen.shader)
end

function Screen.finish()
    love.graphics.pop()
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.clear(Pal.N)
    love.graphics.setColor(1, 1, 1, 1)
    if curseMix > 0.001 then
        Screen.tintShader:send("curse", curseMix)
        love.graphics.setShader(Screen.tintShader)
    end
    love.graphics.draw(Screen.canvas, Screen.ox, Screen.oy, 0, Screen.scale, Screen.scale)
    love.graphics.setShader()
end

local shakeT, shakeAmp = 0, 0
function Screen.shake(amp, dur)
    shakeAmp = math.max(shakeAmp, amp)
    shakeT = math.max(shakeT, dur or 0.25)
end

function Screen.update(dt)
    local target = curseOn and 1 or 0
    curseMix = curseMix + (target - curseMix) * math.min(1, dt * 6)
    if math.abs(target - curseMix) < 0.001 then curseMix = target end
    if shakeT > 0 then
        shakeT = shakeT - dt
        local a = shakeAmp * math.max(0, shakeT) * 4
        if a > shakeAmp then a = shakeAmp end
        Screen.shakeX = (love.math.random() * 2 - 1) * a
        Screen.shakeY = (love.math.random() * 2 - 1) * a
        if shakeT <= 0 then shakeAmp, Screen.shakeX, Screen.shakeY = 0, 0, 0 end
    end
end

return Screen
