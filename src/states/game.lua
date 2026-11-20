local Config = require("src.config")
local A = require("src.assets.assets")
local M = require("src.states.manager")
local App = require("src.app")
local Audio = require("src.audio.audio")
local Screen = require("src.utils.screen")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Spring = require("src.utils.spring")
local Particles = require("src.animations.particles")
local Match = require("src.chess.match")
local BV = require("src.ui.boardview")
local Sidebar = require("src.ui.sidebar")
local HistoryView = require("src.ui.historyview")
local CardTip = require("src.ui.cardtip")
local Tutorial = require("src.ui.tutorial")
local Search = require("src.ai.search")
local U = require("src.utils.util")
local Levels = require("src.campaign.levels")
local Online = require("src.net.online")
local Sync = require("src.net.sync")
local AFK = require("src.net.afk")

local lg = love.graphics
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local Game = {}

local GAME = Config.ui.game
local BOARD = Config.ui.board
local MIN_THINK, STEP_BUDGET, RESULT_DELAY = GAME.minThink, GAME.stepBudget, GAME.resultDelay

local DEPTH_STR = {}
for i = 0, Config.chess.maxPly do DEPTH_STR[i] = "DEPTH " .. i end

local function rect(x, y, w, h) lg.rectangle("fill", x, y, w, h) end

local cursors = {}
local function setCursor(kind)
    if not love.mouse or not love.mouse.getSystemCursor or not love.mouse.isCursorSupported() then return end
    if not cursors[kind] then
        local ok, c = pcall(love.mouse.getSystemCursor, kind)
        cursors[kind] = ok and c or false
    end
    if cursors[kind] then pcall(love.mouse.setCursor, cursors[kind]) end
end

function Game:enter(p)
    if p.resume and self.match then
        Audio.music("music_game")
        return
    end
    self.params = p
    local match = Match.new(p)
    self.match = match
    self.difficulty = p.difficulty or Config.settings.defaults.difficulty
    self.ai = Search.level(p.ai or self.difficulty)
    local cpuMode = match.mode == "cpu"
    self.online = match.mode == "online"
    local bottom = match.mode ~= "local" and match.human or 1
    self.bottom = bottom

    local topName = match.players[-bottom].name
    local botName = match.players[bottom].name
    local ratings = p.ratings
    self.view = BV.new(match, {
        bottom = bottom,
        topLabel = "TAKEN FROM " .. topName,
        bottomLabel = "TAKEN FROM " .. botName,
    })
    self.view.onMove = function(m) self:applyMove(m) end

    local level = self.ai
    self.left = Sidebar.new {
        x = Config.ui.sidebar.leftX, side = bottom, match = match, name = botName,
        sub = bottom == 1 and "WHITE PIECES" or "BLACK PIECES", showHistory = true,
        rating = ratings and ratings[bottom],
    }
    self.right = Sidebar.new {
        x = Config.ui.sidebar.rightX, side = -bottom, match = match, name = topName, right = true,
        sub = cpuMode and (level.name .. " CPU") or (bottom == 1 and "BLACK PIECES" or "WHITE PIECES"),
        rating = ratings and ratings[-bottom],
    }

    self.net = nil
    self.netApplying = false
    self.timeoutSent = false
    self.afkT = 0
    self.rematchMe, self.rematchThem, self.rematchText, self.rematchBtn = false, false, nil, nil
    if self.online then
        self.net = Sync.new(self, Online.current, p.role, p.log)
        self.roomCode = p.code
    end

    self.job = nil
    self.thinkT = 0
    self.started = false
    self.paused = false
    self.resultT = nil
    self.overlayShown = false
    self.overlayHidden = false
    self.toasts = {}
    self.fx = Particles.new(GAME.particles)
    self.t = 0
    self.lastTick = -1
    self.spellLog = {}

    self.timeline = {}
    self.timelineVer = 0
    self.historyOpen = false
    self.history = HistoryView.new(self)
    self.cursor = nil

    local pauseBtn = GAME.pauseButton
    self.pauseBtn = Button.new { x = pauseBtn.x, y = pauseBtn.y, w = pauseBtn.w, h = pauseBtn.h,
        label = "II", textScale = 3, hoverShift = 0, onClick = function() self:togglePause() end }
    self:buildPause()
    self.resultButtons = nil

    local okSpells, Spells = pcall(require, "src.cards.layer")
    if match.spells and okSpells then
        self.spells = Spells.new(self)
    else
        self.spells = nil
        if not okSpells and not tostring(Spells):find("not found") then print(Spells) end
    end

    self.tut = (p.tutorial and match.mode == "cpu") and Tutorial.new(self) or nil

    Audio.music("music_game")
