local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local Screen = require("src.utils.screen")
local Spring = require("src.utils.spring")
local Particles = require("src.animations.particles")
local Audio = require("src.audio.audio")
local App = require("src.app")
local E = require("src.utils.easing")
local Board = require("src.chess.board")

local BV = {}
BV.__index = BV

local X0, Y0, S = 576, 152, 96
BV.X, BV.Y, BV.S, BV.W = X0, Y0, S, S * 8
local TRAY_X, TRAY_W = 544, 832
local TOP_TRAY_Y, BOT_TRAY_Y, TRAY_H = 20, 960, 88
local TRAY_STEP = 48

local abs, floor, sin, pi, min, max = math.abs, math.floor, math.sin, math.pi, math.min, math.max
local random = love.math.random
local lg = love.graphics

local FILES = { "A", "B", "C", "D", "E", "F", "G", "H" }
local RANKS = { "1", "2", "3", "4", "5", "6", "7", "8" }
local PROMO_TYPES = { Board.Q, Board.N, Board.R, Board.B }
local DIFF_STR = {}
for i = 1, 40 do DIFF_STR[i] = "+" .. i end

local function round(v) return floor(v + 0.5) end

function BV.new(match, opts)
    opts = opts or {}
    local v = setmetatable({}, BV)
    v.match = match
    v.bottom = opts.bottom or 1
    v.flip = v.bottom == -1
    v.interactive = false
    v.sprites, v.list = {}, {}
    v.seen = {}
    v.fx = Particles.new(900)
    v.rings = {}
    for i = 1, 24 do v.rings[i] = { on = false, x = 0, y = 0, t = 0, life = 0, r0 = 0, r1 = 0, col = Pal.C } end
    v.moves = {}
    v.nMoves = 0
    v.targets = {}
    v.t = 0
    v.checkPulse = 0
    v.kingShake = 0
    v.pickSet = {}
    v.headTop = opts.topLabel or "TAKEN FROM BLACK"
    v.headBot = opts.bottomLabel or "TAKEN FROM WHITE"
    v.drag = { on = false, moved = false, x = 0, y = 0, ox = 0, oy = 0, sx = 0, sy = 0 }
    v:sync(nil, true)
    return v
end

function BV:squareXY(s)
    local f, r = Board.FILE[s], Board.RANK[s]
    if self.flip then return X0 + (7 - f) * S, Y0 + r * S end
    return X0 + f * S, Y0 + (7 - r) * S
end

function BV:squareAt(x, y)
    if x < X0 or y < Y0 or x >= X0 + 8 * S or y >= Y0 + 8 * S then return nil end
    local c, row = floor((x - X0) / S), floor((y - Y0) / S)
    if self.flip then return Board.sq(7 - c, row) end
    return Board.sq(c, 7 - row)
end

function BV:squareCenter(s)
    local x, y = self:squareXY(s)
    return x + S / 2, y + S / 2
end

function BV:traySlot(side, i)
    local y = (side == self.bottom) and (BOT_TRAY_Y + 12) or (TOP_TRAY_Y + 14)
    return TRAY_X + 24 + (i - 1) * TRAY_STEP, y
end

local function trayIndex(board, id)
    for side = 1, -1, -2 do
        local l = board.captured[side]
        for i = 1, #l do if l[i].id == id then return side, i end end
    end
    return nil
end

local function animK() return App.animScale() end
local function durScale() return 0.6 + 0.4 * animK() end

