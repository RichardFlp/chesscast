local M = require("src.states.manager")
local Button = require("src.ui.button")
local Frame = require("src.ui.frame")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Audio = require("src.audio.audio")
local Spring = require("src.utils.spring")
local U = require("src.utils.util")
local A = require("src.assets.assets")
local App = require("src.app")
local Levels = require("src.campaign.levels")
local Search = require("src.ai.search")

local C = {}

local CLIP_X, CLIP_Y, CLIP_W, CLIP_H = 0, 0, 1920, 1028
local SCALE = 3
local floor, sin = math.floor, math.sin
local DIFF = { "EASY", "MEDIUM", "HARD" }

local function quads(img, n, w, h)
    local q = {}
    for i = 1, n do q[i] = love.graphics.newQuad((i - 1) * w, 0, w, h, img:getDimensions()) end
    return q
end

function C:load()
    if self.img then return end
    local function img(n, w, h) return A.image("assets/campaign/" .. n .. ".png", w, h) end
    self.img = {
        done = img("node_done", 48, 48), current = img("node_current", 48, 48), locked = img("node_locked", 48, 48),
        boss = img("node_boss", 56, 56), bossLocked = img("node_boss_locked", 56, 56),
        map = A.image("assets/campaign/map.png", 640, 1500),
        ring = img("ring", 512, 64), spark = img("sparkle", 63, 9), mascot = img("mascot", 192, 32),
    }
    self.q = {
        ring = quads(self.img.ring, 8, 64, 64),
        spark = quads(self.img.spark, 7, 9, 9),
        mascot = quads(self.img.mascot, 6, 32, 32),
    }
end

function C:layout()
    local path = require("src.campaign.path")
    self.mapH = path.h
    self.nodes, self.headers = {}, {}
    for u, un in ipairs(Levels.units) do
        local first = un.levels[1].index
        self.headers[u] = { y = path.nodes[first].y, unit = un }
        for _, lv in ipairs(un.levels) do
            local sz = (lv.boss and 56 or 48) * SCALE
            local pt = path.nodes[lv.index]
            self.nodes[lv.index] = { lv = lv, x = pt.x, y = pt.y, r = sz / 2 * 0.92, sz = sz,
                ss = Spring.new(1, 300, 14), shake = 0 }
        end
    end
    self.maxScroll = math.max(0, self.mapH - CLIP_H)
    self.eyes = {}
    for i, e in ipairs(path.eyes) do
        self.eyes[i] = { x = e.x, y = e.y, off = love.math.random() * 40, rate = 0.6 + love.math.random() * 0.5 }
    end
    self.flies = {}
    for i = 1, 70 do
        self.flies[i] = { x = love.math.random() * 1920, y = love.math.random() * self.mapH,
            ph = love.math.random() * 6.28, sp = 0.4 + love.math.random() * 0.8, r = 20 + love.math.random() * 40 }
    end
end

function C:centerOn(i, snap)
    local n = self.nodes[i]
    local t = U.clamp(n.y - CLIP_H / 2, 0, self.maxScroll)
    self.scroll.target = t
    if snap then self.scroll:snap(t) end
end

function C:burst(i, count)
    local n = self.nodes[i]
    for _ = 1, count do
        local a = love.math.random() * math.pi * 2
        local d = n.r * (0.9 + love.math.random() * 0.5)
        self.sparks[#self.sparks + 1] = { x = n.x + math.cos(a) * d, y = n.y + math.sin(a) * d, t = 0,
            life = 0.5 + love.math.random() * 0.4 }
    end
end

function C:enter(p)
    self:load()
    if not self.nodes then self:layout() end
    self.t = 0
    self.sparks = {}
    self.scroll = Spring.new(0, 170, 24)
    local prog = Levels.progress()
    self.sel = math.min(prog + 1, Levels.count)
    self:centerOn(self.sel, true)
    self.bubble = Spring.new(0, 320, 16)
    self.bubble.target = 1
    self.back = Button.new { x = 60, y = 60, w = 240, h = 72, label = "BACK", backSound = true,
        onClick = function() M.switch("menu") end }
    for _, n in ipairs(self.nodes) do n.ss:snap(1); n.shake = 0 end
    if p and p.won then
        local n = self.nodes[p.won]
        if n then n.ss:kick(-6); self:burst(p.won, 16) end
        local nxt = math.min(p.won + 1, Levels.count)
        self.sel = nxt
        self:centerOn(nxt)
        self.bubble:snap(0); self.bubble.target = 1
    end
    Audio.music("music_menu")
