local Config = require("src.config")
local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local Button = require("src.ui.button")
local Spring = require("src.utils.spring")
local Screen = require("src.utils.screen")
local Audio = require("src.audio.audio")
local U = require("src.utils.util")
local Board = require("src.chess.board")
local Defs = require("src.cards.defs")
local S = require("src.cards.spells")
local Search = require("src.ai.search")
local Sidebar = require("src.ui.sidebar")
local BG = require("src.ui.background")
local CardTip = require("src.ui.cardtip")

local Layer = {}
Layer.__index = Layer

local lg = love.graphics
local floor, min, max, abs, sin, pi = math.floor, math.min, math.max, math.abs, math.sin, math.pi
local random = love.math.random
local now = love.timer.getTime

local CARD = Config.ui.card
local SIDEBAR = Config.ui.sidebar
local MAX_MANA, MAX_HAND, START_HAND = CARD.maxMana, CARD.maxHand, CARD.startHand
local CARD_W, CARD_H = CARD.width, CARD.height
local CENTER_X, CENTER_Y = Screen.W / 2, CARD.centerY
local CARD_ENTER_X = { [1] = -CARD.enterX, [-1] = Screen.W + CARD.enterX }
local CARD_ENTER_Y_OFFSET = CARD.enterYOffset
local T_IMPACT, T_FADE, T_DONE = CARD.timing.impact, CARD.timing.fade, CARD.timing.done
local CPU_BUDGET = Config.ai.cpuBudget

local IMPACT_COLS = { Pal.C, Pal.B, Pal.I }
local ROLE_COLS = { Pal.R, Pal.RL, Pal.RD }

local function copyCounts(counts)
    local out = {}
    for k, v in pairs(counts) do out[k] = v end
    return out
end
local COST_STR, KEY_SLOT = {}, {}
for i = 0, MAX_MANA do COST_STR[i] = tostring(i) end
for i = 1, MAX_HAND do
    KEY_SLOT[tostring(i)] = i
    KEY_SLOT["kp" .. i] = i
end

local function rect(x, y, w, h) lg.rectangle("fill", x, y, w, h) end
local function round(v) return floor(v + 0.5) end

local backImg
local function cardBack()
    if backImg then return backImg end
    local CW, CH = Config.assets.imageSizes.cardW, Config.assets.imageSizes.cardH
    local d = love.image.newImageData(CW, CH)
    local N, I, B, C = Pal.N, Pal.I, Pal.B, Pal.C
    d:mapPixel(function(x, y)
        local c = N
        local ex = min(x, CW - 1 - x)
        local ey = min(y, CH - 1 - y)
        local e = min(ex, ey)
        if e == 0 then c = N
        elseif e <= 2 then c = I
        elseif e == 4 then c = B
        else

            local u, v = (x - CW / 2) % 8, (y - CH / 2) % 8
            if abs(u - 4) + abs(v - 4) == 3 then c = I end

            local m = abs(x - (CW / 2 - 0.5)) + abs(y - (CH / 2 - 0.5)) * 0.8
            if m < 15 then c = N end
            if m >= 11 and m < 13 then c = B end
            if m < 6 then c = C end
            if m >= 6 and m < 8 then c = I end
        end
        return c[1], c[2], c[3], 1
    end)
    backImg = love.graphics.newImage(d)
    backImg:setFilter("nearest", "nearest")
    return backImg
end

