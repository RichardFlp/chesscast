io.stdout:setvbuf("no")

local Config = require("src.config")
local args = {}
for i, a in ipairs(arg or {}) do args[i] = a end
local function argValue(name)
    for i, a in ipairs(args) do if a == name then return args[i + 1] or true end end
    return nil
end

if argValue("--test") then
    function love.errorhandler(msg)
        print("ERROR: " .. tostring(msg))
        print(debug.traceback())
        return function() return 1 end
    end
end

if argValue("--test") then
    function love.load()
        local ok = true
        for _, name in ipairs(Config.tests) do
            local found, s = pcall(require, name)
            if found and type(s) == "table" and type(s.run) == "function" then
                local passed = s.run(print)
                ok = passed and ok
            else
                print("ERROR loading " .. name .. ": " .. tostring(s)); ok = false
            end
        end
        print(ok and "ALL TESTS PASSED" or "TESTS FAILED")
        love.event.quit(ok and 0 or 1)
    end
    return
end

local A = require("src.assets.assets")
local Text = require("src.ui.text")
local Screen = require("src.utils.screen")
local Audio = require("src.audio.audio")
local BG = require("src.ui.background")
local App = require("src.app")
local M = require("src.states.manager")
local Transition = require("src.animations.transition")
local Window = require("src.ui.window")

function love.load()
    App.load()
    if Screen.chromeOn then Window.setVisible(false) end
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    local t0 = love.timer.getTime()
    local function lap(what) print(string.format("[load] %s %.2fs", what, love.timer.getTime() - t0)) end
    A.load(); lap("assets")
    Text.init()
    Screen.init(); lap("screen")
    if App.WEB then require("src.net.webnet").init() end
    Audio.load(); lap("audio")
    App.applyAudio()
    BG.init()
    M.register("splash", require("src.states.splash"))
    M.register("menu", require("src.states.menu"))
    M.register("settings", require("src.states.settings"))
    M.register("setup", require("src.states.setup"))
    M.register("campaign", require("src.states.campaign"))
    M.register("multiplayer", require("src.states.multiplayer"))
    M.register("matchmaking", require("src.states.matchmaking"))
    M.register("game", require("src.states.game"))
    M.register("lobby", require("src.states.lobby"))
    local server = argValue("--server")
    if type(server) == "string" then require("src.net.online").setServer(server) end
    M.set("splash")
    App.applyWindow()
    if Screen.chromeOn then
        local w, h = love.graphics.getDimensions()
        local dw, dh = love.window.getDesktopDimensions()
        love.window.setPosition(math.floor((dw - w) / 2), math.floor((dh - h) / 2))
        Window.setVisible(true)
    end
end

local FIXED_MAX = Config.app.fixedMax
function love.update(dt)
    if dt > FIXED_MAX then dt = FIXED_MAX end
    Screen.update(dt)
    Transition.update(dt)
    Window:update()
    local mx, my = Screen.mouse()
    M.call("update", dt, mx, my)
end

function love.draw()
    Screen.begin()
    M.call("draw")
    Transition.draw()
    Screen.finish()
    Window:draw()
end

function love.resize(w, h) Screen.resize(w, h) end

function love.mousepressed(x, y, b)
    if Window:mousepressed(x, y, b) then return end
    local vx, vy = Screen.toVirtual(x, y)
    M.call("mousepressed", vx, vy, b)
end

function love.mousereleased(x, y, b)
    if Window:mousereleased(x, y, b) then return end
    local vx, vy = Screen.toVirtual(x, y)
    M.call("mousereleased", vx, vy, b)
end

function love.mousemoved(x, y)
    local vx, vy = Screen.toVirtual(x, y)
    M.call("mousemoved", vx, vy)
end

function love.wheelmoved(dx, dy) M.call("wheelmoved", dx, dy) end

function love.keypressed(key)
    if key == "f11" then
        App.settings.fullscreen = not App.settings.fullscreen
        App.applyWindow(); App.save()
        return
    end
    M.call("keypressed", key)
end

function love.focus(f) M.call("windowFocus", f) end
function love.textinput(t) M.call("textinput", t) end

function love.quit()
    local Online = require("src.net.online")
    Online.close()
end