end

function C:unlocked(i) return i <= Levels.progress() + 1 end

function C:play(i)
    local lv = Levels.flat[i]
    M.switch("game", {
        mode = "cpu", human = lv.human, difficulty = lv.difficulty, spells = true, clock = 0,
        names = { [-lv.human] = lv.name }, campaign = i,
        tutorial = (i == 1 and App.settings.tutorial) or nil,
    })
end

function C:select(i)
    if i == self.sel then return end
    self.sel = i
    self.bubble:snap(0); self.bubble.target = 1
    self.bubble:kick(6)
    Audio.play("tick", 1.1)
    local n = self.nodes[i]
    local top, bottom = n.y - n.r - 80, n.y + n.r + 40
    if top < self.scroll.target or bottom > self.scroll.target + CLIP_H then self:centerOn(i) end
end

function C:update(dt, mx, my)
    self.t = self.t + dt
    self.back:update(dt, mx, my)
    self.scroll:update(dt)
    self.bubble:update(dt)
    for _, n in ipairs(self.nodes) do
        local hover = U.inRect(mx, my, CLIP_X, CLIP_Y, CLIP_W, CLIP_H) and self:unlocked(n.lv.index)
            and (mx - n.x) ^ 2 + (my - (CLIP_Y + n.y - self.scroll.x)) ^ 2 <= n.r * n.r
        n.ss.target = hover and 1.07 or 1
        n.ss:update(dt)
        if n.shake > 0 then n.shake = math.max(0, n.shake - dt) end
    end
    local cur = Levels.progress() + 1
    if cur <= Levels.count and love.math.random() < dt * 3 then self:burst(cur, 1) end
    for i = #self.sparks, 1, -1 do
        local s = self.sparks[i]
        s.t = s.t + dt
        if s.t >= s.life then table.remove(self.sparks, i) end
    end
end

function C:drawNode(n)
    local lv = n.lv
    local i = lv.index
    local prog = Levels.progress()
    local img
    if i <= prog then img = lv.boss and self.img.boss or self.img.done
    elseif i == prog + 1 then img = lv.boss and self.img.boss or self.img.current
    else img = lv.boss and self.img.bossLocked or self.img.locked end
    local sy = CLIP_Y + n.y - self.scroll.x
    local bob = 0
    if i == self.sel and self:unlocked(i) then bob = floor(sin(self.t * 3) * 1.5 + 0.5) * 2 end
    local sx = n.x
    if n.shake > 0 then sx = sx + floor(sin(n.shake * 60) * n.shake * 40 / 2 + 0.5) * 2 end
    local w, h = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, floor(sx), floor(sy) + bob, 0, SCALE * n.ss.x, SCALE * n.ss.x, w / 2, h / 2)
    if i == prog + 1 and not lv.boss then
        local f = floor(self.t * 6) % 8 + 1
        love.graphics.draw(self.img.ring, self.q.ring[f], floor(sx), floor(sy) + bob, 0, SCALE * 1.15, SCALE * 1.15, 32, 32)
    end
    if i == prog + 1 and lv.boss then
        local f = floor(self.t * 6) % 8 + 1
        love.graphics.draw(self.img.ring, self.q.ring[f], floor(sx), floor(sy) + bob, 0, SCALE * 1.4, SCALE * 1.4, 32, 32)
    end
end

function C:bubbleRect()
    local n = self.nodes[self.sel]
    local label = self.sel <= Levels.progress() and "REPLAY" or "START"
    local w = Text.width(label, 3) + 64
    local sy = CLIP_Y + n.y - self.scroll.x
    local pop = U.clamp(self.bubble.x, 0, 1.3)
    local bob = floor(sin(self.t * 3) * 1.5 + 0.5) * 2
    local h = 56
    local y = sy - n.r - 78 - (1 - pop) * 20 + bob
    return n.x - w / 2, y, w, h, label, pop
