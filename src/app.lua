local Config = require("src.config")
local Save = require("src.utils.save")
local Audio = require("src.audio.audio")
local Screen = require("src.utils.screen")

local App = {}

function App.load()
    App.settings = Save.load()
end

function App.save() Save.write(App.settings) end

function App.applyAudio()
    local s = App.settings
    Audio.setVolumes(s.master, s.music, s.sfx)
end

function App.animScale() return Save.ANIM_SCALE[App.settings.anim] end

App.WEB = love.system and love.system.getOS() == "Web"

local function windowSize(s)
    local res = Save.RESOLUTIONS[s.resolution]
    local dw, dh = love.window.getDesktopDimensions()
    local chrome = Screen.chromeOn and Config.ui.chrome.height or 0
    local w, h = res[1], res[2]
    local winH = h + chrome
    if w > dw or winH > dh then
        local k = math.min(dw / Screen.W, (dh - Config.ui.windowMargin - chrome) / Screen.H)
        w, h = math.floor(Screen.W * k), math.floor(Screen.H * k)
        winH = h + chrome
    end
    return w, winH, chrome
end

function App.applyWindow()
    if not love.window then return end
    if App.WEB then Screen.resize(love.graphics.getDimensions()); return end
    if Screen.lite then
        local _, _, flags = love.window.getMode()
        if not flags.fullscreen then pcall(love.window.setFullscreen, true, "desktop") end
        Screen.resize(love.graphics.getDimensions())
        return
    end
    local s = App.settings
    if s.fullscreen then
        pcall(love.window.setFullscreen, true, "desktop")
    else
        local w, winH, chrome = windowSize(s)
        local cw, ch, flags = love.window.getMode()
        if flags.fullscreen or cw ~= w or ch ~= winH then
            pcall(love.window.setMode, w, winH, {
                resizable = not Screen.chromeOn,
                borderless = Screen.chromeOn,
                vsync = 1,
                minwidth = Config.window.minWidth,
                minheight = Config.window.minHeight + chrome,
                fullscreen = false,
            })
        end
    end
    Screen.resize(love.graphics.getDimensions())
    require("src.ui.window"):reset()
end

return App
