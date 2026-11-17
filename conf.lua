local headless = false
for _, a in ipairs(arg or {}) do
    if a == "--test" then headless = true end
end

function love.conf(t)
    t.identity = "chessplus"
    t.version = "11.4"
    t.console = false
    t.window.title = "ChessCast"
    t.window.width = 1600
    t.window.height = 900
    t.window.minwidth = 960
    t.window.minheight = 540
    t.window.resizable = true
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
    if headless then
        t.window = false
        t.modules.window = false
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.sound = true
    end
end