end

function C:drawBubble()
    if not self:unlocked(self.sel) then return end
    local x, y, w, h, label, pop = self:bubbleRect()
    if pop <= 0.02 then return end
    local cx = x + w / 2
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", x + 6, y + 6, w, h)
    Pal.set(Pal.C)
    love.graphics.rectangle("fill", x, y, w, h)
    for k = 0, 3 do
        love.graphics.rectangle("fill", cx - 16 + k * 4, y + h + k * 4, 32 - k * 8, 4)
    end
    Text.print(label, cx, y + (h - 21) / 2, 3, Pal.N, "center")
end

function C:drawMascot()
    local prog = Levels.progress()
    local i = math.min(prog + 1, Levels.count)
    local n = self.nodes[i]
    local sy = CLIP_Y + n.y - self.scroll.x
    local right = n.x < 960
    local mx = n.x + (right and 1 or -1) * (n.r + 96)
    local f = floor(self.t * 3) % 6 + 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.img.mascot, self.q.mascot[f], floor(mx / 2) * 2, floor(sy / 2) * 2, 0,
        right and 4 or -4, 4, 16, 16)
end

function C:drawSparks()
    love.graphics.setColor(1, 1, 1, 1)
    for _, s in ipairs(self.sparks) do
        local f = U.clamp(floor(s.t / s.life * 7) + 1, 1, 7)
        love.graphics.draw(self.img.spark, self.q.spark[f], floor(s.x / 2) * 2, floor((CLIP_Y + s.y - self.scroll.x) / 2) * 2,
            0, 4, 4, 4, 4)
    end
end

function C:drawHeaders()
    for _, h in ipairs(self.headers) do
        local y = CLIP_Y + h.y - self.scroll.x - 150
        if y > -100 and y < CLIP_H then
            local x, w = 1440, 440
            Pal.set(Pal.N)
            love.graphics.rectangle("fill", x + 8, y + 8, w, 96)
            love.graphics.setColor(1, 1, 1, 1)
            A.ui.panel_small:draw(x, y, w, 96, 2)
            Text.print(h.unit.title, x + w / 2, y + 16, 2, Pal.B, "center")
            Text.print(h.unit.sub, x + w / 2, y + 50, 3, Pal.C, "center", Pal.N)
        end
    end
end

function C:drawInfo()
    local lv = Levels.flat[self.sel]
    local x, y, w, h = 60, 300, 440, 400
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", x + 8, y + 8, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.panel_large:draw(x, y, w, h, 2)
    local state = self.sel <= Levels.progress() and "CLEARED" or (self:unlocked(self.sel) and "READY" or "LOCKED")
    Text.print("LEVEL " .. lv.index, x + w / 2, y + 36, 3, Pal.B, "center")
    Text.print(lv.name, x + w / 2, y + 84, 6, Pal.C, "center", Pal.N)
    Text.print(lv.boss and "BOSS" or "DUEL", x + w / 2, y + 156, 3, lv.boss and Pal.C or Pal.B, "center", Pal.N)
    Text.print(DIFF[lv.difficulty] .. " CPU", x + w / 2, y + 214, 3, Pal.C, "center", Pal.N)
    Text.print("YOU PLAY " .. (lv.human == 1 and "WHITE" or "BLACK"), x + w / 2, y + 260, 2, Pal.B, "center")
    Frame.divider(x + 40, y + 304, w - 80)
    Text.print(state, x + w / 2, y + 336, 3, state == "LOCKED" and Pal.I or Pal.C, "center", Pal.N)
end

