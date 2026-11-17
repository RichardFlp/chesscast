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
        local res = Save.RESOLUTIONS[s.resolution]
        local dw, dh = love.window.getDesktopDimensions()
        local w, h = res[1], res[2]
        if w > dw or h > dh then

            local k = math.min(dw / 1920, (dh - 60) / 1080)
            w, h = math.floor(1920 * k), math.floor(1080 * k)
        end
        local cw, ch, flags = love.window.getMode()
        if flags.fullscreen or cw ~= w or ch ~= h then
            pcall(love.window.setMode, w, h, { resizable = true, vsync = 1, minwidth = 960, minheight = 540, fullscreen = false })
        end
    end
    Screen.resize(love.graphics.getDimensions())
end

return App
