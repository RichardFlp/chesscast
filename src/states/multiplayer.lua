local Config = require("src.config")
local Screen = require("src.utils.screen")
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
local UI = Config.ui.multiplayer

function MP:enter()
    self.t = 0
    local cx, w, y, gap = Screen.W / 2, UI.width, UI.firstY, UI.gap
    self.items = {
        Button.new { x = cx - w / 2, y = y, w = w, h = UI.height, label = "MATCHMAKING", style = "primary",
            tag = "CASUAL OR RANKED", onClick = function() M.switch("matchmaking") end },
        Button.new { x = cx - w / 2, y = y + gap, w = w, h = UI.height, label = "HOST ONLINE", style = "primary",
            tag = "CREATE A ROOM CODE", onClick = function() M.switch("setup", { mode = "online" }) end },
        Button.new { x = cx - w / 2, y = y + gap * 2, w = w, h = UI.height, label = "JOIN ONLINE", style = "primary",
            tag = "ENTER A ROOM CODE", onClick = function() M.switch("lobby", { role = "guest" }) end },
        Button.new { x = cx - w / 2, y = y + gap * 3, w = w, h = UI.height, label = "LOCAL HOT-SEAT",
            tag = "2 PLAYERS, 1 SCREEN", onClick = function() M.switch("setup", { mode = "local" }) end },
        Button.new { x = cx - 200, y = y + gap * 4 + UI.backGap, w = 400, h = 76, label = "BACK", backSound = true,
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
    BG.draw(Config.ui.background.menuDim)
    local f = Config.ui.frame
    Frame.panel(f.x, f.y, f.w, f.h, "MULTIPLAYER")

    local bob = math.floor(math.sin(self.t * 2) * 2) * 2
    local cx = Screen.W / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(A.piece[1][6], cx - 260, UI.pieceY + bob, 0, UI.pieceScale, UI.pieceScale)
    love.graphics.draw(A.piece[-1][6], cx + 68, UI.pieceY - bob, 0, UI.pieceScale, UI.pieceScale)
    Text.print("VS", cx, UI.vsY, 6, Pal.C, "center", Pal.I)
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
