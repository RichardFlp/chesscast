local Config = require("src.config")
local Screen = require("src.utils.screen")
local M = require("src.states.manager")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Logo = require("src.ui.logo")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Audio = require("src.audio.audio")
local Particles = require("src.animations.particles")
local Frame = require("src.ui.frame")
local A = require("src.assets.assets")
local App = require("src.app")

local Menu = {}

function Menu:init()
    local bw, x = Config.ui.menu.width, Screen.W / 2 - Config.ui.menu.width / 2
    local y0, gap = Config.ui.menu.y, Config.ui.menu.gap
    self.buttons = {
        Button.new { x = x, y = y0, w = bw, h = Config.ui.menu.height, label = "CAMPAIGN",
            style = "primary", tag = "NEW", onClick = function() M.switch("campaign") end },
        Button.new { x = x, y = y0 + gap, w = bw, h = Config.ui.menu.height, label = "CLASSIC", tag = "VS CPU",
            onClick = function() M.switch("setup") end },
        Button.new { x = x, y = y0 + gap * 2, w = bw, h = Config.ui.menu.height, label = "MULTIPLAYER CLASSIC",
            onClick = function() M.switch("multiplayer") end },
        Button.new { x = x, y = y0 + gap * 3, w = bw, h = Config.ui.menu.height, label = "SETTINGS",
            onClick = function() M.switch("settings", { back = "menu" }) end },
        Button.new { x = x, y = y0 + gap * 4, w = bw, h = Config.ui.menu.height, label = "QUIT", backSound = true,
            onClick = function() love.event.quit() end },
    }
    if App.WEB then self.buttons[5] = nil end
    self.buttons[1].h = Config.ui.menu.campaignHeight
    self.focus = W.Focus.new(self.buttons)
    self.fx = Particles.new(Config.ui.menu.fx)
end

function Menu:enter()
    if not self.buttons then self:init() end
    self.t = 0
    Audio.music("music_menu")
end

function Menu:update(dt, mx, my)
    self.t = self.t + dt
    BG.update(dt)
    for _, b in ipairs(self.buttons) do b:update(dt, mx, my) end

    if love.math.random() < dt * Config.ui.menu.spawnRate then
        local x = 560 + love.math.random() * 800
        local y = 150 + love.math.random() * 150
        local vx = (love.math.random() - 0.5) * 40
        local col = love.math.random() < 0.5 and Pal.C or Pal.B
        self.fx:add(x, y, vx, -20 - love.math.random() * 40,
            1 + love.math.random(), 4, col, -10, 0.5, 1)
    end
    self.fx:update(dt)
end

function Menu:draw()
    BG.draw()
    Logo.draw(Screen.W / 2, Config.ui.menu.logoY, self.t)
    self.fx:draw()
    local tag = "A CHESS GAME WITH SPELLS"
    local tw = Text.width(tag, 2) + 100
    love.graphics.setColor(1, 1, 1, 1)
    local menu = Config.ui.menu
    A.ui.panel_small:draw(Screen.W / 2 - tw / 2, menu.tagY, tw, menu.tagH, 2)
    Text.print(tag, Screen.W / 2, menu.tagTextY, 2, Pal.C, "center", Pal.N)
    Frame.diamond(Screen.W / 2 - tw / 2 + 26, menu.tagTextY + 7, 6, Pal.B)
    Frame.diamond(Screen.W / 2 + tw / 2 - 26, menu.tagTextY + 7, 6, Pal.B)
    for _, b in ipairs(self.buttons) do b:draw() end
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", 0, Screen.H - Config.ui.footer, Screen.W, Config.ui.footer)
    if not Screen.lite then
        local hint = App.WEB and "ARROWS + ENTER OR MOUSE"
            or "ARROWS + ENTER OR MOUSE    F11 FULLSCREEN"
        Text.print(hint, menu.hintX, menu.footerTextY, 2, Pal.B, "left")
    end
    Text.print("V " .. Config.app.release, Screen.W - menu.footerInset, menu.footerTextY, 2, Pal.B, "right")
end

function Menu:mousemoved() self.focus:clearIfMouse() end

function Menu:mousepressed(x, y, b)
    for _, btn in ipairs(self.buttons) do if btn:mousepressed(x, y, b) then return end end
end

function Menu:mousereleased(x, y, b)
    for _, btn in ipairs(self.buttons) do btn:mousereleased(x, y, b) end
end

function Menu:keypressed(key)
    if key == "escape" then return end
    self.focus:keypressed(key)
end

return Menu
