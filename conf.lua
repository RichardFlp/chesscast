local Config = require("src.config")

local headless = false
for _, a in ipairs(arg or {}) do
    if a == "--test" then headless = true end
end

function love.conf(t)
    local windows = love._os == "Windows"
    local chrome = windows and Config.ui.chrome.height or 0
    t.identity = Config.app.key
    t.version = Config.app.version
    t.console = false
    t.window.title = Config.app.name
    t.window.width = Config.window.width
    t.window.height = Config.window.height + chrome
    t.window.minwidth = Config.window.minWidth
    t.window.minheight = Config.window.minHeight + chrome
    t.window.resizable = not windows
    t.window.borderless = windows
    t.window.vsync = 1
    t.window.highdpi = false
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false

    if love._os == "Android" or love._os == "iOS" then
        t.window.fullscreen = true
        t.window.fullscreentype = "desktop"
        t.window.resizable = false
        t.window.vsync = 1
    end

    if windows then
        t.window.x = -10000
        t.window.y = -10000
    end

    if headless then
        t.window = false
        t.modules.window = false
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.sound = true
    end
end
