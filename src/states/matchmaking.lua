local Config = require("src.config")
local Screen = require("src.utils.screen")
local M = require("src.states.manager")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Frame = require("src.ui.frame")
local Audio = require("src.audio.audio")

local MM = {}
local UI = Config.ui.matchmaking

function MM:enter(p)
    self.casual = p and p.casual or false
    self.ranked = p and p.ranked or false
    self:build()
end

function MM:build()
    local cx, w = Screen.W / 2, UI.width

    if self.casual or self.ranked then
        self.items = {}
        for i, mode in ipairs(Config.net.casualModes) do
            local id = mode.id
            self.items[#self.items + 1] = Button.new {
                x = cx - w / 2, y = UI.modeFirstY + (i - 1) * UI.modeGap,
                w = w, h = UI.modeHeight, label = mode.name, tag = mode.tag,
                onClick = function() M.switch("lobby", { role = "match", mode = id, ranked = self.ranked }) end,
            }
        end
        self.items[#self.items + 1] = Button.new {
            x = cx - w / 2, y = UI.modeBackY, w = w, h = UI.modeHeight,
            label = "BACK", backSound = true, onClick = function() self:back() end,
        }
    else
        self.items = {
            Button.new { x = cx - w / 2, y = UI.firstY, w = w, h = UI.height, label = "CASUAL",
                tag = "PLAY ANYONE", style = "primary",
                onClick = function()
                    self.casual, self.ranked = true, false
                    self:build()
                end },
            Button.new { x = cx - w / 2, y = UI.firstY + UI.gap, w = w, h = UI.height, label = "RANKED",
                tag = "Elo MATCH", style = "primary",
                onClick = function()
                    self.casual, self.ranked = false, true
                    self:build()
                end },
            Button.new { x = cx - w / 2, y = UI.backY, w = w, h = UI.height, label = "BACK",
                backSound = true, onClick = function() self:back() end },
        }
    end

    self.focus = W.Focus.new(self.items)
end

function MM:back()
    if self.casual or self.ranked then
        self.casual = false
        self.ranked = false
        self:build()
    else
        M.switch("multiplayer")
    end
end

function MM:update(dt, mx, my)
    BG.update(dt)
    for _, item in ipairs(self.items) do item:update(dt, mx, my) end
end

function MM:draw()
    BG.draw(Config.ui.background.menuDim)
    local f = Config.ui.frame
    local title = self.ranked and "RANKED" or self.casual and "CASUAL" or "MATCHMAKING"
    Frame.panel(f.x, f.y, f.w, f.h, title)
    for _, item in ipairs(self.items) do item:draw() end
end

function MM:mousemoved() self.focus:clearIfMouse() end

function MM:mousepressed(x, y, button)
    for _, item in ipairs(self.items) do
        if item:mousepressed(x, y, button) then return end
    end
end

function MM:mousereleased(x, y, button)
    for _, item in ipairs(self.items) do item:mousereleased(x, y, button) end
end

function MM:keypressed(key)
    if key == "escape" then
        Audio.play("ui_back")
        self:back()
        return
    end
    self.focus:keypressed(key)
end

return MM