end

function Game:leave()
    Screen.setCurse(false)
    setCursor("arrow")
    self.cursor = nil
end

function Game:buildPause()
    local layout = GAME.pauseMenu
    local x, w, h, gap = layout.x, layout.w, layout.h, layout.gap
    local labels, actions
    local resign = function()
        self.paused = false
        local side = self.match.mode ~= "local" and self.match.human or self.match.board.side
        self.match:resign(side)
        if self.net then self.net:localAction("R " .. side) end
    end
    if self.online then
        labels = { "RESUME", "RESIGN" }
        actions = {
            function() self:togglePause() end,
            resign,
        }
    else
        labels = { "RESUME", "RESTART", "SETTINGS", "RESIGN",
            self.params and self.params.campaign and "ROADMAP" or "MAIN MENU" }
        actions = {
            function() self:togglePause() end,
            function() M.switch("game", self.params) end,
            function()
                M.switch("settings", { back = "game", backParams = { resume = true },
                    overlay = function() self:drawScene() end })
            end,
            resign,
            function() M.switch(self.params and self.params.campaign and "campaign" or "menu") end,
        }
    end
    local y0 = layout.top + (layout.maxButtons - #labels) * gap / 2
    self.pauseItems = {}
    for i, l in ipairs(labels) do
        self.pauseItems[i] = Button.new { x = x, y = y0 + (i - 1) * gap, w = w, h = h, label = l,
            style = i == 1 and "primary" or "secondary", backSound = (i == 1 or i == #labels), onClick = actions[i] }
    end
    self.pauseFocus = W.Focus.new(self.pauseItems)
end

function Game:quitToMenu()
    local campaign = self.params and self.params.campaign
    if M.switch(self.online and "multiplayer" or (campaign and "campaign" or "menu")) then
        if self.net then
            Online.close()
            self.net.session = nil
        end
    end
end

function Game:buildResult()
    local layout = GAME.resultMenu
    local x, w, h = layout.x, layout.w, layout.h
    local y1, y2, y3 = layout.firstY, layout.firstY + layout.step, layout.firstY + layout.step * 2
    local list = {}
    self.rematchBtn = Button.new { x = x, y = y1, w = w, h = h, label = "REMATCH", style = "primary",
        disabled = self.online and (self.rematchMe or not (self.net and self.net.session)),
        onClick = function()
            if self.online then self:requestRematch() else M.switch("game", self.params) end
        end }
    list[1] = self.rematchBtn
    list[2] = Button.new { x = x, y = y2, w = w, h = h, label = "VIEW BOARD",
        onClick = function() self.overlayHidden = true end }
    list[3] = Button.new { x = x, y = y3, w = w, h = h, label = "MAIN MENU", backSound = true,
        onClick = function() self:quitToMenu() end }
    local campaign = self.params and self.params.campaign
    if campaign then
        local nextLevel = Levels.flat[campaign + 1]
        if self.resultGood and nextLevel then
            list[1] = Button.new { x = x, y = y1, w = w, h = h, label = "CONTINUE", style = "primary",
                onClick = function() M.switch("campaign", { won = campaign }) end }
        elseif not self.resultGood then
            list[1].label = "RETRY"
        else
            list[1] = Button.new { x = x, y = y1, w = w, h = h, label = "FINISH", style = "primary",
                onClick = function() M.switch("campaign", { won = campaign }) end }
        end
        list[3].label = "ROADMAP"
    end
    if self.match.result and self.match.result.reason == "AFK" then self.rematchBtn.disabled = true end
    self.resultButtons = list
    self.resultFocus = W.Focus.new(self.resultButtons)
end

function Game:togglePause()
    if self.match.result then
        if self.overlayShown then self.overlayHidden = not self.overlayHidden end
        return
    end
    self.paused = not self.paused
    Audio.play(self.paused and "ui_click" or "ui_back")
end

function Game:toast(text, big, role)
    local toast = GAME.toast
    local s = Spring.new(toast.spring[1], toast.spring[2], toast.spring[3])
    s.target = 1
    local list = self.toasts
    if #list >= toast.max then table.remove(list, 1) end
    list[#list + 1] = { text = text, t = 0, life = big and toast.bigLife or toast.life, s = s, big = big, role = role }
end

function Game:log(text, def)
    local l = self.spellLog
    l[#l + 1] = { text = text, def = def }
    if #l > GAME.spellLogMax then table.remove(l, 1) end
end

local function push(self, e)
    local t = self.timeline
    t[#t + 1] = e
    self.timelineVer = self.timelineVer + 1
end

function Game:recordMove(side, san, ply)
    push(self, { kind = "move", side = side, san = san, ply = ply, hist = #self.match.history })
end

function Game:recordSpell(side, def, countered)
    local c = self.spells and self.spells.casting
    local ply = self.match.board.ply
    if (countered or def.endsTurn) and c then ply = c.ply end
    push(self, { kind = "spell", side = side, def = def, countered = countered, ply = ply,
        hist = #self.match.history })
    if self.tut then self.tut:onSpell(side, def) end
end

function Game:recordNote(side, text)
    local ply = self.match.board.ply - 1
    for i = #self.timeline, 1, -1 do
        local e = self.timeline[i]
        if e.kind == "move" then ply = e.ply; break end
    end
    push(self, { kind = "note", side = side, text = text, ply = ply, hist = #self.match.history })
end

function Game:markRewound(h)
    for _, e in ipairs(self.timeline) do
        if (e.kind == "spell" and e.hist >= h) or (e.kind ~= "spell" and e.hist > h) then e.rewound = true end
    end
    self.timelineVer = self.timelineVer + 1
end

function Game:openHistory()
    if self.historyOpen then return end
    self.historyOpen = true
    self.view:deselect()
    if self.spells then self.spells:cancel(false) end
    self.history:open()
    Audio.play("ui_click")
end

function Game:closeHistory()
    if not self.historyOpen then return end
    self.historyOpen = false
    Audio.play("ui_back")
end

function Game:applyMove(m)
    local match = self.match
    if match.result or not match:isLegal(m) then return end
    local mover = match.board.side
    local info = match:playMove(m)
    self:recordMove(mover, info.san, match.board.ply - 1)
    if self.net and not self.netApplying then self.net:move(info, match.clock[mover]) end
    self.view:sync(info)
    if info.check and not match.result then
        Audio.play("check")
        self:toast("CHECK", true)
    end
    if info.promo and info.promo > 0 then self:toast("PROMOTION") end
    if self.spells then self.spells:onMovePlayed(info) end
    self:turnStarted()
end

function Game:turnStarted()
    self.job = nil
    self.thinkT = 0
    self.afkT = 0
    if self.spells and not self.match.result then self.spells:onTurnStart(self.match.board.side) end
end

function Game:positionChanged(info)
    self.match:positionChanged()
    self.view:sync(info)
    self.job = nil
    self.afkT = 0
    if self.match.check and not self.match.result then Audio.play("check"); self:toast("CHECK", true) end
end

function Game:onResult()
    local r = self.match.result
    -- CPU and online games report the result from the human player's seat.
    -- Hot-seat games report the winning colour instead.
    local relative = self.match.mode ~= "local"
    local good = r.winner ~= 0 and (not relative or r.winner == self.match.human)
    if r.winner == 0 then Audio.play("defeat", 1.2, 0.7)
    elseif good then Audio.play("victory") else Audio.play("defeat") end
    if r.winner ~= 0 then
        if relative then
            self.resultTitle = good and "VICTORY" or "DEFEAT"
        else
            self.resultTitle = r.winner == 1 and "WHITE WINS" or "BLACK WINS"
        end
    elseif r.reason == "AFK" then
        self.resultTitle = "MATCH ABORTED"
    elseif r.reason == "CONNECTION LOST" or r.reason == "OUT OF SYNC" then
        self.resultTitle = "DISCONNECTED"
    else
        self.resultTitle = "DRAW"
    end
    local reason = r.reason
    if r.reason == "TIMEOUT" then reason = r.winner == 0 and "TIME OUT, NO MATING MATERIAL" or "TIME RAN OUT"
    elseif r.reason == "RESIGNED" then
        if self.online then reason = r.winner == self.match.human and "YOUR OPPONENT RESIGNED" or "YOU RESIGNED"
        else reason = (r.winner == 1 and "BLACK" or "WHITE") .. " RESIGNED" end
    elseif r.reason == "REPETITION" then reason = "THREEFOLD REPETITION"
    elseif r.reason == "FIFTY MOVES" then reason = "FIFTY MOVE RULE"
    elseif r.reason == "AFK" then reason = "PLAYER AFK" end
    self.resultReason = reason
    self.resultGood = good
    local campaign = self.params and self.params.campaign
    if campaign and good and campaign > Levels.progress() then Levels.complete(campaign) end

    if self.params and self.params.tutorial then
        self.params.tutorial = false
        App.settings.tutorial = false
        App.save()
        self:toast("TUTORIAL COMPLETE")
    end
    self:buildResult()
end

function Game:netEnded(reason)
    if self.net then self.net.session = nil end
    Online.close()
    local match = self.match
    if match.result then
        self.rematchText = reason == "CONNECTION LOST" and "DISCONNECTED" or reason
        if self.rematchBtn then self.rematchBtn.disabled = true end
        return
    end
    if reason == "OPPONENT LEFT" then
        match.result = { winner = match.human, reason = reason }
        self.rematchText = "OPPONENT LEFT"
    elseif reason == "OPPONENT DISCONNECTED" then
        match.result = { winner = match.human, reason = reason }
    else
        match.result = { winner = 0, reason = reason }
    end
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

function Game:rematchAllowed()
    local result = self.match.result
    return result ~= nil and result.reason ~= "AFK"
end

function Game:requestRematch()
    local net = self.net
    if not self:rematchAllowed() or self.rematchMe or not (net and net.session) then return end
    self.rematchMe = true
    self.rematchBtn.disabled = true
    self.rematchText = "WAITING FOR OPPONENT"
    net.session:sendInput("RM")
    self:tryRematch()
end

function Game:rematchRequested()
    if not self:rematchAllowed() then return end
    self.rematchThem = true
    if not self.rematchMe then self.rematchText = "OPPONENT WANTS A REMATCH" end
    Audio.play("ui_click")
    self:tryRematch()
end

function Game:beginRematch(np, header)
    if self.match.result and self.match.result.reason == "AFK" then return false end
    if not M.switch("game", np) then return false end
    if header and self.net and self.net.session then self.net.session:sendMove(header) end
    self.net.session = nil
    self.net.over = true
    return true
end

function Game:tryRematch()
    if not self:rematchAllowed() then return end
    if not (self.rematchMe and self.rematchThem) or self.net.role ~= "host" then return end
    local p = self.params
    local names = p.names or {}
    local side = -p.human
    local np = copy(p)
    np.human, np.seed = side, love.math.random(1, Config.net.maxSeed)
    np.names = { [side] = names[p.human], [-side] = names[-p.human] }
    if p.ratings then
        np.ratings = { [side] = p.ratings[p.human], [-side] = p.ratings[-p.human] }
    end
    local header = Sync.header(np.seed, p.spells, p.clock, side, names[p.human])
    np.log = { header }
    self:beginRematch(np, header)
end

function Game:rematchStart(lines)
    local h = Sync.parseHeader(lines[1])
    local p = self.params
    local names = p.names or {}
    local np = copy(p)
    np.human = -h.hostSide
    np.seed, np.spells, np.clock, np.log = h.seed, h.spells, h.clock, lines
    np.names = { [np.human] = names[p.human], [h.hostSide] = h.name }
    if p.ratings then
        np.ratings = { [np.human] = p.ratings[-p.human], [h.hostSide] = p.ratings[p.human] }
    end
    self:beginRematch(np)
end

function Game:afkLimit()
    return AFK.limit(self.match, self.online, self.started, self.net and self.net.session)
end

function Game:afkRemaining()
    return AFK.remaining(self.afkT, self:afkLimit())
end

function Game:abortAfk()
    if self.match.result or not (self.net and self.net.session) then return end
    self.match.result = { winner = 0, reason = "AFK" }
    self.net:localAction("A " .. self.match.human)
end

function Game:updateAfk(dt)
    local limit = self:afkLimit()
    local expired
    self.afkT, expired = AFK.advance(self.afkT, limit, dt)
    if expired then self:abortAfk() end
end

function Game:updateCPU(dt)
    local match = self.match
    local side = match.board.side
    if match.result or not match:isCPU(side) or not self.started then
        self.job = nil
        return
    end
    if self.spells and self.spells:busy() then return end
    self.thinkT = self.thinkT + dt
    if not self.job then

        if self.spells and self.spells:cpuTurn(side) then return end
        self.job = Search.start(match.board, self.ai)
    end
    local done = self.job:step(STEP_BUDGET)
    if done and self.thinkT >= MIN_THINK * App.animScale() and not self.view:busy() then
        local m = self.job.move
        self.job = nil
        if m then self:applyMove(m) end
    end
end

function Game:update(dt, mx, my)
    self.t = self.t + dt
    self.mx, self.my = mx, my
    if self.spells then Screen.setCurse(self.spells:curseActive()) else Screen.setCurse(false) end
    BG.update(dt)
    local match = self.match
    local view = self.view

    if not self.started and not view:busy() then self.started = true end

    local frozen = (self.paused or self.historyOpen) and not self.online
    local tut = self.tut
    local holding = tut and tut:holding()
    if not frozen then

        if self.started and not match.result and not (tut and tut.running) then
            local timedOut = match:tick(dt)
            local side = match.board.side

            if self.net and timedOut and not self.timeoutSent then
                self.timeoutSent = true
                self.net:localAction("T " .. side)
            end

            if match.timed and not match.result and match:isLocal(side) then
                local c = match.clock[side]
                if c < GAME.lowClock then
                    local sec = floor(c)
                    if sec ~= self.lastTick then self.lastTick = sec; Audio.play("tick", 1.4, 0.5) end
                end
            end
        end
        if not holding then self:updateCPU(dt) end
        if self.net then self.net:update() end
        if self.started and not match.result then self:updateAfk(dt) end
        local side = match.board.side
        view.interactive = self.started and not match.result and match:isLocal(side) and not view:busy()
            and not self.paused and not self.historyOpen and not holding
            and not (self.spells and self.spells:blocksBoard())
        view:update(dt, mx, my)
        if self.spells then self.spells:update(dt, mx, my) end
    else
        view.interactive = false
    end

    local covered = self.historyOpen or self.paused or (self.resultT and self.overlayShown and not self.overlayHidden)
    local hx, hy = mx, my
    if covered or (self.spells and self.spells:busy()) then hx, hy = -1, -1 end
    self.left:update(dt, hx, hy)
    self.right:update(dt, hx, hy, self.spellLog)
    if self.historyOpen then self.history:update(dt, mx, my) end
    self.fx:update(dt)

    if match.result and not self.resultT then
        self.resultT = 0
        self.paused = false
        view:deselect()
        self:onResult()
    end
    if self.resultT then
        self.resultT = self.resultT + dt
        if not self.overlayShown and self.resultT >= RESULT_DELAY and not view:busy() then
            self.overlayShown = true
            if self.resultGood then self:confetti() end
        end
        if self.overlayShown and not self.overlayHidden then
            for _, b in ipairs(self.resultButtons) do b:update(dt, mx, my) end
        end
        local confetti = GAME.confetti
        if self.resultGood and self.overlayShown and self.resultT < confetti.seconds
            and floor(self.resultT * 4) ~= floor((self.resultT - dt) * 4) then
            self:confetti(confetti.burst)
        end
    end

    if tut then
        local over = self.paused or self.historyOpen or (self.resultT and self.overlayShown)
        tut:update(dt, over and -1 or mx, over and -1 or my)
    end

    self.pauseBtn:update(dt, mx, my)
    if self.paused then
        for _, b in ipairs(self.pauseItems) do b:update(dt, mx, my) end
    end

    local list = self.toasts
    for i = #list, 1, -1 do
        local tt = list[i]
        tt.t = tt.t + dt
        tt.s:update(dt)
        if tt.t >= tt.life then table.remove(list, i) end
    end

    local want = "arrow"
    if (view.wantHand and view.interactive) or (self.spells and self.spells.wantHand) then want = "hand" end
    if self.pauseBtn.hover then want = "hand" end
    if self.left.boxHover or self.right.boxHover then want = "hand" end
    if tut and tut.wantHand then want = "hand" end
    if self.historyOpen then want = self.history.wantHand and "hand" or "arrow" end
    if want ~= self.cursor then self.cursor = want; setCursor(want) end
end

function Game:confetti(n)
    local cols = { Pal.C, Pal.B, Pal.I }
    for _ = 1, n or GAME.confetti.count do
        local x = BOARD.x + love.math.random() * BOARD.cell * 8
        self.fx:add(x, -10 - love.math.random() * 60, (love.math.random() - 0.5) * 120, 80 + love.math.random() * 160,
            2.5 + love.math.random(), 4 + 2 * love.math.random(0, 2), cols[love.math.random(3)], 120, 0.6)
    end
end

function Game:plateStatus(side)
    local match = self.match
    if match.result then return nil end
    if match:isCPU(side) then return "THINKING" end
    if match:isRemote(side) then return "THEIR TURN" end
    if match.mode ~= "local" then return "YOUR TURN" end
    return "TO MOVE"
end

function Game:drawScene()
    local match = self.match
    BG.draw(GAME.sceneDim)
    self.left:drawBackdrop()
    self.right:drawBackdrop()
    self.view:drawTrays()
    self.view:draw()

    local left, right = self.left, self.right
    left:drawPlate(self:plateStatus(left.side))
    left:drawClock()
    left:drawSlots(match.spells)
    if match.spells then
        left:drawMana(self.spells and self.spells:mana(left.side) or 0, Config.ui.card.maxMana)
    end
    right:drawPlate(self:plateStatus(right.side))
    right:drawClock()
    right:drawSlots(match.spells)
    if match.spells then
        right:drawMana(self.spells and self.spells:mana(right.side) or 0, Config.ui.card.maxMana)
    end
    self.left:drawHistory()
    self:drawRightStatus()

    if self.spells then self.spells:draw() end
    self.view:drawOverlay()
    if self.spells then self.spells:drawOverlay() end
    self.fx:draw()
    self:drawToasts()
    local tip = self.left.tipDef or self.right.tipDef
    if tip then CardTip.drawAtMouse(tip, self.mx, GAME.cardTipY) end
end

function Game:drawRightStatus()
    local match = self.match
    local sb = self.right
    local log = #self.spellLog > 0 and self.spellLog or nil
    if match.mode == "cpu" then
        local thinking = match:isCPU(match.board.side) and not match.result and self.started
        local line1 = thinking and "THINKING" or (match.result and "GAME OVER" or "WAITING")
        local line2
        if thinking and self.job and self.job.depth and self.job.depth > 0 then
            line2 = DEPTH_STR[self.job.depth]
        elseif not log then
            line2 = "NO SPELLS CAST YET"
        end
        sb:drawStatus("CPU", line1, line2, thinking, log)
    else
        sb:drawStatus("SPELL LOG", log and "RECENT SPELLS" or "NO SPELLS CAST YET", nil, false, log)
    end
end

function Game:drawToasts()
    local list = self.toasts
    for i = 1, #list do
        local tt = list[i]
        local k = tt.big and 6 or 4
        local scale = max(0.05, tt.s.x)
        local fade = tt.t > tt.life - 0.25 and (tt.life - tt.t) / 0.25 or 1
        local toast = GAME.toast
        local w = Text.width(tt.text, k) + toast.widthPad
        local h = k * 8 + toast.heightPad
        local cy = Config.ui.card.centerY - (#list - i) * (h + toast.gap)
        lg.push()
        lg.translate(Screen.W / 2, cy)
        lg.scale(scale, scale)
        if tt.role then
            Pal.set(Pal.RD, 0.94 * fade)
            rect(-w / 2 + 8, -h / 2 + 8, w, h)
            Pal.set(Pal.RD, 0.98 * fade)
            rect(-w / 2, -h / 2, w, h)
            Pal.set(Pal.R, fade)
            rect(-w / 2 + 4, -h / 2 + 4, w - 8, 4)
            rect(-w / 2 + 4, h / 2 - 8, w - 8, 4)
            rect(-w / 2 + 4, -h / 2 + 8, 4, h - 16)
            rect(w / 2 - 8, -h / 2 + 8, 4, h - 16)
            Text.print(tt.text, 0, -k * 4 + 2, k, Pal.RL, "center", Pal.RD, fade)
        else
            Pal.set(Pal.N, 0.8 * fade)
            rect(-w / 2 + 8, -h / 2 + 8, w, h)
            lg.setColor(1, 1, 1, fade)
            A.ui.dialogue:draw(floor(-w / 2), floor(-h / 2), w, h, 2)
            Text.print(tt.text, 0, -k * 4 + 2, k, Pal.C, "center", Pal.N, fade)
        end
        lg.pop()
    end
end

function Game:drawPause()
    Pal.set(Pal.N, 0.7)
    rect(0, 0, Screen.W, Screen.H)
    local p = GAME.pause
    Frame.panel(p.x, p.y, p.w, p.h, "PAUSED")
    for _, b in ipairs(self.pauseItems) do b:draw() end
    Text.print("ESC TO RESUME", Screen.W / 2, p.hintY, 2, Pal.B, "center")
end

function Game:drawResult()
    local overlay = GAME.resultOverlay
    local a = min(1, (self.resultT - RESULT_DELAY) * overlay.fade)
    Pal.set(Pal.N, 0.65 * a)
    rect(0, 0, Screen.W, Screen.H)
    local slide = (1 - a) * overlay.slide
    lg.push()
    lg.translate(0, slide)
    local r = GAME.result
    Frame.panel(r.x, r.y, r.w, r.h)
    local col = self.resultTitle == "DEFEAT" and Pal.B or Pal.C
    Text.print(self.resultTitle, Screen.W / 2, r.titleY, 8, col, "center", Pal.N)
    Frame.divider(r.dividerX, r.dividerY, r.dividerW)
    Text.print(self.resultReason, Screen.W / 2, r.reasonY, 3, Pal.B, "center")
    if self.rematchText then Text.print(self.rematchText, Screen.W / 2, r.rematchY, 2, Pal.C, "center", Pal.N) end
    lg.pop()
    for _, b in ipairs(self.resultButtons) do b:draw() end
end

function Game:drawNetWarning()
    local net = self.net
    if not (net and net.session) or self.match.result then return end
    local afk = self:afkRemaining()
    if afk then
        local text = "OPPONENT AFK  " .. afk
        local w = Text.width(text, 3) + 60
        Pal.set(Pal.N, 0.85)
        local warn = GAME.warning
        rect(Screen.W / 2 - w / 2, warn.y, w, warn.h)
        Text.print(text, Screen.W / 2, warn.textY, 3, Pal.C, "center", Pal.N)
        return
    end
    local quiet = net:silence()
    if quiet < Sync.WARN_AFTER then return end
    local left = max(0, ceil(Sync.DROP_AFTER - quiet))
    local text = "OPPONENT NOT RESPONDING  " .. left
    local w = Text.width(text, 3) + 60
    Pal.set(Pal.N, 0.85)
    local warn = GAME.warning
    rect(Screen.W / 2 - w / 2, warn.y, w, warn.h)
    Text.print(text, Screen.W / 2, warn.textY, 3, Pal.C, "center", Pal.N)
end

function Game:draw()
    self:drawScene()
    self:drawNetWarning()
    self.pauseBtn:draw()
    if self.tut then self.tut:draw() end
    if self.resultT and self.overlayShown and not self.overlayHidden then
        self:drawResult()
    elseif self.paused then
        self:drawPause()
    end
    if self.historyOpen then self.history:draw() end
end

function Game:overlayButtons()
    if self.resultT and self.overlayShown and not self.overlayHidden then return self.resultButtons end
    if self.paused then return self.pauseItems end
    return nil
end

function Game:mousemoved()
    if self.pauseFocus then self.pauseFocus:clearIfMouse() end
    if self.resultFocus then self.resultFocus:clearIfMouse() end
end

function Game:mousepressed(x, y, b)
    if self.historyOpen then
        if self.history:mousepressed(x, y, b) then return end

        local h = Config.ui.history
        if not U.inRect(x, y, h.x, h.y, h.w, h.h) then self:closeHistory() end
        return
    end
    if self.pauseBtn:mousepressed(x, y, b) then return end
    local list = self:overlayButtons()
    if list then
        for _, bt in ipairs(list) do if bt:mousepressed(x, y, b) then return end end
        return
    end
    if self.tut and self.tut:mousepressed(x, y, b) then return end

    if b == 1 and (self.left:boxHit(x, y) or self.right:boxHit(x, y)) and not (self.spells and self.spells:busy()) then
        self:openHistory()
        return
    end
    if self.spells and self.spells:mousepressed(x, y, b) then return end
    self.view:mousepressed(x, y, b)
end

function Game:mousereleased(x, y, b)
    if self.historyOpen then self.history:mousereleased(x, y, b); return end
    self.pauseBtn:mousereleased(x, y, b)
    local list = self:overlayButtons()
    if list then
        for _, bt in ipairs(list) do bt:mousereleased(x, y, b) end
        return
    end
    if self.tut and self.tut:mousereleased(x, y, b) then return end
    if self.spells and self.spells:mousereleased(x, y, b) then return end
    self.view:mousereleased(x, y, b)
end

function Game:wheelmoved(dx, dy)
    local mx, my = Screen.mouse()
    if self.historyOpen then self.history:wheel(dy); return end
    if self.left:wheel(dy, mx, my) then return end
    if self.spells and self.spells.wheelmoved then self.spells:wheelmoved(dx, dy, mx, my) end
end

function Game:keypressed(key)
    if self.historyOpen then
        if key == "escape" or key == "h" then self:closeHistory() else self.history:keypressed(key) end
        return
    end
    if self.resultT and self.overlayShown then
        if key == "escape" then self.overlayHidden = not self.overlayHidden; Audio.play("ui_click"); return end
        if not self.overlayHidden then self.resultFocus:keypressed(key) end
        return
    end
    if self.paused then
        if key == "escape" then self:togglePause(); return end
        self.pauseFocus:keypressed(key)
        return
    end
    if self.tut and self.tut:keypressed(key) then return end
    if key == "escape" then

        if self.spells and self.spells:cancel() then return end
        if self.view.promo or self.view.sel or self.view.onPick then self.view:keypressed(key); return end
        self:togglePause()
        return
    end
    if self.spells and self.spells:keypressed(key) then return end
    self.view:keypressed(key)
end

function Game:windowFocus(f)
    if not f and not self.match.result and not self.paused and not self.online then
        self.paused = true
    end
end

return Game
