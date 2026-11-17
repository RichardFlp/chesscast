local M = require("src.states.manager")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Frame = require("src.ui.frame")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Audio = require("src.audio.audio")
local A = require("src.assets.assets")
local App = require("src.app")

local MP = {}

function MP:enter()
    self.t = 0
    self.items = {
        Button.new { x = 960 - 300, y = 410, w = 600, h = 84, label = "MATCHMAKING", style = "primary",
            tag = "PLAY A RANDOM OPPONENT", onClick = function() M.switch("lobby", { role = "match" }) end },
        Button.new { x = 960 - 300, y = 510, w = 600, h = 84, label = "HOST ONLINE", style = "primary",
            tag = "CREATE A ROOM CODE", onClick = function() M.switch("setup", { mode = "online" }) end },
        Button.new { x = 960 - 300, y = 610, w = 600, h = 84, label = "JOIN ONLINE", style = "primary",
            tag = "ENTER A ROOM CODE", onClick = function() M.switch("lobby", { role = "guest" }) end },
        Button.new { x = 960 - 300, y = 710, w = 600, h = 84, label = "LOCAL HOT-SEAT",
            tag = "2 PLAYERS, 1 SCREEN", onClick = function() M.switch("setup", { mode = "local" }) end },
        Button.new { x = 960 - 200, y = 860, w = 400, h = 76, label = "BACK", backSound = true,
            onClick = function() M.switch("menu") end },
    }
    self.focus = W.Focus.new(self.items)
end

function MP:update(dt, mx, my)
    self.t = self.t + dt
    BG.update(dt)
    for _, it in ipairs(self.items) do it:update(dt, mx, my) end
end

function MP:draw()
    BG.draw(0.35)
    Frame.panel(340, 150, 1240, 830, "MULTIPLAYER")

    local bob = math.floor(math.sin(self.t * 2) * 2) * 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(A.piece[1][6], 700, 200 + bob, 0, 6, 6)
    love.graphics.draw(A.piece[-1][6], 1028, 200 - bob, 0, 6, 6)
    Text.print("VS", 960, 280, 6, Pal.C, "center", Pal.I)
    for _, it in ipairs(self.items) do it:draw() end
end

function MP:mousemoved() self.focus:clearIfMouse() end
function MP:mousepressed(x, y, b)
    for _, it in ipairs(self.items) do if it:mousepressed(x, y, b) then return end end
end
function MP:mousereleased(x, y, b)
    for _, it in ipairs(self.items) do it:mousereleased(x, y, b) end
end
function MP:keypressed(key)
    if key == "escape" then Audio.play("ui_back"); M.switch("menu"); return end
    self.focus:keypressed(key)
end

return MP