function Layer.new(game)
    local L = setmetatable({}, Layer)
    L.game, L.match, L.view = game, game.match, game.view
    local m0 = game.match.opts.mana or 0
    L.manaOf = { [1] = m0, [-1] = m0 }
    L.hand = { [1] = {}, [-1] = {} }
    L.deck = { [1] = {}, [-1] = {} }
    L.discard = { [1] = {}, [-1] = {} }
    L.ward = { [1] = 0, [-1] = 0 }
    L.double = {}
    L.lastSpell = {}
    L.castThisTurn = { [1] = false, [-1] = false }
    L.bonusTurn = {}
    L.snaps = {}
    L.casting = nil
    L.sel = nil
    L.hover = nil
    L.t = 0
    L.ver, L.seenVer = 1, 0
    L.turnNo = 0
    L.cpuDone = -1
    L.cpuCo = nil
    L.wantHand = false
    L.tags = { [1] = { "", "" }, [-1] = { "", "" } }
    L.ctxBuf = {}

    local seed = game.params and game.params.seed
    if seed then
        local gen = love.math.newRandomGenerator(seed)
        L.rng = function(n) return gen:random(n) end
    end
    for _, side in ipairs({ 1, -1 }) do
        local deck = L.deck[side]
        for _, def in ipairs(Defs.deck) do deck[#deck + 1] = def end
        U.shuffle(deck, L.rng)
    end
    cardBack()

    local cast = CARD.cast
    L.castBtn = Button.new { x = CENTER_X + cast.dx, y = cast.y, w = cast.w, h = cast.h, label = "CAST", textScale = 2,
        style = "primary", hoverShift = 0, onClick = function() L:confirm() end }
    L.cancelBtn = Button.new { x = CENTER_X + cast.dx + cast.w + cast.gap, y = cast.y,
        w = cast.w, h = cast.h, label = "CANCEL", textScale = 2,
        hoverShift = 0, backSound = true, onClick = function() L:cancel(true) end }

    L.view.drawMarks = function(view) L:drawMarks(view) end

    for _ = 1, START_HAND do
        L:drawCards(1, 1)
        L:drawCards(-1, 1)
    end
    L:onTurnStart(L.match.board.side)
    local roll = L.rng or random
    if #Defs.roles > 0 then
        for _, side in ipairs({ 1, -1 }) do
            if roll(Config.cards.roleOdds) == 1 then
                L:addCard(side, Defs.roles[roll(#Defs.roles)])
            end
        end
    end
    return L
end

function Layer:sidebar(side)
    local g = self.game
    return g.left.side == side and g.left or g.right
end

function Layer:mana(side) return self.manaOf[side] end
function Layer:busy() return self.casting ~= nil end
function Layer:curseActive()
    if self.match.result then return false end
    local c = self.casting
    if c and c.def.role then return true end
    local b = self.match.board
    local ply = b.ply
    for _, e in pairs(b.st) do
        if e.pawned and e.pawned > ply then return true end
    end
    return false
end
function Layer:blocksBoard() return self.sel ~= nil or self.casting ~= nil end
function Layer:dirty() self.ver = self.ver + 1 end

function Layer:activeHuman()
    local m = self.match
    local side = m.board.side
    if not m:isLocal(side) then return nil end
    return side
end

function Layer:faceUp(side)
    local m = self.match
    if m.mode ~= "local" then return m:isLocal(side) end
    return m.board.side == side
end

local function newCard(def, side, x, y)
    return {
        def = def, side = side,
        x = Spring.new(x, 230, 17), y = Spring.new(y, 230, 17),
        rot = Spring.new(0, 300, 13), scale = Spring.new(1, 320, 14),
        lift = Spring.new(0, 340, 15), face = Spring.new(0, 260, 20),
        glow = 0, delay = 0, alpha = 1, ok = false, reason = nil, slot = 1,
    }
end

function Layer:slotCenter(side, i)
    local x, y, w, h = self:sidebar(side):slotRect(i)
    return x + w / 2, y + h / 2
end

function Layer:reslot(side)
    for i, cv in ipairs(self.hand[side]) do cv.slot = i end
end

function Layer:addCard(side, def)
    local hand = self.hand[side]
    if not def or #hand >= MAX_HAND then return false end
    local sb = self:sidebar(side)
    local _, sy = self:slotCenter(side, #hand + 1)
    local cv = newCard(def, side, CARD_ENTER_X[side], sy + CARD_ENTER_Y_OFFSET)
    cv.rot:snap(sb.right and 0.5 or -0.5)
    local pending = 0
    for _, o in ipairs(hand) do if o.delay > 0 then pending = pending + 1 end end
    cv.delay = CARD.enterDelay + pending * CARD.enterStagger
    hand[#hand + 1] = cv
    self:reslot(side)
    self:dirty()
    return true
end

function Layer:drawCards(side, n)
    for _ = 1, n do
        if #self.hand[side] >= MAX_HAND then return end
        local deck = self.deck[side]
        if #deck == 0 then
            local dis = self.discard[side]
            for i = #dis, 1, -1 do deck[#deck + 1] = dis[i]; dis[i] = nil end
            U.shuffle(deck, self.rng)
            if #deck == 0 then return end
        end
        self:addCard(side, table.remove(deck))
    end
end

function Layer:gainMana(side, n)
    self.manaOf[side] = min(MAX_MANA, self.manaOf[side] + n)
    self:dirty()
end

function Layer:removeCard(cv)
    local hand = self.hand[cv.side]
    for i = #hand, 1, -1 do
        if hand[i] == cv then table.remove(hand, i) end
    end
    self:reslot(cv.side)
end

function Layer:snapshotFor(side)
    local ply = self.match.board.ply
    for p = ply - 1, max(0, ply - CARD.snapshotDepth), -1 do
        local e = self.snaps[p]
        if e and e.board.side == side then return e end
    end
    return nil
end

function Layer:ctxFor(side)
    local c = self.ctxBuf
    local e = self:snapshotFor(side)
    c.snapshot = e and e.board or nil
    c.hist = e and e.hist or nil
    c.reps = e and e.reps or nil
    return c
end

function Layer:onTurnStart(side)
    local b = self.match.board
    self.turnNo = self.turnNo + 1
    self.snaps[b.ply] = { board = b:clone(), hist = #self.match.history, reps = copyCounts(self.match.reps) }
    self.snaps[b.ply - CARD.snapshotKeep] = nil
    if self.sel then self:cancel(true) end
    self:dirty()
    if self.bonusTurn[side] then
        self.bonusTurn[side] = nil
        return
    end
    self.manaOf[side] = min(MAX_MANA, self.manaOf[side] + 1)
    self.castThisTurn[side] = false
    self:drawCards(side, 1)
end

function Layer:onMovePlayed(info)
    local side = info.side
    self:dirty()
    if not self.double[side] then return end
    self.double[side] = nil
    local m = self.match
    if m.result or info.check then
        self.game:toast("NO SECOND STRIKE")
        return
    end
    local b = m.board
    local test = b:clone()
    test:passTurn()
    local id = test.id[info.to]
    if id ~= 0 then test:setStatus(id, "frozen", test.ply + 1) end
    if not test:hasLegalMove() then
        self.game:toast("NO SECOND STRIKE")
        return
    end
    b:passTurn()
    if id ~= 0 then b:setStatus(id, "frozen", b.ply + 1) end
    self.bonusTurn[side] = true
    self.game:positionChanged()
    self.game:toast("DOUBLE STRIKE")
    self.game:log(m.players[side].name .. " STRIKES AGAIN")
    self.game:recordNote(side, "STRIKES AGAIN")
end

function Layer:refreshState()
    if self.seenVer == self.ver then return end
    self.seenVer = self.ver
    local b = self.match.board
    for _, side in ipairs({ 1, -1 }) do
        local ctx = self:ctxFor(side)
        for _, cv in ipairs(self.hand[side]) do
            local ok, why = false, "NOT YOUR TURN"
            if b.side == side and not self.match.result then
                ok, why = S.castable(b, side, cv.def, self, ctx)
            end
            cv.ok, cv.reason = ok, why
        end

        local ply = b.ply
        local t1, t2 = "", ""
        if self.ward[side] > ply then t1 = t1 .. "WARD " end
        if self.double[side] or self.bonusTurn[side] then t1 = t1 .. "2X " end
        if b.epAny[side] > ply then t2 = t2 .. "EP " end
        if b.fog[side] > ply then t2 = t2 .. "FOG " end
        if b.lastStand[side] > ply then t2 = t2 .. "LAST" end
        self.tags[side][1], self.tags[side][2] = t1, t2
    end
end

function Layer:canInteract(side)
    local g, m, v = self.game, self.match, self.view
    return g.started and not m.result and not self.casting and not v.promo and not v:busy()
        and self:activeHuman() == side
end

function Layer:deny(cv)
    cv.rot:kick(cv.side == 1 and 9 or -9)
    cv.x:kick(140)
    Audio.play("ui_back", 0.9)
    if cv.reason then self.game:toast(cv.reason) end
end

function Layer:clickCard(cv)
    if not self:canInteract(cv.side) or cv.delay > 0 then
        return
    end
    if self.sel and self.sel.card == cv then
        self:cancel(true)
        return
    end
    self:refreshState()
    if not cv.ok then
        self:deny(cv)
        return
    end
    if self.sel then self:cancel(false) end
    local def = cv.def
    self.sel = { card = cv, step = def.steps == 0 and 0 or 1, a = nil }
    cv.lift:kick(-900)
    cv.scale:kick(2.5)
    Audio.play("card_select")
    self.view:deselect()
    if def.steps > 0 then
        local side = cv.side
        local ctx = self:ctxFor(side)
        local list = S.firstTargets(self.match.board, side, def, ctx)
        self.view:setPick(list, function(s) self:pick(s) end)
    end
end

function Layer:pick(s)
    local sel = self.sel
    if not sel then return end
    local cv = sel.card
    local def, side = cv.def, cv.side
    local ctx = self:ctxFor(side)
    local fx, fy = self.view:squareCenter(s)
    self.game.fx:burst(fx, fy, 10, 160, { Pal.C, Pal.B }, 0.4, 4, 0)
    if sel.step == 1 and def.pick2 then
        sel.a = s
        sel.step = 2
        Audio.play("ui_click", 1.1)
        local list = S.secondTargets(self.match.board, side, def, s, ctx)
        self.view:setPick(list, function(t) self:pick(t) end)
        return
    end
    if sel.step == 1 then
        self:beginCast(side, cv, s, nil)
    else
        self:beginCast(side, cv, sel.a, s)
    end
end

function Layer:confirm()
    local sel = self.sel
    if sel and sel.step == 0 then self:beginCast(sel.card.side, sel.card, nil, nil) end
end

function Layer:cancel(sound)
    if not self.sel then return false end
    self.sel = nil
    self.view:setPick(nil)
    if sound ~= false then Audio.play("ui_back") end
    return true
end

function Layer:discardCard(side, def)
    if def.role then return end
    local dis = self.discard[side]
    dis[#dis + 1] = def
end

function Layer:beginCast(side, cv, a, c)
    local def = cv.def
    local b = self.match.board
    local ctx = self:ctxFor(side)

    self.casting = {
        card = cv, side = side, def = def, a = a, c = c, t = 0, hit = false,
        ctx = { snapshot = ctx.snapshot, hist = ctx.hist, reps = ctx.reps }, ply = b.ply,
    }
    self.manaOf[side] = self.manaOf[side] - def.cost
    self.castThisTurn[side] = true
    if def.slug ~= "temporal_echo" then self.lastSpell[side] = def end
    -- A played card is consumed even if the spell later fizzles.
    self:discardCard(side, def)
    self:removeCard(cv)
    self.sel = nil
    self.view:setPick(nil)
    cv.x.target, cv.y.target = CENTER_X, CENTER_Y
    cv.lift.target, cv.rot.target, cv.scale.target, cv.face.target = 0, 0, CARD.castScale, 1
    cv.rot:kick(side == 1 and 10 or -10)
    cv.scale:kick(3)
    Audio.play("spell", def.role and 0.82 or 1)
    self:dirty()
    local g = self.game
    if g.net and not g.netApplying then g.net:cast(def.slug, a, c, self.match.clock[side]) end
end

function Layer:impact()
    local c = self.casting
    local fx, view, def = self.game.fx, self.view, c.def
    if def.role then
        fx:burst(CENTER_X, CENTER_Y, 56, 620, ROLE_COLS, 0.9, 6, 260)
        BG.pulse(CENTER_X, CENTER_Y, 1.2)
        view:ring(CENTER_X, CENTER_Y, 40, 320, 0.55, Pal.R)
        view:ring(CENTER_X, CENTER_Y, 20, 220, 0.42, Pal.RL)
        Screen.shake(6, 0.22)
        Audio.play("impact", 0.88, 0.72)
        return
    end
    fx:burst(CENTER_X, CENTER_Y, 44, 560, IMPACT_COLS, 0.9, 6, 260)
    BG.pulse(CENTER_X, CENTER_Y, 0.6 + def.cost * 0.3)
    view:ring(CENTER_X, CENTER_Y, 40, 300, 0.5, Pal.C)
    view:ring(CENTER_X, CENTER_Y, 20, 200, 0.4, Pal.B)
    Screen.shake(def.cost >= 3 and 10 or 6, 0.25)
    local snd = "impact"
    if def.slug == "freeze" then snd = "freeze"
    elseif def.slug == "meteor" or def.slug == "sacrifice" or def.slug == "blood_pact" then snd = "explode" end
    Audio.play(snd)
    for _, s in ipairs({ c.a, c.c }) do
        if s then
            local x, y = view:squareCenter(s)
            fx:burst(x, y, 24, 300, IMPACT_COLS, 0.7, 5, 160)
            view:ring(x, y, 10, 80, 0.4, Pal.C)
        end
    end
end

function Layer:resolve()
    local c = self.casting
    local side, def = c.side, c.def
    local m, g = self.match, self.game
    local b = m.board
    local who = m.players[side].name
    if self.ward[-side] > b.ply then
        self.ward[-side] = 0
        g:toast("COUNTERED", true)
        g:log(who .. ": " .. def.name .. " X", def)
        g:recordSpell(side, def, true)
        self:dirty()
        return
    end
    local ok, nb = S.check(b, side, def, c.a, c.c, c.ctx)
    if not ok then
        g:toast("FIZZLED")
        self:dirty()
        return
    end
    Defs.restore(b, nb)
    if def.after then def.after(self, side) end
    if not def.role then g:toast(def.name) end
    g:log(who .. ": " .. def.name, def)
    if def.slug == "time_rewind" and c.ctx.hist then
        m:rewind(c.ctx.hist, c.ctx.reps)
        m.lastMove = nil
        g:markRewound(c.ctx.hist)
    end
    g:recordSpell(side, def, false)
    if def.endsTurn then
        m.lastMove = nil
        m.history[#m.history + 1] = {
            side = side, no = floor((b.ply - 1) / 2) + 1, san = def.tag, spell = def.name,
        }
        m:recordPosition()
        g:positionChanged()
        g:turnStarted()
    else
        m.pendingSpell = def.name
        g:positionChanged()
    end
    self:dirty()
end

local function sample(list, n)
    U.shuffle(list)
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

function Layer:cpuDecide(side)
    local L = self.game.ai or Search.level(2)
    local b = self.match.board
    if random() > (L.cast or 1) then return nil end
    if self.ward[-side] > b.ply then return nil end
    local depth, qs, noise = L.spellDepth or 1, L.qs, L.spellNoise or 0
    local ctx = self:ctxFor(side)
    ctx = { snapshot = ctx.snapshot, hist = ctx.hist, reps = ctx.reps }
    local t0 = now()
    local base, _, stop = Search.score(b:clone(), depth, 0.6, true, qs)
    if stop then return nil end
    local best, bestGain, bestA, bestC = nil, -math.huge, nil, nil
    local evals = 0
    local spell = CARD.cpuSpell
    local hand = {}
    for i, cv in ipairs(self.hand[side]) do hand[i] = cv end

    local function try(cv, a, c)
        if evals >= spell.maxEvals or now() - t0 > spell.timeBudget then return end
        local def = cv.def
        local ok, nb = S.check(b, side, def, a, c, ctx)
        if not ok then return end
        evals = evals + 1
        local sc, _, st = Search.score(nb, depth, 0.5, true, qs)
        if st then return end
        local gain = (def.endsTurn and -sc or sc) - base + (def.aiBonus or 0)
        gain = gain + (random() * 2 - 1) * noise
        if gain > bestGain then best, bestGain, bestA, bestC = cv, gain, a, c end
        coroutine.yield()
    end

    for _, cv in ipairs(hand) do
        local def = cv.def
        if S.castable(b, side, def, self, ctx, true) then
            if def.steps == 0 then
                try(cv)
            else
                local firsts = sample(def.pick1(b, side, ctx), def.steps == 1 and 12 or 5)
                for _, a in ipairs(firsts) do
                    if def.steps == 1 then
                        try(cv, a)
                    else
                        local seconds = sample(def.pick2(b, side, a, ctx), 4)
                        for _, c in ipairs(seconds) do try(cv, a, c) end
                    end
                end
            end
        end
    end
    if best and bestGain > spell.thresholdBase + spell.thresholdCost * best.def.cost then return best, bestA, bestC end
    return nil
end

function Layer:cpuTurn(side)
    if self.casting then return true end
    if self.cpuDone == self.turnNo or self.castThisTurn[side] then return false end
    if not self.cpuCo then
        self.cpuCo = coroutine.create(function() return self:cpuDecide(side) end)
    end
    local frameEnd = now() + CPU_BUDGET
    local co = self.cpuCo
    local ok, cv, a, c
    repeat
        ok, cv, a, c = coroutine.resume(co)
        if not ok then print("CPU spell error: " .. tostring(cv)); cv = nil end
    until coroutine.status(co) == "dead" or now() >= frameEnd
    if coroutine.status(co) ~= "dead" then return true end
    self.cpuCo = nil
    self.cpuDone = self.turnNo
    if ok and cv and cv.def then
        self:beginCast(side, cv, a, c)
        return true
    end
    return false
end

function Layer:cardAt(mx, my)

    for _, side in ipairs({ 1, -1 }) do
        local hand = self.hand[side]
        for i = #hand, 1, -1 do
            local cv = hand[i]
            if cv.delay <= 0 then
                local k = cv.scale.x
                local cx, cy = cv.x.x, cv.y.x + cv.lift.x
                if abs(mx - cx) <= CARD_W / 2 * k and abs(my - cy) <= CARD_H / 2 * k then return cv end
            end
        end
    end
    return nil
end

function Layer:update(dt, mx, my)
    self.t = self.t + dt
    self:refreshState()

    local h = nil
    if not self.casting then
        h = self:cardAt(mx, my)
        if h and not self:faceUp(h.side) then h = nil end
    end
    if h ~= self.hover then
        if h then
            Audio.play("card_hover", 0.95 + random() * 0.1)
            h.scale:kick(1.5)
        end
        self.hover = h
    end
    local selCard = self.sel and self.sel.card
    self.wantHand = h ~= nil and h.ok and self:canInteract(h.side)

    for _, side in ipairs({ 1, -1 }) do
        local hand = self.hand[side]
        local up = self:faceUp(side)
        local sb = self:sidebar(side)
        for i = 1, #hand do
            local cv = hand[i]
            if cv.delay > 0 then
                cv.delay = cv.delay - dt
                if cv.delay <= 0 then
                    Audio.play("card_draw", 0.9 + random() * 0.2)
                    cv.y:kick(-500)
                    cv.rot:kick(sb.right and -6 or 6)
                end
            else
                local tx, ty = self:slotCenter(side, cv.slot)
                local lift, rot, scale = 0, sin(self.t * 1.3 + i * 1.7) * 0.015, 1
                if cv == selCard then
                    lift, scale, rot = -34, 1.1, sin(self.t * 4) * 0.03
                elseif cv == h then
                    lift, scale = -18, 1.06
                    rot = U.clamp((mx - cv.x.x) / 64, -1, 1) * 0.07
                elseif selCard and selCard.side == side then

                    local sx, sy = self:slotCenter(side, selCard.slot)
                    if abs(sy - ty) < 1 then tx = tx + (tx > sx and 14 or -14) end
                    if abs(sx - tx) < 1 or abs(sy - ty) > 1 then ty = ty + (ty > sy and 12 or -12) end
                end
                cv.x.target, cv.y.target = tx, ty
                cv.lift.target, cv.rot.target, cv.scale.target = lift, rot, scale
                cv.face.target = up and 1 or 0
                local g = (cv == h or cv == selCard) and 1 or 0
                cv.glow = U.approach(cv.glow, g, 10, dt)
            end
            cv.x:update(dt); cv.y:update(dt); cv.rot:update(dt)
            cv.scale:update(dt); cv.lift:update(dt); cv.face:update(dt)
        end
    end

    local c = self.casting
    if c then
        c.t = c.t + dt
        local cv = c.card
        cv.x:update(dt); cv.y:update(dt); cv.rot:update(dt)
        cv.scale:update(dt); cv.lift:update(dt); cv.face:update(dt)
        cv.glow = 1
        if not c.hit and c.t >= T_IMPACT then
            c.hit = true
            cv.scale:kick(-6)
            self:impact()
            self:resolve()
        end
        if c.t >= T_FADE then
            cv.alpha = max(0, 1 - (c.t - T_FADE) / (T_DONE - T_FADE))
            cv.scale.target = CARD.fadeScale
        end
        if c.t >= T_DONE then
            self.casting = nil
            self:dirty()
        end
    end

    if self.sel then
        if self.sel.step == 0 then self.castBtn:update(dt, mx, my) end
        self.cancelBtn:update(dt, mx, my)
        if self.castBtn.hover or self.cancelBtn.hover then self.wantHand = true end
    end
end

function Layer:mousepressed(x, y, b)
    if b == 2 then return self:cancel(true) end
    if b ~= 1 or self.casting then return false end
    if self.sel then
        if self.sel.step == 0 and self.castBtn:mousepressed(x, y, b) then return true end
        if self.cancelBtn:mousepressed(x, y, b) then return true end
    end
    local cv = self:cardAt(x, y)
    if cv and self:faceUp(cv.side) then
        if self:canInteract(cv.side) then
            self:clickCard(cv)
        else
            cv.rot:kick(5)
            Audio.play("card_hover", 0.8)
        end
        return true
    end
    return false
end

function Layer:mousereleased(x, y, b)
    if not self.sel then return false end
    local hit = self.castBtn:mousereleased(x, y, b)
    hit = self.cancelBtn:mousereleased(x, y, b) or hit
    return hit
end

function Layer:keypressed(key)
    local side = self:activeHuman()
    if not side then return false end
    local i = KEY_SLOT[key]
    if i then
        local cv = self.hand[side][i]
        if cv then self:clickCard(cv) end
        return true
    end
    if (key == "return" or key == "kpenter" or key == "space") and self.sel and self.sel.step == 0 then
        self:confirm()
        return true
    end
    return false
end

function Layer:wheelmoved() end

function Layer:drawCard(cv)
    local a = cv.alpha
    local k = cv.scale.x
    local fw = cv.face.x * 2 - 1
    local front = fw > 0
    local wk = max(0.04, abs(fw))
    lg.push()
    lg.translate(round(cv.x.x), round(cv.y.x + cv.lift.x))
    lg.rotate(cv.rot.x)
    lg.scale(k * wk, k)

    local drop = 10 - cv.lift.x * 0.3
    Pal.set(Pal.N, 0.55 * a)
    local hw, hh = CARD_W / 2, CARD_H / 2
    rect(-hw + drop * 0.6, -hh + drop, CARD_W, CARD_H)
    if cv.def.role and front and not self.casting then
        local pulse = 0.5 + 0.5 * sin(self.t * 3 + cv.side * 1.7)
        Pal.set(Pal.R, (0.04 + 0.035 * pulse) * a)
        rect(-hw - 5, -hh - 5, CARD_W + 10, CARD_H + 10)
    end
    if cv.glow > 0.02 then
        local p = 0.7 + 0.3 * sin(self.t * 7)
        local accent = cv.def.role and Pal.R or Pal.C
        local accent2 = cv.def.role and Pal.RL or Pal.B
        Pal.set(accent, cv.glow * p * a)
        rect(-hw - 8, -hh - 8, CARD_W + 16, CARD_H + 16)
        Pal.set(accent2, cv.glow * a)
        rect(-hw - 4, -hh - 4, CARD_W + 8, CARD_H + 8)
    end
    lg.setColor(1, 1, 1, a)
    if front then
        lg.draw(A.card[cv.def.slug], -hw, -hh, 0, 2, 2)
        if a >= 1 then
            local role = cv.def.role
            Frame.diamond(-hw + 22, -hh + 22, 18, role and Pal.RD or Pal.N)
            Frame.diamond(-hw + 22, -hh + 22, 14, role and Pal.R or Pal.B)
            Text.print(COST_STR[cv.def.cost], -hw + 23, -hh + 15, 2,
                role and Pal.RL or Pal.C, "center", role and Pal.RD or Pal.N)
        end

        if not cv.ok and not self.casting and self.match.board.side == cv.side then
            Pal.set(Pal.N, 0.5 * a)
            rect(-hw, -hh, CARD_W, CARD_H)
        end
    else
        lg.draw(backImg, -hw, -hh, 0, 2, 2)
    end
    lg.pop()
end

function Layer:drawHand(side)
    local hand = self.hand[side]
    local top = nil
    for i = 1, #hand do
        local cv = hand[i]
        local isTop = cv == self.hover or (self.sel and self.sel.card == cv)
        if isTop and not top then
            top = cv
        else
            self:drawCard(cv)
        end
    end
    if top then self:drawCard(top) end
end

local BADGE = CARD.badge
local function badge(x, y, letter, col)
    Pal.set(Pal.N)
    rect(x, y, BADGE, BADGE)
    Pal.set(col)
    rect(x + 2, y + 2, BADGE - 4, 2)
    Text.print(letter, x + BADGE / 2, y + 6, 2, col, "center")
end

function Layer:drawStatus()
    local b = self.match.board
    local view = self.view
    local sprites = view.sprites
    local cell = Config.ui.board.cell
    local ply = b.ply
    for s = 1, 64 do
        local id = b.id[s]
        if id ~= 0 then
            local sp = sprites[id]
            local e = b.st[id]
            local prot = b:isProtected(s)
            if sp and sp.state == "board" and (e or prot) then
                local x, y = round(sp.x), round(sp.y)
                local bx, by = x + 4, y + 4
                local function addBadge(letter, col)
                    badge(bx, by, letter, col)
                    bx = bx + BADGE + CARD.badgeGap
                    if bx + BADGE > x + cell - 2 then bx, by = x + 4, by + BADGE + CARD.badgeGap end
                end
                if e and e.pawned and e.pawned > ply then
                    Pal.set(Pal.R, 0.10 + 0.04 * sin(self.t * 4 + s))
                    rect(x + 4, y + 4, cell - 8, cell - 8)
                    addBadge("P", Pal.R)
                end
                if e and e.frozen and e.frozen > ply then
                    Pal.set(Pal.C, 0.28 + 0.06 * sin(self.t * 3 + s))
                    rect(x + 4, y + 4, cell - 8, cell - 8)
                    addBadge("F", Pal.C)
                end
                if prot then addBadge("S", Pal.C) end
                if e and e.berserk and e.berserk > ply then addBadge("B", Pal.B) end
            end
        end
    end
    for _, side in ipairs({ 1, -1 }) do
        local sb = self:sidebar(side)
        local tg = self.tags[side]
        local x = sb.right and (sb.x + SIDEBAR.tagRightX) or (sb.x + SIDEBAR.tagLeftX)
        if tg[1] ~= "" then Text.print(tg[1], x, SIDEBAR.tagY1, 2, Pal.C, "right") end
        if tg[2] ~= "" then Text.print(tg[2], x, SIDEBAR.tagY2, 2, Pal.B, "right") end
        if self.castThisTurn[side] and b.side == side and not self.match.result then
            Frame.diamond(sb.right and (sb.x + SIDEBAR.tagLeftX) or (sb.x + 16), SIDEBAR.turnDotY, 6, Pal.I)
        end
    end
end

function Layer:drawMarks(view)
    local b = self.match.board
    local S = Config.ui.board.cell
    for _, z in ipairs(b.zones) do
        if z.untilPly > b.ply then
            local pulse = 0.22 + 0.06 * sin(self.t * 3)
            for dr = -1, 1 do
                for df = -1, 1 do
                    local f, r = z.f + df, z.r + dr
                    if f >= 0 and f <= 7 and r >= 0 and r <= 7 then
                        local x, y = view:squareXY(Board.sq(f, r))
                        Pal.set(z.owner == 1 and Pal.C or Pal.B, pulse)
                        rect(x, y, S, S)
                        Pal.set(Pal.C, 0.5)
                        rect(x + 44, y + 2, 8, 2); rect(x + 44, y + S - 4, 8, 2)
                        rect(x + 2, y + 44, 2, 8); rect(x + S - 4, y + 44, 2, 8)
                    end
                end
            end
        end
    end
    local sel = self.sel
    if sel and sel.a then
        local x, y = view:squareXY(sel.a)
        Pal.set(Pal.C, 0.6)
        rect(x, y, S, S)
        Pal.set(Pal.N)
        rect(x + 6, y + 6, S - 12, 4); rect(x + 6, y + S - 10, S - 12, 4)
        rect(x + 6, y + 6, 4, S - 12); rect(x + S - 10, y + 6, 4, S - 12)
    end
end

function Layer:draw()
    self:drawStatus()
    self:drawHand(1)
    self:drawHand(-1)
end

function Layer:drawTooltip(cv)
    local def = cv.def
    local sb = self:sidebar(cv.side)
    local reason = (not cv.ok and self.match.board.side == cv.side) and cv.reason or nil
    local w, h = CardTip.size(def, reason)
    local edge = Config.ui.cardtip.edge
    local x = sb.right and (sb.x - edge - w) or (sb.x + Sidebar.W + edge)
    local y = U.clamp(round(cv.y.x + cv.lift.x - h / 2), edge, Screen.H - edge - h)
    CardTip.draw(def, x, y, reason)
end

function Layer:drawBanner()
    local sel = self.sel
    local def = sel.card.def
    local banner = Config.ui.cardtip.banner
    local x, y, w, h = banner.x, banner.y, banner.w, banner.h
    Pal.set(Pal.N, 0.85)
    rect(x + 8, y + 8, w, h)
    lg.setColor(1, 1, 1, 1)
    A.ui.dialogue:draw(x, y, w, h, 2)
    local accent = def.role and Pal.RL or Pal.C
    local sub = def.role and Pal.R or Pal.B
    Text.print(def.name, x + 28, y + 24, 3, accent, "left", def.role and Pal.RD or Pal.N)
    local prompt = sel.step == 0 and "CAST THIS SPELL?" or (sel.step == 1 and def.prompt1 or def.prompt2)
    Text.print(prompt or "", x + 28, y + 64, 2, sub, "left")
    if sel.step == 0 then self.castBtn:draw() end
    self.cancelBtn:draw()
end

function Layer:drawOverlay()
    if self.sel then self:drawBanner() end
    local c = self.casting
    if c then self:drawCard(c.card) end
    local h = self.hover
    if h and not c and h.delay <= 0 then self:drawTooltip(h) end
end

return Layer
