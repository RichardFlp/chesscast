local Config = require("src.config")
local Screen = require("src.utils.screen")
local M = require("src.states.manager")
local App = require("src.app")
local Save = require("src.utils.save")
local Search = require("src.ai.search")
local Defs = require("src.cards.defs")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Frame = require("src.ui.frame")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Audio = require("src.audio.audio")

local Setup = {}

local DESC = {
    "EASY: MAKES LOTS OF MISTAKES, GOOD FOR LEARNING",
    "MEDIUM: SEES SIMPLE TRADES, STILL SLIPS UP",
    "HARD: CAREFUL PLAY, PUNISHES HANGING PIECES",
}

local function difficulties()
    local out = {}
    for i, level in ipairs(Search.LEVELS) do out[i] = level.name end
    return out
end

local function clockLabels()
    local t = {}
    for i, c in ipairs(Save.CLOCKS) do t[i] = c[1] end
    return t
end

function Setup:enter(p)
    local s = App.settings
    self.mode = p.mode or "cpu"
    self.color = self.color or 1
    local x, w, y, gap = Config.ui.form.x, Config.ui.form.w, Config.ui.form.y, Config.ui.form.gap
    self.items = {}
    local y2 = y
    if self.mode == "cpu" then
        self.items[#self.items + 1] = W.Selector.new { x = x, y = y2, w = w, label = "DIFFICULTY",
            options = difficulties(), index = s.difficulty, onChange = function(i) s.difficulty = i end }
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
    local cx, by = Screen.W / 2, Config.ui.form.buttonY
    local startLabel = self.mode == "online" and "CREATE ROOM" or "START"
    self.items[#self.items + 1] = Button.new { x = cx - 420, y = by, w = 400, h = 84,
        label = startLabel, style = "primary", onClick = function() self:start() end }
    self.items[#self.items + 1] = Button.new { x = cx + 20, y = by, w = 400, h = 84, label = "BACK",
        backSound = true, onClick = function() self:back() end }
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
    BG.draw(Config.ui.background.menuDim)
    local titles = { cpu = "CLASSIC", online = "HOST ONLINE" }
    local f = Config.ui.frame
    Frame.panel(f.x, f.y, f.w, f.h, titles[self.mode] or "HOT-SEAT")
    local s = App.settings
    local form = Config.ui.form
    local cx = Screen.W / 2
    if self.mode == "cpu" then
        Text.print("CHALLENGE THE CPU", cx, form.titleY, 2, Pal.B, "center")
        Text.print(DESC[s.difficulty], cx, form.descY, 2, Pal.B, "center")
    elseif self.mode == "online" then
        Text.print("CREATE A ROOM, THEN SHARE ITS CODE", cx, form.titleY, 2, Pal.B, "center")
    else
        Text.print("TWO PLAYERS, ONE SCREEN. WHITE MOVES FIRST.", cx, form.titleY, 2, Pal.B, "center")
    end
    local deckNote = s.spells
        and "EACH PLAYER DRAWS FROM A " .. #Defs.deck .. " CARD SPELL DECK"
        or "STANDARD CHESS, NO SPELLS"
    Text.print(deckNote, cx, self.mode == "cpu" and form.deckY or form.onlineDeckY, 2, Pal.I, "center")
    for _, it in ipairs(self.items) do it:draw() end
end

function Setup:back()
    App.save()
    M.switch(self.mode == "cpu" and "menu" or "multiplayer")
end

function Setup:mousemoved() self.focus:clearIfMouse() end
function Setup:mousepressed(x, y, b)
    for _, it in ipairs(self.items) do if it:mousepressed(x, y, b) then return end end
end
function Setup:mousereleased(x, y, b)
    for _, it in ipairs(self.items) do it:mousereleased(x, y, b) end
end
function Setup:keypressed(key)
    if key == "escape" then
        Audio.play("ui_back")
        self:back()
        return
    end
    self.focus:keypressed(key)
end

return Setup
