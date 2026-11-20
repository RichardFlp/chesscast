local Config = require("src.config")
local Screen = require("src.utils.screen")
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

local Settings = {}

local function resLabels()
    local t = {}
    for i, r in ipairs(Save.RESOLUTIONS) do t[i] = r[1] .. " X " .. r[2] end
    return t
end

function Settings:build()
    local s = App.settings
    local form = Config.ui.settings
    local x, w, y, gap = form.x, form.w, form.y, form.gap
    self.items = {
        W.Slider.new { x = x, y = y, w = w, label = "MASTER VOLUME", value = s.master,
            onChange = function(v) s.master = v; App.applyAudio() end },
        W.Slider.new { x = x, y = y + gap, w = w, label = "MUSIC VOLUME", value = s.music,
            onChange = function(v) s.music = v; App.applyAudio() end },
        W.Slider.new { x = x, y = y + gap * 2, w = w, label = "SFX VOLUME", value = s.sfx,
            onChange = function(v) s.sfx = v; App.applyAudio(); Audio.play("move") end },
        W.Selector.new { x = x, y = y + gap * 3 + 44, w = w, label = "FULLSCREEN", options = { "OFF", "ON" },
            index = s.fullscreen and 2 or 1,
            onChange = function(i) s.fullscreen = (i == 2); App.applyWindow(); self:refresh() end },
        W.Selector.new { x = x, y = y + gap * 4 + 44, w = w, label = "WINDOW SIZE", options = resLabels(),
            index = s.resolution, onChange = function(i) s.resolution = i; App.applyWindow() end },
        W.Selector.new { x = x, y = y + gap * 5 + 44, w = w, label = "ANIMATIONS", options = Save.ANIM,
            index = s.anim, onChange = function(i) s.anim = i end },
        Button.new { x = Screen.W / 2 - 200, y = form.backY, w = 400, h = 76, label = "BACK", backSound = true,
            onClick = function() self:back() end },
    }
    self.focus = W.Focus.new(self.items)
    self:refresh()
end

function Settings:refresh()
    local fixed = App.WEB or Screen.lite
    self.items[5].disabled = App.settings.fullscreen or fixed
    self.items[4].disabled = fixed
end

function Settings:enter(p)
    self.backTo = p.back or "menu"
    self.backParams = p.backParams
    self.overlay = p.overlay
    self:build()
end

function Settings:back()
    App.save()
    M.switch(self.backTo, self.backParams)
end

function Settings:update(dt, mx, my)
    BG.update(dt)
    for _, it in ipairs(self.items) do it:update(dt, mx, my) end
end

function Settings:draw()
    if self.overlay then self.overlay() else BG.draw(Config.ui.background.menuDim) end
    local f = Config.ui.frame
    Frame.panel(f.x, f.y, f.w, f.h, "SETTINGS")
    local form = Config.ui.settings
    Text.print("AUDIO", form.x, form.audioY, 2, Pal.B, "left")
    Frame.divider(form.x, form.dividerY, form.w)
    Text.print("DISPLAY", form.x, form.displayY, 2, Pal.B, "left")
    for _, it in ipairs(self.items) do it:draw() end
    if App.settings.fullscreen then
        Text.print("WINDOW SIZE APPLIES IN WINDOWED MODE", Screen.W / 2, form.hintY, 2, Pal.I, "center")
    end
end

function Settings:mousemoved() self.focus:clearIfMouse() end

function Settings:mousepressed(x, y, b)
    for _, it in ipairs(self.items) do
        if not it.disabled and it:mousepressed(x, y, b) then return end
    end
end

function Settings:mousereleased(x, y, b)
    for _, it in ipairs(self.items) do it:mousereleased(x, y, b) end
end

function Settings:keypressed(key)
    if key == "escape" then Audio.play("ui_back"); self:back(); return end
    self.focus:keypressed(key)
end

return Settings