function BV:newSprite(id, pc, s)
    local x, y = self:squareXY(s)
    local sp = {
        id = id, side = pc > 0 and 1 or -1, t = abs(pc), sq = s,
        x = x, y = y, fx = x, fy = y, tx = x, ty = y,
        moving = false, top = false, mt = 0, dur = 0, delay = 0, arc = 0,
        state = "board", st = 0, sdelay = 0,
        squash = Spring.new(0, 520, 16), lift = Spring.new(0, 380, 26),
        flash = 0, alpha = 1, scale = 3, rot = 0, pendingType = nil,
        phase = random() * pi * 2, drop = 0,
    }
    self.sprites[id] = sp
    self.list[#self.list + 1] = sp
    return sp
end

function BV:startMove(sp, s, delay, fast)
    local x, y = self:squareXY(s)
    sp.fx, sp.fy = sp.x, sp.y
    sp.tx, sp.ty = x, y
    sp.sq = s
    local d = math.sqrt((x - sp.x) ^ 2 + (y - sp.y) ^ 2) / S
    sp.dur = (0.16 + 0.05 * min(d, 7)) * durScale() * (fast and 0.6 or 1)
    sp.delay = delay or 0
    sp.mt = 0
    sp.arc = (sp.t == Board.N and 46 or 10 + 3 * min(d, 6)) * min(1.4, animK())
    if fast then sp.arc = sp.arc * 0.3 end
    sp.moving = true
    return sp.delay + sp.dur
end

function BV:promoteFx(sp, t)
    sp.t = t
    sp.flash = 1
    sp.squash:kick(-4)
    local cx, cy = sp.x + S / 2, sp.y + S / 2
    self.fx:burst(cx, cy, 26, 260, { Pal.C, Pal.B, Pal.C }, 0.8, 4, 0)
    self.fx:sparkle(sp.x + 16, sp.y + 10, S - 32, S - 20, 14, { Pal.C, Pal.B }, 90)
    self:ring(cx, cy, 10, 70, 0.45, Pal.C)
    Audio.play("spell", 1.2)
end

function BV:ring(x, y, r0, r1, life, col)
    for i = 1, #self.rings do
        local r = self.rings[i]
        if not r.on then
            r.on, r.x, r.y, r.t, r.life, r.r0, r.r1, r.col = true, x, y, 0, life, r0, r1, col or Pal.C
            return
        end
    end
end

function BV:sync(info, intro)
    local b = self.match.board
    local seen = self.seen
    for k in pairs(seen) do seen[k] = nil end
    local lastArrive = 0
    for s = 1, 64 do
        local id = b.id[s]
        if id ~= 0 then
            seen[id] = true
            local pc = b.p[s]
            local sp = self.sprites[id]
            if not sp then
                sp = self:newSprite(id, pc, s)
                if intro then
                    local row = Board.RANK[s]
                    if pc < 0 then row = 7 - row end
                    sp.drop = 1
                    sp.delay = 0.15 + row * 0.07 + Board.FILE[s] * 0.018
                    sp.dur = 0.42
                    sp.mt = 0
                else
                    sp.drop = 1
                    sp.delay, sp.dur, sp.mt = 0, 0.38, 0
                    local cx, cy = self:squareCenter(s)
                    self.fx:burst(cx, cy, 18, 200, { Pal.C, Pal.B }, 0.7, 4, 0)
                    self:ring(cx, cy, 10, 64, 0.4, Pal.B)
                end
            else
                if sp.state ~= "board" then

                    sp.state, sp.alpha, sp.scale, sp.rot = "board", 1, 3, 0
                    local x, y = self:squareXY(s)
                    sp.x, sp.y, sp.sq, sp.moving, sp.top = x, y, s, false, false
                    sp.drop, sp.delay, sp.dur, sp.mt = 1, 0, 0.38, 0
                end
                sp.side = pc > 0 and 1 or -1
                if sp.sq ~= s then
                    local rook = info and info.castle and abs(pc) == Board.R
                    local fast = self.dropped and info ~= nil and info.to == s
                    lastArrive = max(lastArrive, self:startMove(sp, s, rook and 0.08 or 0, fast))

                    if rook then sp.arc, sp.top = 64 * min(1.4, animK()), true end
                end
                local t = abs(pc)
                if t ~= sp.t then
                    if sp.moving then sp.pendingType = t else self:promoteFx(sp, t) end
                end
            end
        end
    end
    self.dropped = false

    for i = 1, #self.list do
        local sp = self.list[i]
        if not seen[sp.id] and sp.state == "board" then
            local side, idx = trayIndex(b, sp.id)
            sp.moving = false
            if idx then
                sp.state = "dying"
                sp.st = 0
                sp.sdelay = lastArrive > 0 and lastArrive * 0.86 or 0
                sp.traySide = side
            else
                sp.state = "vanish"
                sp.st = 0
                sp.sdelay = lastArrive * 0.86
            end
        end
    end
    self:refreshSelection()
end

function BV:refreshSelection()
    if self.sel then
        local b = self.match.board
        if b.p[self.sel] == 0 or (b.p[self.sel] > 0) ~= (b.side > 0) then self:deselect() else self:select(self.sel) end
    end
end

function BV:busy()
    for i = 1, #self.list do
        local sp = self.list[i]
        if sp.moving or sp.state == "dying" or sp.state == "vanish" or sp.drop > 0 then
            return true
        end
    end
    return false
end

function BV:isFlying(id)
    local sp = self.sprites[id]
    return sp ~= nil and sp.state ~= "board" and sp.state ~= "tray"
end

function BV:select(s)
    self.sel = s
    local n = self.match:movesFrom(s, self.moves)
    self.nMoves = n
    local t = self.targets
    for i = 1, 64 do t[i] = nil end
    local b = self.match.board
    for i = 1, n do
        local m = self.moves[i]
        local to = Board.to(m)
        t[to] = (b.p[to] ~= 0 or Board.flag(m) == 2) and 2 or 1
    end
end

function BV:deselect()
    self.sel = nil
    self.nMoves = 0
    for i = 1, 64 do self.targets[i] = nil end
end

function BV:setPick(squares, onPick)
    for i = 1, 64 do self.pickSet[i] = nil end
    if squares then
        for _, s in ipairs(squares) do self.pickSet[s] = true end
        self.onPick = onPick
        self:deselect()
    else
        self.onPick = nil
    end
end

function BV:tryMove(to)
    local from = self.sel
    local cnt, first = 0, nil
    for i = 1, self.nMoves do
        if Board.to(self.moves[i]) == to then cnt = cnt + 1; first = first or self.moves[i] end
    end
    if cnt == 0 then return false end
    if cnt > 1 then

        self.promo = { from = from, to = to, side = self.match.board.side, t = 0 }
        return true
    end
    self:deselect()
    if self.onMove then self.onMove(first) end
    return true
end

function BV:promoSquares()
    local p = self.promo
    local x, y = self:squareXY(p.to)
    local dir = (y == Y0) and 1 or -1
    return x, y, dir
end

function BV:mousepressed(x, y, button)
    if button ~= 1 then
        if button == 2 then self:deselect(); self.promo = nil end
        return false
    end
    if self.promo then
        local px, py, dir = self:promoSquares()
        for i = 1, 4 do
            local ry = py + (i - 1) * dir * S
            if x >= px and x < px + S and y >= ry and y < ry + S then
                local p = self.promo
                self.promo = nil
                self:deselect()
                local m = self.match:findMove(p.from, p.to, PROMO_TYPES[i])
                if m and self.onMove then Audio.play("ui_click"); self.onMove(m) end
                return true
            end
        end
        self.promo = nil
        Audio.play("ui_back")
        return true
    end
    local s = self:squareAt(x, y)
    if not s then return false end
    if self.onPick then
        if self.pickSet[s] then self.onPick(s) else Audio.play("ui_back") end
        return true
    end
    if not self.interactive then return false end
    local b = self.match.board
    local pc = b.p[s]
    if pc ~= 0 and (pc > 0) == (b.side > 0) then
        local was = self.sel == s
        if not was then
            self:select(s)
            Audio.play("ui_hover", 1.1)
        end
        local sp = self.sprites[b.id[s]]
        if sp and not sp.moving then
            local d = self.drag
            local sx, sy = self:squareXY(s)
            d.on, d.moved, d.sq, d.was = true, false, s, was
            d.ox, d.oy = x - sx, y - sy
            d.sx, d.sy = x, y
            d.x, d.y = x, y
            d.id = sp.id
        end
        return true
    end
    if self.sel then
        if not self:tryMove(s) then
            self:deselect()
            Audio.play("ui_back")
        end
        return true
    end
    return false
end

function BV:mousereleased(x, y, button)
    local d = self.drag
    if button ~= 1 or not d.on then return end
    d.on = false
    local sp = self.sprites[d.id]
    if not d.moved then

        if d.was then self:deselect() end
        return
    end
    local s = self:squareAt(x, y)
    if s and s ~= d.sq and self.sel and self.targets[s] then
        if sp then sp.x, sp.y = d.x - d.ox, d.y - d.oy end
        self.dropped = true
        if not self:tryMove(s) then self.dropped = false end
        if self.promo and sp then

            local ox, oy = self:squareXY(d.sq)
            sp.x, sp.y = ox, oy
        end
    elseif sp then

        sp.x, sp.y = d.x - d.ox, d.y - d.oy
        self:startMove(sp, d.sq, 0, true)
    end
end

function BV:keypressed(key)
    if key == "escape" and (self.promo or self.sel) then
        self.promo = nil
        self:deselect()
        return true
    end
    return false
end

function BV:update(dt, mx, my)
    self.t = self.t + dt
    self.mx, self.my = mx, my
    local b = self.match.board
    local d = self.drag
    if d.on then
        d.x, d.y = mx, my
        if not d.moved and (abs(mx - d.sx) > 8 or abs(my - d.sy) > 8) then d.moved = true end
    end
    self.hover = self:squareAt(mx, my)
    if self.promo then self.promo.t = self.promo.t + dt end
    self.fx.intensity = animK()

    if self.match.check then
        if not self.wasCheck then self.kingShake = 0.55 end
        self.checkPulse = self.checkPulse + dt
    else
        self.checkPulse = 0
    end
    self.wasCheck = self.match.check
    if self.kingShake > 0 then self.kingShake = self.kingShake - dt end

    local list = self.list
    local i = 1
    while i <= #list do
        local sp = list[i]
        local remove = false
        sp.squash.target = 0
        sp.squash:update(dt)
        local liftT = 0
        if sp.state == "board" and not sp.moving then
            if self.sel == sp.sq and not (d.on and d.moved and d.id == sp.id) then liftT = -12
            elseif self.interactive and self.hover == sp.sq and b.p[sp.sq] ~= 0
                and (b.p[sp.sq] > 0) == (b.side > 0) and not self.onPick then liftT = -6 end
        end
        sp.lift.target = liftT
        sp.lift:update(dt)
        if sp.flash > 0 then sp.flash = max(0, sp.flash - dt * 3) end

        if sp.drop > 0 then
            sp.mt = sp.mt + dt
            local u = (sp.mt - sp.delay) / sp.dur
            if u >= 1 then
                sp.drop = 0
                sp.squash:kick(3.5)
                local x, y = self:squareXY(sp.sq)
                sp.x, sp.y = x, y
                self:dust(x + S / 2, y + S - 8, 4)
            end
        elseif sp.moving then
            sp.mt = sp.mt + dt
            local u = (sp.mt - sp.delay) / sp.dur
            if u >= 1 then
                sp.moving = false
                sp.top = false
                sp.x, sp.y = sp.tx, sp.ty
                sp.squash:kick(4.5 * min(1.3, animK() + 0.2))
                self:dust(sp.x + S / 2, sp.y + S - 8, 6)
                if sp.pendingType then
                    self:promoteFx(sp, sp.pendingType)
                    sp.pendingType = nil
                end
                if not sp.silent then Audio.play("move", 0.95 + random() * 0.1) end
                sp.silent = false
            elseif u > 0 then
                local e = E.outCubic(u)
                sp.x = sp.fx + (sp.tx - sp.fx) * e
                sp.y = sp.fy + (sp.ty - sp.fy) * e - sp.arc * sin(pi * u)
            end
        elseif sp.state == "dying" then
            sp.st = sp.st + dt
            if sp.st >= sp.sdelay then

                sp.state = "flying"
                sp.st = 0
                sp.flash = 1
                local cx, cy = sp.x + S / 2, sp.y + S / 2
                self.fx:burst(cx, cy, 30, 340, { Pal.C, Pal.B, Pal.N }, 0.7, 4, 400)
                self:ring(cx, cy, 12, 80, 0.35, Pal.C)
                Screen.shake(2 * animK(), 0.18)
                Audio.play("capture", 0.95 + random() * 0.1)
                sp.fx, sp.fy = sp.x, sp.y
                sp.dur = 0.62 * durScale()
                sp.rot0 = (random() < 0.5 and -1 or 1)
            end
        elseif sp.state == "flying" then
            sp.st = sp.st + dt
            local u = min(1, sp.st / sp.dur)
            local side, idx = trayIndex(b, sp.id)
            if not idx then
                remove = true
            else
                local tx, ty = self:traySlot(side, idx)

                local e = E.inOutCubic(u)
                local sc = 3 - e
                local cell = 32 * sc
                local fx, fy = sp.fx + 48 - cell / 2, sp.fy + 96 - cell
                sp.x = fx + (tx - fx) * e
                sp.y = fy + (ty - fy) * e - 120 * sin(pi * u) * min(1.2, animK() + 0.2)
                sp.scale = sc
                sp.rot = sp.rot0 * sin(pi * u) * 0.35
                if u >= 1 then
                    sp.state = "tray"
                    self.fx:burst(tx + 32, ty + 40, 8, 120, { Pal.C, Pal.B }, 0.4, 2, 0)
                    remove = true
                end
            end
        elseif sp.state == "vanish" then
            sp.st = sp.st + dt
            if sp.st >= sp.sdelay then
                if not sp.vanished then
                    sp.vanished = true
                    local cx, cy = sp.x + S / 2, sp.y + S / 2
                    self.fx:burst(cx, cy, 36, 300, { Pal.C, Pal.B, Pal.I }, 0.8, 4, -60)
                    self:ring(cx, cy, 12, 90, 0.4, Pal.B)
                end
                sp.alpha = 1 - (sp.st - sp.sdelay) / 0.3
                if sp.alpha <= 0 then remove = true end
            end
        end
        if remove then
            self.sprites[sp.id] = nil
            list[i] = list[#list]
            list[#list] = nil
        else
            i = i + 1
        end
    end

    for j = 2, #list do
        local sp = list[j]
        local y = sp.y
        local k = j - 1
        while k >= 1 and list[k].y > y do
            list[k + 1] = list[k]
            k = k - 1
        end
        list[k + 1] = sp
    end

    for j = 1, #self.rings do
        local r = self.rings[j]
        if r.on then
            r.t = r.t + dt
            if r.t >= r.life then r.on = false end
        end
    end
    self.fx:update(dt)

    local want = false
    if self.promo then want = true
    elseif self.onPick then want = self.hover ~= nil and self.pickSet[self.hover] == true
    elseif self.interactive and self.hover then
        local pc = b.p[self.hover]
        want = (pc ~= 0 and (pc > 0) == (b.side > 0)) or (self.sel ~= nil and self.targets[self.hover] ~= nil)
    end
    self.wantHand = want or d.on
end

function BV:dust(x, y, n)
    local k = animK()
    n = floor(n * k + 0.5)
    for _ = 1, n do
        local dir = random() < 0.5 and -1 or 1
        self.fx:add(x + dir * (14 + random() * 18), y, dir * (40 + random() * 80), -20 - random() * 30,
            0.35 + random() * 0.2, 4, random() < 0.5 and Pal.C or Pal.B, 80, 3, 0)
    end
end

local function rect(x, y, w, h) lg.rectangle("fill", x, y, w, h) end

local function frameRect(x, y, w, h, t)
    rect(x, y, w, t); rect(x, y + h - t, w, t)
    rect(x, y + t, t, h - 2 * t); rect(x + w - t, y + t, t, h - 2 * t)
end

local function corners(x, y, len, t)

    rect(x, y, len, t); rect(x, y, t, len)
    rect(x + S - len, y, len, t); rect(x + S - t, y, t, len)
    rect(x, y + S - t, len, t); rect(x, y + S - len, t, len)
    rect(x + S - len, y + S - t, len, t); rect(x + S - t, y + S - len, t, len)
end

function BV:drawBoard()

    Pal.set(Pal.N)
    rect(X0 - 28 + 12, Y0 - 28 + 12, 8 * S + 56, 8 * S + 56)
    lg.setColor(1, 1, 1, 1)
    A.ui.panel_large:draw(X0 - 28, Y0 - 28, 8 * S + 56, 8 * S + 56, 2)
    Pal.set(Pal.N)
    rect(X0 - 4, Y0 - 4, 8 * S + 8, 8 * S + 8)
    for s = 1, 64 do
        local x, y = self:squareXY(s)
        local light = (Board.FILE[s] + Board.RANK[s]) % 2 == 1
        Pal.set(light and Pal.B or Pal.I)
        rect(x, y, S, S)
    end

    Pal.set(Pal.N, 0.35)
    for s = 1, 64 do
        if (Board.FILE[s] + Board.RANK[s]) % 2 == 0 then
            local x, y = self:squareXY(s)
            rect(x + 14, y + 18, 4, 2); rect(x + 70, y + 60, 6, 2); rect(x + 40, y + 82, 2, 2)
        end
    end

    for c = 0, 7 do
        local fileS = self.flip and Board.sq(7 - c, 7) or Board.sq(c, 0)
        local x, y = self:squareXY(fileS)
        local light = (Board.FILE[fileS] + Board.RANK[fileS]) % 2 == 1
        Text.print(FILES[Board.FILE[fileS] + 1], x + S - 6, y + S - 20, 2, light and Pal.N or Pal.C, "right")
        local rankS = self.flip and Board.sq(7, c) or Board.sq(0, 7 - c)
        x, y = self:squareXY(rankS)
        light = (Board.FILE[rankS] + Board.RANK[rankS]) % 2 == 1
        Text.print(RANKS[Board.RANK[rankS] + 1], x + 6, y + 6, 2, light and Pal.N or Pal.C, "left")
    end
end

function BV:drawHighlights()
    local m = self.match
    local lm = m.lastMove
    if lm then
        Pal.set(Pal.C, 0.38)
        local x, y = self:squareXY(lm.from); rect(x, y, S, S)
        x, y = self:squareXY(lm.to); rect(x, y, S, S)
    end

    if self.drawMarks then self.drawMarks(self) end
    if m.check and m.checkSq then
        local x, y = self:squareXY(m.checkSq)
        local a = 0.55 + 0.3 * sin(self.checkPulse * 7)
        Pal.set(Pal.N, a)
        rect(x, y, S, S)
        Pal.set(Pal.C)
        frameRect(x, y, S, S, 4)
    end
    if self.sel then
        local x, y = self:squareXY(self.sel)
        Pal.set(Pal.C, 0.55)
        rect(x, y, S, S)
        Pal.set(Pal.C)
        frameRect(x, y, S, S, 4)
    end

    local h = self.hover
    if self.sel and h and self.targets[h] then
        local x, y = self:squareXY(h)
        Pal.set(Pal.C, 0.4)
        rect(x, y, S, S)
    end

    if self.onPick then
        local a = 0.5 + 0.25 * sin(self.t * 6)
        for s = 1, 64 do
            if self.pickSet[s] then
                local x, y = self:squareXY(s)
                Pal.set(Pal.C, a * (h == s and 1.4 or 0.6))
                rect(x, y, S, S)
                Pal.set(Pal.N)
                corners(x, y, 20, 6)
                Pal.set(Pal.C)
                corners(x + 2, y + 2, 16, 2)
            end
        end
    end
end

function BV:drawMoveDots()
    for s = 1, 64 do
        local t = self.targets[s]
        if t == 1 then
            local cx, cy = self:squareCenter(s)
            Frame.diamond(cx, cy, 14, Pal.N)
            Frame.diamond(cx, cy, 8, Pal.C)
        end
    end
end

function BV:drawCaptureMarks()
    local bob = floor(sin(self.t * 5) * 1.5 + 0.5) * 2
    for s = 1, 64 do
        if self.targets[s] == 2 then
            local x, y = self:squareXY(s)
            Pal.set(Pal.N)
            corners(x + 2 - bob / 2, y + 2 - bob / 2, 26, 8)
            Pal.set(Pal.C)
            corners(x + 4 - bob / 2, y + 4 - bob / 2, 20, 4)
        end
    end
end

function BV:drawSprite(sp, x, y)
    local img = A.piece[sp.side][sp.t]
    local k = sp.scale
    local q = sp.squash.x
    if q > 0.3 then q = 0.3 elseif q < -0.3 then q = -0.3 end
    local sx, sy = k * (1 + q * 0.5), k * (1 - q * 0.6)
    local cell = 32 * k
    local cx, by = x + cell / 2, y + cell
    local lift = sp.lift.x
    local a = sp.alpha

    if sp.state == "board" or sp.state == "dying" then
        local h = -lift
        Pal.set(Pal.N, 0.45 * a)
        lg.ellipse("fill", round(cx), round(by - 8), 30 - h * 0.3, 8 - h * 0.08)
    end
    local dx = round(cx - 16 * sx)
    local dy = round(by - 32 * sy + lift)
    if sp.rot ~= 0 then
        lg.setColor(1, 1, 1, a)
        lg.draw(img, round(cx), round(by - 16 * sy + lift), sp.rot, sx, sy, 16, 16)
    else
        lg.setColor(1, 1, 1, a)
        lg.draw(img, dx, dy, 0, sx, sy)
    end
    if sp.flash > 0 then
        Screen.flat(true)
        Pal.set(Pal.C, sp.flash)
        if sp.rot ~= 0 then
            lg.draw(img, round(cx), round(by - 16 * sy + lift), sp.rot, sx, sy, 16, 16)
        else
            lg.draw(img, dx, dy, 0, sx, sy)
        end
        Screen.flat(false)
    end
end

function BV:drawPieces()
    self:drawPieceLayer(false)
    self:drawPieceLayer(true)
    self:drawDragged()
end

function BV:drawPieceLayer(top)
    local d = self.drag
    local m = self.match
    local kingId = m.check and m.checkSq and m.board.id[m.checkSq] or 0
    for i = 1, #self.list do
        local sp = self.list[i]
        if (sp.top or false) == top and (sp.state == "board" or sp.state == "dying" or sp.state == "vanish") then
            if not (d.on and d.moved and d.id == sp.id) then
                local x, y = sp.x, sp.y
                local waiting = false
                if sp.drop > 0 then
                    local u = (sp.mt - sp.delay) / sp.dur
                    if u < 0 then
                        waiting = true
                    else
                        local tx, ty = self:squareXY(sp.sq)
                        x = tx
                        y = ty - (1 - E.outQuad(math.min(1, u))) * 140
                        sp.alpha = min(1, u * 3)
                    end
                elseif sp.state == "board" and sp.drop == 0 and not sp.moving then
                    sp.alpha = 1
                end
                if not waiting then

                    if sp.state == "board" and not sp.moving and sp.drop == 0 and sp.side == m.board.side then
                        if sin(self.t * 2.2 + sp.phase) > 0.6 then y = y - 2 end
                    end
                    if sp.id == kingId and self.kingShake > 0 then
                        x = x + floor(sin(self.kingShake * 60) * 3 + 0.5) * 2
                    end
                    self:drawSprite(sp, x, y)
                end
            end
        end
    end
end

function BV:drawDragged()
    local d = self.drag
    if d.on and d.moved then
        local sp = self.sprites[d.id]
        if sp then
            local gx, gy = self:squareXY(d.sq)
            Screen.flat(true)
            Pal.set(Pal.N, 0.4)
            lg.draw(A.piece[sp.side][sp.t], gx, gy, 0, 3, 3)
            Screen.flat(false)
            self:drawSprite(sp, d.x - d.ox, d.y - d.oy - 10)
        end
    end
end

function BV:drawFlying()
    for i = 1, #self.list do
        local sp = self.list[i]
        if sp.state == "flying" then self:drawSprite(sp, sp.x, sp.y) end
    end
end

function BV:drawEffects()
    for j = 1, #self.rings do
        local r = self.rings[j]
        if r.on then
            local u = r.t / r.life
            local rad = r.r0 + (r.r1 - r.r0) * E.outCubic(u)
            Pal.set(r.col, 1 - u)
            lg.setLineWidth(4)
            lg.rectangle("line", round(r.x - rad), round(r.y - rad), round(rad * 2), round(rad * 2))
            lg.setLineWidth(1)
        end
    end
    self.fx:draw()
end

function BV:drawPromo()
    local p = self.promo
    if not p then return end
    local px, py, dir = self:promoSquares()
    local top = dir == 1 and py or py - 3 * S
    Pal.set(Pal.N, 0.6)
    rect(X0, Y0, 8 * S, 8 * S)
    Pal.set(Pal.N)
    rect(px - 8 + 8, top - 8 + 8, S + 16, 4 * S + 16)
    lg.setColor(1, 1, 1, 1)
    A.ui.dialogue:draw(px - 8, top - 8, S + 16, 4 * S + 16, 2)
    for i = 1, 4 do
        local ry = py + (i - 1) * dir * S
        local hov = self.mx and self.mx >= px and self.mx < px + S and self.my >= ry and self.my < ry + S
        if hov then
            Pal.set(Pal.B)
            rect(px, ry, S, S)
        end
        local u = min(1, p.t * 6 - (i - 1) * 0.4)
        if u > 0 then
            local k = 3 * E.outBack(u)
            local img = A.piece[p.side][PROMO_TYPES[i]]
            lg.setColor(1, 1, 1, 1)
            lg.draw(img, round(px + S / 2 - 16 * k), round(ry + S / 2 - 16 * k - (hov and 6 or 0)), 0, k, k)
        end
    end
end

local function trayFrame(x, y, w, h, label, labelBelow)
    Pal.set(Pal.N)
    rect(x + 8, y + 8, w, h)
    lg.setColor(1, 1, 1, 1)
    A.ui.panel_small:draw(x, y, w, h, 2)
    local tw = Text.width(label, 2) + 40
    local ty = labelBelow and (y + h - 14) or (y - 14)
    lg.setColor(1, 1, 1, 1)
    A.ui.tooltip:draw(x + 28, ty, tw, 28, 2)
    Text.print(label, x + 28 + tw / 2, ty + 7, 2, Pal.C, "center")
end

function BV:drawTrays()
    local b = self.match.board
    trayFrame(TRAY_X, TOP_TRAY_Y, TRAY_W, TRAY_H, self.headTop, false)
    trayFrame(TRAY_X, BOT_TRAY_Y, TRAY_W, TRAY_H, self.headBot, true)
    for side = 1, -1, -2 do
        local l = b.captured[side]
        for i = 1, #l do
            local c = l[i]
            if not self:isFlying(c.id) then
                local x, y = self:traySlot(side, i)
                lg.setColor(1, 1, 1, 1)
                lg.draw(A.piece[side][c.t], x, y, 0, 2, 2)
            end
        end
    end

    local diff = self.match:materialDiff(self.bottom)
    if diff ~= 0 then
        local str = DIFF_STR[min(40, abs(diff))]
        local y = diff > 0 and (TOP_TRAY_Y + 36) or (BOT_TRAY_Y + 36)
        Text.print(str, TRAY_X + TRAY_W - 28, y, 3, Pal.C, "right", Pal.N)
    end
end

function BV:draw()
    self:drawBoard()
    self:drawHighlights()
    self:drawMoveDots()
    self:drawPieces()
    self:drawCaptureMarks()
end

function BV:drawOverlay()
    self:drawFlying()
    self:drawEffects()
    self:drawPromo()
end

return BV