function C:drawEyes()
    local sc = -floor(-self.scroll.x)
    for _, e in ipairs(self.eyes) do
        local sy = e.y - sc
        if sy > -20 and sy < CLIP_H + 20 then
            local c = (self.t * e.rate + e.off) % 9
            if c > 2.5 then
                local h = (c % 3.1 < 0.12) and 1 or 2
                local lx = floor(sin(self.t * 0.4 + e.off) * 1.5 + 0.5) * SCALE
                Pal.set(c > 8.4 and Pal.B or Pal.C)
                for _, dx in ipairs({ -9, 6 }) do
                    love.graphics.rectangle("fill", e.x + dx + lx, sy + (2 - h) * SCALE, 2 * SCALE, h * SCALE)
                end
            end
        end
    end
end

function C:drawFlies()
    for _, f in ipairs(self.flies) do
        local t = self.t * f.sp + f.ph
        local x = f.x + sin(t) * f.r
        local y = f.y + sin(t * 0.7 + 1.3) * f.r * 0.6 - self.scroll.x
        if y > -10 and y < CLIP_H + 10 then
            local glow = sin(t * 2.3)
            if glow > -0.3 then
                x, y = floor(x / SCALE) * SCALE, floor(y / SCALE) * SCALE
                if glow > 0.5 then
                    Pal.set(Pal.B)
                    love.graphics.rectangle("fill", x - SCALE, y, SCALE * 3, SCALE)
                    love.graphics.rectangle("fill", x, y - SCALE, SCALE, SCALE * 3)
                end
                Pal.set(glow > 0.2 and Pal.C or Pal.B)
                love.graphics.rectangle("fill", x, y, SCALE, SCALE)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function C:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.img.map, 0, floor(-self.scroll.x), 0, 3, 3)
    self:drawEyes()
    self:drawFlies()
    self:drawHeaders()
    for _, n in ipairs(self.nodes) do
        local sy = CLIP_Y + n.y - self.scroll.x
        if sy > -n.r - 40 and sy < CLIP_H + n.r + 40 then self:drawNode(n) end
    end
    self:drawMascot()
    self:drawSparks()
    self:drawBubble()
    self:drawInfo()
    self.back:draw()
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", 0, 1028, 1920, 52)
    Text.print("UP DOWN SELECT    ENTER PLAY    ESC BACK", 40, 1046, 2, Pal.B, "left")
    Text.print(Levels.progress() .. " OF " .. Levels.count .. " CLEARED", 1880, 1046, 2, Pal.B, "right")
end

function C:nodeAt(x, y)
    if not U.inRect(x, y, CLIP_X, CLIP_Y, CLIP_W, CLIP_H) then return nil end
    for i, n in ipairs(self.nodes) do
        if (x - n.x) ^ 2 + (y - (CLIP_Y + n.y - self.scroll.x)) ^ 2 <= n.r * n.r then return i end
    end
end

function C:mousepressed(x, y, b)
    if self.back:mousepressed(x, y, b) then return end
    if b ~= 1 then return end
    if self:unlocked(self.sel) then
        local bx, by, bw, bh = self:bubbleRect()
        if U.inRect(x, y, bx, by, bw, bh + 16) and U.inRect(x, y, CLIP_X, CLIP_Y, CLIP_W, CLIP_H) then
            Audio.play("ui_click")
            self:play(self.sel)
            return
        end
    end
    local i = self:nodeAt(x, y)
    if not i then return end
    local n = self.nodes[i]
    if not self:unlocked(i) then
        n.shake = 0.35
        Audio.play("ui_back", 0.7)
        return
    end
    n.ss:kick(-4)
    if i == self.sel then
        Audio.play("ui_click")
        self:play(i)
    else
        self:select(i)
    end
end

function C:mousereleased(x, y, b) self.back:mousereleased(x, y, b) end

function C:wheelmoved(_, dy)
    self.scroll.target = U.clamp(self.scroll.target - dy * 120, 0, self.maxScroll)
end

function C:keypressed(key)
    if key == "escape" then Audio.play("ui_back"); M.switch("menu"); return end
    if key == "up" or key == "left" then
        if self.sel > 1 then self:select(self.sel - 1) end
    elseif key == "down" or key == "right" then
        if self.sel < Levels.count and self:unlocked(self.sel + 1) then self:select(self.sel + 1) end
    elseif key == "return" or key == "space" or key == "kpenter" then
        Audio.play("ui_click")
        self:play(self.sel)
    end
end

return C
