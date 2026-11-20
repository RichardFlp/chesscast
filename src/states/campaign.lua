local Config = require("src.config")
local Screen = require("src.utils.screen")
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

local CAMPAIGN = Config.ui.campaign
local NODE = CAMPAIGN.node
local CLIP_X, CLIP_Y, CLIP_W = 0, 0, Screen.W
local CLIP_H = Screen.H - CAMPAIGN.footer.height
local SCALE = CAMPAIGN.scale
local floor, sin = math.floor, math.sin
local DIFF = {}
for i, level in ipairs(Search.LEVELS) do DIFF[i] = level.name end

local function quads(img, n, w, h)
    local q = {}
    for i = 1, n do q[i] = love.graphics.newQuad((i - 1) * w, 0, w, h, img:getDimensions()) end
    return q
end

function C:load()
    if self.img then return end
    local function img(n, w, h) return A.image(Config.assets.campaign .. n .. ".png", w, h) end
    self.img = {
        done = img("node_done", NODE.size, NODE.size), current = img("node_current", NODE.size, NODE.size),
        locked = img("node_locked", NODE.size, NODE.size),
        boss = img("node_boss", NODE.bossSize, NODE.bossSize), bossLocked = img("node_boss_locked", NODE.bossSize, NODE.bossSize),
        map = A.image(Config.assets.campaign .. "map.png", CAMPAIGN.mapW, CAMPAIGN.mapH),
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
            local sz = (lv.boss and NODE.bossSize or NODE.size) * SCALE
            local pt = path.nodes[lv.index]
            self.nodes[lv.index] = { lv = lv, x = pt.x, y = pt.y, r = sz / 2 * NODE.radius, sz = sz,
                ss = Spring.new(1, NODE.spring[1], NODE.spring[2]), shake = 0 }
        end
    end
    self.maxScroll = math.max(0, self.mapH - CLIP_H)
    self.eyes = {}
    for i, e in ipairs(path.eyes) do
        self.eyes[i] = { x = e.x, y = e.y, off = love.math.random() * 40, rate = 0.6 + love.math.random() * 0.5 }
    end
    self.flies = {}
    for i = 1, 70 do
        self.flies[i] = { x = love.math.random() * Screen.W, y = love.math.random() * self.mapH,
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
    self.scroll = Spring.new(0, CAMPAIGN.scrollSpring[1], CAMPAIGN.scrollSpring[2])
    local prog = Levels.progress()
    self.sel = math.min(prog + 1, Levels.count)
    self:centerOn(self.sel, true)
    self.bubble = Spring.new(0, CAMPAIGN.bubbleSpring[1], CAMPAIGN.bubbleSpring[2])
    self.bubble.target = 1
    local back = CAMPAIGN.back
    self.back = Button.new { x = back.x, y = back.y, w = back.w, h = back.h, label = "BACK", backSound = true,
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
    if not self:unlocked(i) then return end
    local lv = Levels.flat[i]
    M.switch("game", {
        mode = "cpu", human = lv.human, difficulty = lv.difficulty, spells = true, clock = 0,
        fen = lv.fen, ai = lv.ai, mana = 1,
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
    local top, bottom = n.y - n.r - NODE.topMargin, n.y + n.r + NODE.bottomMargin
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
    if cur <= Levels.count and love.math.random() < dt * NODE.spawnRate then self:burst(cur, 1) end
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
    if i == self.sel and self:unlocked(i) then bob = floor(sin(self.t * 3) * NODE.bobAmplitude + 0.5) * 2 end
    local sx = n.x
    if n.shake > 0 then sx = sx + floor(sin(n.shake * NODE.shakeSpeed) * n.shake * NODE.shakeAmp / 2 + 0.5) * 2 end
    local w, h = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, floor(sx), floor(sy) + bob, 0, SCALE * n.ss.x, SCALE * n.ss.x, w / 2, h / 2)
    if i == prog + 1 and not lv.boss then
        local f = floor(self.t * 6) % 8 + 1
        love.graphics.draw(self.img.ring, self.q.ring[f], floor(sx), floor(sy) + bob,
            0, SCALE * NODE.ringScale, SCALE * NODE.ringScale, NODE.ringPivot, NODE.ringPivot)
    end
    if i == prog + 1 and lv.boss then
        local f = floor(self.t * 6) % 8 + 1
        love.graphics.draw(self.img.ring, self.q.ring[f], floor(sx), floor(sy) + bob,
            0, SCALE * NODE.bossRingScale, SCALE * NODE.bossRingScale, NODE.ringPivot, NODE.ringPivot)
    end
end

function C:bubbleRect()
    local n = self.nodes[self.sel]
    local label = self.sel <= Levels.progress() and "REPLAY" or "START"
    local w = Text.width(label, 3) + 64
    local sy = CLIP_Y + n.y - self.scroll.x
    local pop = U.clamp(self.bubble.x, 0, 1.3)
    local bob = floor(sin(self.t * 3) * NODE.bobAmplitude + 0.5) * 2
    local bubble = CAMPAIGN.bubble
    local h = bubble.h
    local y = sy - n.r - bubble.above - (1 - pop) * bubble.popInset + bob
    return n.x - w / 2, y, w, h, label, pop
end

function C:drawBubble()
    if not self:unlocked(self.sel) then return end
    local x, y, w, h, label, pop = self:bubbleRect()
    if pop <= 0.02 then return end
    local cx = x + w / 2
    local bubble = CAMPAIGN.bubble
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", x + bubble.shadow, y + bubble.shadow, w, h)
    Pal.set(Pal.C)
    love.graphics.rectangle("fill", x, y, w, h)
    for k = 0, bubble.tailSteps do
        love.graphics.rectangle("fill", cx - 16 + k * 4, y + h + k * 4, 32 - k * 8, 4)
    end
    Text.print(label, cx, y + (h - 21) / 2, 3, Pal.N, "center")
end

function C:drawMascot()
    local prog = Levels.progress()
    local i = math.min(prog + 1, Levels.count)
    local n = self.nodes[i]
    local sy = CLIP_Y + n.y - self.scroll.x
    local right = n.x < Screen.W / 2
    local mascot = CAMPAIGN.mascot
    local mx = n.x + (right and 1 or -1) * (n.r + mascot.offset)
    local f = floor(self.t * 3) % 6 + 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.img.mascot, self.q.mascot[f], floor(mx / 2) * 2, floor(sy / 2) * 2, 0,
        right and mascot.frameScale or -mascot.frameScale, mascot.frameScale, mascot.pivot, mascot.pivot)
end

function C:drawSparks()
    love.graphics.setColor(1, 1, 1, 1)
    for _, s in ipairs(self.sparks) do
        local f = U.clamp(floor(s.t / s.life * 7) + 1, 1, 7)
        local sx = floor(s.x / 2) * 2
        local sy = floor((CLIP_Y + s.y - self.scroll.x) / 2) * 2
        local spark = CAMPAIGN.spark
        love.graphics.draw(self.img.spark, self.q.spark[f], sx, sy, 0,
            spark.frameScale, spark.frameScale, spark.pivot, spark.pivot)
    end
end

function C:drawHeaders()
    for _, h in ipairs(self.headers) do
        local header = CAMPAIGN.header
        local y = CLIP_Y + h.y - self.scroll.x + header.offsetY
        if y > -100 and y < CLIP_H then
            local x, w = header.x, header.w
            Pal.set(Pal.N)
            love.graphics.rectangle("fill", x + 8, y + 8, w, header.h)
            love.graphics.setColor(1, 1, 1, 1)
            A.ui.panel_small:draw(x, y, w, header.h, 2)
            Text.print(h.unit.title, x + w / 2, y + header.titleY, 2, Pal.B, "center")
            Text.print(h.unit.sub, x + w / 2, y + header.subY, 3, Pal.C, "center", Pal.N)
        end
    end
end

function C:drawInfo()
    local lv = Levels.flat[self.sel]
    local info = CAMPAIGN.info
    local x, y, w, h = info.x, info.y, info.w, info.h
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", x + 8, y + 8, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    A.ui.panel_large:draw(x, y, w, h, 2)
    local state = self.sel <= Levels.progress() and "CLEARED" or (self:unlocked(self.sel) and "READY" or "LOCKED")
    Text.print("LEVEL " .. lv.index, x + w / 2, y + info.levelY, 3, Pal.B, "center")
    Text.print(lv.name, x + w / 2, y + info.nameY, 6, Pal.C, "center", Pal.N)
    Text.print(lv.boss and "BOSS" or "DUEL", x + w / 2, y + info.typeY, 3, lv.boss and Pal.C or Pal.B, "center", Pal.N)
    Text.print(DIFF[lv.difficulty] .. " CPU", x + w / 2, y + info.diffY, 3, Pal.C, "center", Pal.N)
    Text.print("YOU PLAY " .. (lv.human == 1 and "WHITE" or "BLACK"), x + w / 2, y + info.sideY, 2, Pal.B, "center")
    Frame.divider(x + info.dividerPad, y + info.dividerY, w - info.dividerPad * 2)
    Text.print(state, x + w / 2, y + info.stateY, 3, state == "LOCKED" and Pal.I or Pal.C, "center", Pal.N)
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
    love.graphics.draw(self.img.map, 0, floor(-self.scroll.x), 0, SCALE, SCALE)
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
    local footer = CAMPAIGN.footer
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", 0, Screen.H - footer.height, Screen.W, footer.height)
    Text.print("UP DOWN SELECT    ENTER PLAY    ESC BACK", footer.inset, footer.textY, 2, Pal.B, "left")
    local cleared = Levels.progress() .. " OF " .. Levels.count .. " CLEARED"
    Text.print(cleared, Screen.W - footer.inset, footer.textY, 2, Pal.B, "right")
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
