local M = require("src.states.manager")
local App = require("src.app")
local Save = require("src.utils.save")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Frame = require("src.ui.frame")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Audio = require("src.audio.audio")

local Setup = {}

local DESC = {
    "EASY: SHALLOW SEARCH WITH RANDOM SLIPS",
    "MEDIUM: SOLID TACTICS, PLAYS SPELLS SENSIBLY",
    "HARD: DEEP SEARCH, PUNISHES MISTAKES",
}

local function clockLabels()
    local t = {}
    for i, c in ipairs(Save.CLOCKS) do t[i] = c[1] end
    return t
end

function Setup:enter(p)
    local s = App.settings
    self.mode = p.mode or "cpu"
    self.color = self.color or 1
    local x, w, y, gap = 400, 1120, 250, 96
    self.items = {}
    local y2 = y
    if self.mode == "cpu" then
        self.items[#self.items + 1] = W.Selector.new { x = x, y = y2, w = w, label = "DIFFICULTY",
            options = { "EASY", "MEDIUM", "HARD" }, index = s.difficulty, onChange = function(i) s.difficulty = i end }
        y2 = y2 + gap
    end
    if self.mode ~= "local" then
        self.items[#self.items + 1] = W.Selector.new { x = x, y = y2, w = w, label = "PLAY AS",
            options = { "WHITE", "BLACK", "RANDOM" }, index = self.color, onChange = function(i) self.color = i end }
        y2 = y2 + gap
    end
    self.items[#self.items + 1] = W.Selector.new { x = x, y = y2, w = w, label = "SPELL CARDS",
        options = { "ON", "OFF" }, index = s.spells and 1 or 2, onChange = function(i) s.spells = (i == 1) end }
    self.items[#self.items + 1] = W.Selector.new { x = x, y = y2 + gap, w = w, label = "CLOCK",
        options = clockLabels(), index = s.clock, onChange = function(i) s.clock = i end }
    if self.mode == "cpu" then
        self.items[#self.items + 1] = W.Toggle.new { x = x, y = y2 + gap * 2, w = w, label = "TUTORIAL",
            value = s.tutorial, captionOn = "A GUIDED FIRST GAME", captionOff = "OFF",
            onChange = function(v) s.tutorial = v end }
    end
    self.items[#self.items + 1] = Button.new { x = 960 - 420, y = 820, w = 400, h = 84, label = self.mode == "online" and "CREATE ROOM" or "START",
        style = "primary", onClick = function() self:start() end }
    self.items[#self.items + 1] = Button.new { x = 960 + 20, y = 820, w = 400, h = 84, label = "BACK",
        backSound = true, onClick = function() App.save(); M.switch(self.mode == "cpu" and "menu" or "multiplayer") end }
    self.focus = W.Focus.new(self.items)
end

function Setup:start()
    local s = App.settings
    App.save()
    local human = 1
    if self.mode ~= "local" then
        human = (self.color == 1 and 1) or (self.color == 2 and -1) or (love.math.random() < 0.5 and 1 or -1)
    end
    if self.mode == "online" then
        M.switch("lobby", { role = "host", side = human, spells = s.spells, clock = Save.CLOCKS[s.clock][2] })
        return
    end
    M.switch("game", {
        mode = self.mode,
        human = human,
        difficulty = s.difficulty,
        spells = s.spells,
        clock = Save.CLOCKS[s.clock][2],
        tutorial = self.mode == "cpu" and s.tutorial or nil,
    })
end

function Setup:update(dt, mx, my)
    BG.update(dt)
    for _, it in ipairs(self.items) do it:update(dt, mx, my) end
end

function Setup:draw()
    BG.draw(0.35)
    local titles = { cpu = "CLASSIC", online = "HOST ONLINE" }
    Frame.panel(340, 150, 1240, 810, titles[self.mode] or "HOT-SEAT")
    local s = App.settings
    if self.mode == "cpu" then
        Text.print("CHALLENGE THE CPU", 960, 206, 2, Pal.B, "center")
        Text.print(DESC[s.difficulty], 960, 728, 2, Pal.B, "center")
    elseif self.mode == "online" then
        Text.print("CREATE A ROOM, THEN SHARE ITS CODE", 960, 206, 2, Pal.B, "center")
    else
        Text.print("TWO PLAYERS, ONE SCREEN. WHITE MOVES FIRST.", 960, 206, 2, Pal.B, "center")
    end
    Text.print(s.spells and "EACH PLAYER DRAWS FROM A 24 CARD SPELL DECK" or "STANDARD CHESS, NO SPELLS", 960,
        self.mode == "cpu" and 764 or 716, 2, Pal.I, "center")
    for _, it in ipairs(self.items) do it:draw() end
end

function Setup:mousemoved() self.focus:clearIfMouse() end
function Setup:mousepressed(x, y, b)
    for _, it in ipairs(self.items) do if it:mousepressed(x, y, b) then return end end
end
function Setup:mousereleased(x, y, b)
    for _, it in ipairs(self.items) do it:mousereleased(x, y, b) end
end
function Setup:keypressed(key)
    if key == "escape" then Audio.play("ui_back"); App.save(); M.switch(self.mode == "cpu" and "menu" or "multiplayer"); return end
    self.focus:keypressed(key)
end

return Setup
