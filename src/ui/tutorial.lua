local A = require("src.assets.assets")
local Pal = require("src.utils.palette")
local Text = require("src.ui.text")
local Frame = require("src.ui.frame")
local Button = require("src.ui.button")
local Spring = require("src.utils.spring")
local Audio = require("src.audio.audio")
local U = require("src.utils.util")
local Board = require("src.chess.board")
local Defs = require("src.cards.defs")

local T = {}
T.__index = T

local lg = love.graphics
local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local function rect(x, y, w, h) lg.rectangle("fill", x, y, w, h) end

local R = {
    board = { 548, 124, 824, 824 },
    clock = { 36, 124, 408, 80 },
    slots = { 88, 212, 304, 632 },
    mana = { 36, 852, 408, 48 },
    moves = { 36, 912, 408, 148 },
    cpu = { 1468, 4, 424, 1064 },
    pause = { 1376, 20, 96, 80 },
}

local BODY = 2
local LINE = 20
local PAD = 28

local function humanMoves(g)
    local n, side = 0, g.match.human
    for _, e in ipairs(g.match.history) do if e.side == side then n = n + 1 end end
    return n
end

local function myTurn(g)
    return g.match.board.side == g.match.human and not g.view:busy() and not (g.spells and g.spells:busy())
end

local STEPS = {
    {
        title = "WELCOME TO CHESSCAST",
        text = "CHESS, BUT EACH PLAYER ALSO HOLDS SPELL CARDS THAT BEND THE RULES.\n\n"
            .. "THIS GUIDE WALKS YOU THROUGH A REAL GAME AGAINST THE CPU. THE CLOCK STAYS "
            .. "STOPPED UNTIL THE GUIDE IS DONE.",
        box = "center", hold = true,
    },
    {
        title = "THE GOAL",
        text = "YOUR PIECES ARE THE ONES AT THE BOTTOM OF THE BOARD.\n\n"
            .. "WIN BY CHECKMATE: ATTACK THE ENEMY KING SO IT HAS NO WAY OUT. "
            .. "YOU CAN ALSO WIN IF THE CPU'S CLOCK RUNS OUT.",
        focus = "board", box = "right", hold = true,
    },
    {
        title = "HOW THE PIECES MOVE",
        rows = {
            { icon = Board.P, head = "PAWN", text = "ONE SQUARE FORWARD, OR TWO ON ITS FIRST MOVE. CAPTURES ONE SQUARE DIAGONALLY FORWARD." },
            { icon = Board.N, head = "KNIGHT", text = "JUMPS IN AN L: TWO SQUARES ONE WAY, THEN ONE TO THE SIDE. IT CAN JUMP OVER PIECES." },
            { icon = Board.B, head = "BISHOP", text = "ANY DISTANCE DIAGONALLY." },
            { icon = Board.R, head = "ROOK", text = "ANY DISTANCE UP, DOWN OR SIDEWAYS." },
            { icon = Board.Q, head = "QUEEN", text = "ANY DISTANCE IN ANY STRAIGHT OR DIAGONAL LINE." },
            { icon = Board.K, head = "KING", text = "ONE SQUARE IN ANY DIRECTION. IF IT IS TRAPPED, YOU LOSE." },
        },
        box = "wide", hold = true,
    },
    {
        title = "YOUR FIRST MOVE",
        text = function(self)
            local g = self.g
            local s = "CLICK ONE OF YOUR PIECES: DOTS SHOW WHERE IT CAN GO. CLICK A DOT TO MOVE, OR DRAG THE PIECE THERE.\n\n"
                .. "A GOOD START: PUSH THE PAWN IN FRONT OF YOUR KING OR QUEEN TWO SQUARES."
            if g.match.human == -1 then s = "THE CPU PLAYS WHITE, SO IT MOVES FIRST.\n\n" .. s end
            return s
        end,
        focus = "board", box = "right",
        enter = function(self) self.base = humanMoves(self.g) end,
        done = function(self) return humanMoves(self.g) > self.base end,
    },
    {
        title = "THE CPU'S TURN",
        text = "NOW THE CPU THINKS AND ANSWERS. THE SQUARES OF THE LAST MOVE STAY LIT SO YOU CAN SEE WHAT CHANGED.",
        box = "right", wait = true,
        done = function(self) return myTurn(self.g) end,
    },
    {
        title = "YOUR CLOCK",
        text = "EACH PLAYER HAS THEIR OWN CLOCK. YOURS ONLY RUNS ON YOUR TURN.\n\n"
            .. "IF IT REACHES ZERO YOU LOSE, SO DON'T THINK FOREVER. UNDER 10 SECONDS IT TICKS.",
        focus = "clock", box = "right", hold = true,
        need = function(g) return g.match.timed end,
    },
    {
        title = "SPELL CARDS",
        text = "THESE ARE YOUR SPELLS. YOU START WITH 3 CARDS AND DRAW ONE MORE AT THE START OF EACH OF YOUR TURNS, UP TO 6.\n\n"
            .. "HOVER A CARD TO READ WHAT IT DOES. TRY IT NOW!",
        focus = "slots", box = "right", hold = true, spells = true,
    },
    {
        title = "MANA",
        text = "SPELLS COST MANA. YOU GAIN 1 MANA AT THE START OF EACH TURN AND CAN STORE UP TO 3.\n\n"
            .. "THE NUMBER IN THE GEM ON A CARD IS ITS COST. CARDS YOU CAN'T AFFORD YET ARE GREYED OUT.",
        focus = "mana", box = "right", hold = true, spells = true,
    },
    {
        title = "CASTING",
        text = "YOU MAY CAST ONE SPELL PER TURN, BEFORE YOU MOVE.\n\n"
            .. "CLICK A CARD (OR PRESS 1-6). IF IT NEEDS A TARGET, THE SQUARES YOU CAN PICK LIGHT UP: CLICK ONE. "
            .. "OTHERWISE PRESS CAST. RIGHT-CLICK OR ESC CANCELS.\n\n"
            .. "CARDS MARKED ENDS TURN ARE YOUR WHOLE TURN: NO MOVE AFTER THEM.",
        focus = "slots", box = "right", hold = true, spells = true,
    },
    {
        title = "CAST A SPELL",
        text = function(self)
            local cv = self.castCard
            local name = cv and cv.def.name or "A CARD"
            return "YOUR TURN AGAIN. CAST " .. name .. " FROM YOUR HAND: CLICK IT, THEN FOLLOW THE PROMPT "
                .. "AT THE BOTTOM OF THE BOARD.\n\nANY OTHER LIT-UP CARD WORKS TOO."
        end,
        focus = function(self)
            local cv = self.castCard
            if cv and cv.slot then
                local x, y, w, h = self.g.spells:sidebar(self.g.match.human):slotRect(cv.slot)
                return { x - 8, y - 8, w + 16, h + 16 }
            end
            return R.slots
        end,
        box = "right", spells = true, skip = "SKIP STEP",
        enter = function(self)
            self.base = humanMoves(self.g)
            self:ensureCastable()
        end,
        done = function(self)
            local L, g = self.g.spells, self.g
            if humanMoves(g) > self.base then return true end
            return L.castThisTurn[g.match.human] and not L:busy() and not L.sel
        end,
    },
    {
        title = "NOW MOVE",
        text = "THE SPELL IS DONE. A SPELL COMES BEFORE YOUR MOVE, SO NOW MAKE YOUR MOVE AS USUAL.",
        focus = "board", box = "right", spells = true,
        enter = function(self) self.base = humanMoves(self.g) end,
        done = function(self)
            local g = self.g
            return humanMoves(g) > self.base or g.match.board.side ~= g.match.human
        end,
    },
    {
        title = "THE CPU'S SIDE",
        text = function(self)
            if not self.g.match.spells then
                return "THE RIGHT COLUMN IS THE CPU: ITS NAME, ITS CLOCK AND WHAT IT IS DOING RIGHT NOW."
            end
            return "THE RIGHT COLUMN IS THE CPU: ITS CLOCK, ITS HAND (FACE DOWN), ITS MANA AND A LOG OF THE SPELLS CAST.\n\n"
                .. "THE CPU CASTS SPELLS TOO. HOVER A LINE IN THE LOG TO READ THAT CARD."
        end,
        focus = "cpu", box = "left", hold = true,
    },
    {
        title = "MATCH HISTORY",
        text = "EVERY MOVE IS LISTED HERE. MOVES WITH A SPELL HAVE A SMALL GEM: HOVER THEM TO READ THE CARD.\n\n"
            .. "CLICK THIS BOX OR THE CPU'S LOG TO OPEN THE FULL HISTORY OF THE MATCH.",
        focus = "moves", box = "right", hold = true,
    },
    {
        title = "SPECIAL RULES",
        rows = {
            { head = "CHECK", text = "YOUR KING IS ATTACKED. YOUR NEXT MOVE MUST SAVE IT: MOVE IT, BLOCK, OR TAKE THE ATTACKER." },
            { head = "CHECKMATE", text = "A CHECK WITH NO WAY OUT. THE GAME ENDS." },
            { head = "CASTLING", text = "MOVE YOUR KING TWO SQUARES TOWARD A ROOK; THE ROOK JUMPS OVER. ONLY IF NEITHER HAS MOVED." },
            { head = "PROMOTION", text = "A PAWN THAT REACHES THE FAR ROW BECOMES A QUEEN, ROOK, BISHOP OR KNIGHT." },
            { head = "EN PASSANT", text = "A PAWN THAT JUMPS TWO SQUARES PAST YOURS CAN BE TAKEN AS IF IT MOVED ONE." },
            { head = "DRAWS", text = "NO LEGAL MOVE BUT NOT IN CHECK, THE SAME POSITION THREE TIMES, OR 50 MOVES WITHOUT A CAPTURE." },
        },
        box = "wide", hold = true,
    },
    {
        title = "CONTROLS",
        rows = {
            { head = "MOUSE", text = "CLICK OR DRAG PIECES. RIGHT-CLICK CANCELS A SELECTION." },
            { head = "1 - 6", text = "PICK A CARD FROM YOUR HAND.", spells = true },
            { head = "ESC", text = "CANCEL, THEN PAUSE. THE PAUSE MENU (II, TOP RIGHT) HAS RESTART, SETTINGS AND RESIGN." },
        },
        focus = "pause", box = "center", hold = true,
    },
    {
        title = "YOU'RE READY",
        text = "THE CLOCK STARTS NOW. PLAY THE GAME OUT: WIN, LOSE OR DRAW, FINISHING IT COMPLETES THE TUTORIAL.\n\n"
            .. "SHORT TIPS WILL POP UP THE FIRST TIME SOMETHING NEW HAPPENS. GOOD LUCK!",
        box = "center", hold = true, next = "PLAY",
    },
}
T.STEPS = STEPS

function T.new(game)
    local t = setmetatable({ g = game }, T)
    t.running = true
    t.i = 0
    t.time = 0
    t.mx, t.my = -1, -1
    t.pop = Spring.new(0, 300, 16)
    t.spot = 0
    t.tips, t.seen = {}, {}
    t.tip = nil
    t.nextBtn = Button.new { x = 0, y = 0, w = 200, h = 56, label = "NEXT", textScale = 2, style = "primary",
        hoverShift = 0, onClick = function() t:advance() end }
    t.skipBtn = Button.new { x = 0, y = 0, w = 200, h = 56, label = "SKIP TUTORIAL", textScale = 2,
        hoverShift = 0, backSound = true, onClick = function() t:skip() end }
    t:advance()
    return t
end

function T:wanted(s)
    local g = self.g
    if s.spells and not g.spells then return false end
    if s.need and not s.need(g) then return false end
    return true
end

function T:advance()
    local n = #STEPS
    repeat self.i = self.i + 1 until self.i > n or self:wanted(STEPS[self.i])
    if self.i > n then
        self:finish()
        return
    end
    local s = STEPS[self.i]
    self.step = s
    self.time = 0
    self.pop.x = 0.6
    self.pop.target = 1
    if s.enter then s.enter(self) end
    self:layout()
end

function T:finish()
    self.running = false
    self.step = nil
end

function T:skip()
    self:finish()
    self.tipsOff = true
end

function T:holding()
    return self.running and self.step and self.step.hold or false
end

function T:ensureCastable()
    local L, side = self.g.spells, self.g.match.human
    if not L then return end
    L:dirty()
    L:refreshState()
    self.castCard = nil
    for _, cv in ipairs(L.hand[side]) do
        if cv.ok then self.castCard = cv; break end
    end
    if self.castCard then return end
    if L.manaOf[side] < 1 then L.manaOf[side] = 1 end
    local hand = L.hand[side]
    if #hand == 0 then L:addCard(side, Defs.bySlug.shield) else hand[1].def = Defs.bySlug.shield end
    L:dirty()
    L:refreshState()
    self.castCard = hand[1]
end

local function stepText(self, s)
    local v = s.text
    if type(v) == "function" then v = v(self) end
    return v
end

local function rowList(self, s)
    local out = {}
    for _, r in ipairs(s.rows) do
        if not r.spells or self.g.spells then out[#out + 1] = r end
    end
    return out
end

function T:layout()
    local s = self.step
    if not s then return end

    local x, w, y
    if s.box == "right" then x, w = 1462, 440
    elseif s.box == "left" then x, w = 18, 440
    elseif s.box == "wide" then x, w = 420, 1080
    else x, w = 560, 800 end
    self.textW = w - PAD * 2
    local h = PAD + 30 + 20
    if s.rows then
        self.rowsShown = rowList(self, s)
        local tx = s.rows[1].icon and 300 or 230
        self.rowTextX = tx
        self.rowLines = {}
        for i, r in ipairs(self.rowsShown) do
            local lines = Text.lines(r.text, BODY, w - PAD - tx)
            self.rowLines[i] = lines
            h = h + max(r.icon and 64 or 0, #lines * LINE) + 18
        end
    else
        self.lines = Text.lines(stepText(self, s) or "", BODY, self.textW)
        h = h + #self.lines * LINE
    end
    h = h + 24 + 56
    h = h + PAD
    if s.box == "right" or s.box == "left" then
        y = 300
    else
        y = floor(540 - h / 2)
        if s.focus == "pause" then y = 180 end
    end
    self.px, self.py, self.pw, self.ph = x, y, w, h

    local by = y + h - PAD - 56
    local nb, sb = self.nextBtn, self.skipBtn
    nb.label = s.next or "NEXT"
    nb.w = max(120, Text.width(nb.label, 2) + 48)
    nb.x, nb.y = x + w - PAD - nb.w, by
    sb.label = s.skip or "SKIP TUTORIAL"
    sb.w = Text.width(sb.label, 2) + 40
    sb.x, sb.y = x + PAD, by
end

function T:showTip(key, title, text)
    if self.tipsOff or self.running or self.seen[key] then return end
    self.seen[key] = true
    local lines = Text.lines(text, BODY, 768 - PAD * 2)
    self.tips[#self.tips + 1] = { title = title, lines = lines, t = 0 }
end

function T:onSpell(side, def)
    if side ~= self.g.match.human then
        self:showTip("cpu_spell", "THE CPU CAST " .. def.name,
            "HOVER IT IN THE SPELL LOG ON THE RIGHT TO READ WHAT THE CARD DOES.")
    end
end

function T:watchTips()
    local g = self.g
    local m = g.match
    if m.result then return end
    local me = m.human
    local mine = m.board.side == me
    if mine and m.check then
        self:showTip("check", "YOU ARE IN CHECK", "YOUR KING IS ATTACKED. MOVE IT, BLOCK THE ATTACK OR CAPTURE THE ATTACKER.")
    end
    if g.view.promo then
        self:showTip("promo", "PROMOTION", "PICK WHAT YOUR PAWN BECOMES. THE QUEEN IS USUALLY THE BEST CHOICE.")
    end
    local L = g.spells
    if L and mine then
        if L.manaOf[me] >= 3 and not L.castThisTurn[me] then
            self:showTip("mana", "FULL MANA", "MANA STOPS AT 3, SO ANY MORE IS WASTED. A GOOD TIME TO CAST A SPELL!")
        end
        if #L.hand[me] >= 6 then
            self:showTip("hand", "YOUR HAND IS FULL", "WITH 6 CARDS YOU DRAW NO MORE UNTIL YOU CAST ONE.")
        end
    end
end

function T:update(dt, mx, my)
    self.mx, self.my = mx, my
    self.pop:update(dt)
    self.wantHand = false
    local s = self.step
    if self.running and s then
        self.time = self.time + dt
        if s.hold then self.nextBtn:update(dt, mx, my) end
        self.skipBtn:update(dt, mx, my)
        self.wantHand = (s.hold and self.nextBtn.hover) or self.skipBtn.hover

        if type(s.text) == "function" and floor(self.time * 4) ~= floor((self.time - dt) * 4) then self:layout() end
        if s.done and self.time > 0.3 and s.done(self) then
            Audio.play("ui_click", 1.3)
            self:advance()
        end
    end
    local target = (self.running and self.step and self.step.focus and self.step.hold) and 1 or 0
    self.spot = U.approach(self.spot, target, 6, dt)
    if self.g.match.result then
        self.running = false
        self.step = nil
        self.tips = {}
    end

    if not self.running then
        self:watchTips()
        local tip = self.tips[1]
        if tip then
            tip.t = tip.t + dt
            if tip.t > 9 then table.remove(self.tips, 1) end
        end
    end
end

function T:tipRect()
    local tip = self.tips[1]
    if not tip then return nil end
    local h = PAD * 2 + 30 + 14 + #tip.lines * LINE + 28
    return 576, 18, 768, h
end

function T:mousepressed(x, y, b)
    local s = self.running and self.step
    if s then
        if s.hold and self.nextBtn:mousepressed(x, y, b) then return true end
        if self.skipBtn:mousepressed(x, y, b) then return true end
        if s.hold then return true end
        return U.inRect(x, y, self.px, self.py, self.pw, self.ph)
    end

    local tx, ty, tw, th = self:tipRect()
    if tx and U.inRect(x, y, tx, ty, tw, th) then
        table.remove(self.tips, 1)
        Audio.play("ui_back")
        return true
    end
    return false
end

function T:mousereleased(x, y, b)
    local s = self.running and self.step
    if not s then return false end
    self.nextBtn:mousereleased(x, y, b)
    self.skipBtn:mousereleased(x, y, b)
    return s.hold
end

function T:keypressed(key)
    local s = self.running and self.step
    if not s or not s.hold then return false end
    if key == "return" or key == "kpenter" or key == "space" or key == "right" then
        self.nextBtn:activate()
        return true
    end
    return key ~= "escape"
end

local function focusRect(self, s)
    local f = s.focus
    if type(f) == "function" then return f(self) end
    return f and R[f] or nil
end

local function frame(x, y, w, h, t, a)
    Pal.set(Pal.C, a)
    rect(x, y, w, t); rect(x, y + h - t, w, t); rect(x, y, t, h); rect(x + w - t, y, t, h)
end

function T:drawSpotlight(s)
    local r = focusRect(self, s)
    local a = self.spot
    if r and a > 0.01 then
        local x, y, w, h = r[1], r[2], r[3], r[4]
        Pal.set(Pal.N, 0.62 * a)
        rect(0, 0, 1920, y)
        rect(0, y + h, 1920, 1080 - y - h)
        rect(0, y, x, h)
        rect(x + w, y, 1920 - x - w, h)
    elseif a > 0.01 then
        Pal.set(Pal.N, 0.62 * a)
        rect(0, 0, 1920, 1080)
    end
    if s.hold and not r then
        Pal.set(Pal.N, 0.62 * (1 - a))
        rect(0, 0, 1920, 1080)
    end
    if r then

        local p = 0.5 + 0.5 * sin(self.time * 5)
        local g = floor(p * 3) * 2
        frame(r[1] - 6 - g, r[2] - 6 - g, r[3] + 12 + g * 2, r[4] + 12 + g * 2, 4, 0.5 + 0.5 * p)
        Frame.diamond(r[1] - 6 - g, r[2] - 6 - g, 10, Pal.C)
        Frame.diamond(r[1] + r[3] + 6 + g, r[2] + r[4] + 6 + g, 10, Pal.C)
    end
end

function T:drawDots(x, y)
    local n, k = 0, 0
    for i, s in ipairs(STEPS) do
        if self:wanted(s) then
            n = n + 1
            if i == self.i then k = n end
        end
    end
    local gap = 18
    local x0 = x - (n - 1) * gap / 2
    for j = 1, n do
        Frame.diamond(x0 + (j - 1) * gap, y, j == k and 6 or 4, j <= k and Pal.C or Pal.I)
    end
end

function T:drawPanel(s)
    local x, y, w, h = self.px, self.py, self.pw, self.ph
    local k = self.pop.x
    lg.push()
    lg.translate(x + w / 2, y + h / 2)
    lg.scale(k, k)
    lg.translate(-(x + w / 2), -(y + h / 2))
    Pal.set(Pal.N, 0.85)
    rect(x + 10, y + 10, w, h)
    lg.setColor(1, 1, 1, 1)
    A.ui.panel_small:draw(x, y, w, h, 2)

    Frame.diamond(x + PAD + 8, y + PAD + 11, 10, Pal.N)
    Frame.diamond(x + PAD + 8, y + PAD + 11, 7, Pal.C)
    Text.print(s.title, x + PAD + 28, y + PAD, 3, Pal.C, "left", Pal.N)
    local ty = y + PAD + 30 + 20
    if s.rows then
        local tx = self.rowTextX
        for i, r in ipairs(self.rowsShown) do
            local lines = self.rowLines[i]
            local rh = max(r.icon and 64 or 0, #lines * LINE)
            if r.icon then
                lg.setColor(1, 1, 1, 1)
                lg.draw(A.piece[self.g.match.human][r.icon], x + PAD, ty, 0, 2, 2)
                Text.print(r.head, x + PAD + 84, ty + floor(rh / 2) - 7, 2, Pal.C, "left", Pal.N)
            else
                Frame.diamond(x + PAD + 6, ty + 7, 5, Pal.B)
                Text.print(r.head, x + PAD + 22, ty, 2, Pal.C, "left", Pal.N)
            end
            local ly = ty + (r.icon and floor((rh - #lines * LINE) / 2) or 0)
            for j, l in ipairs(lines) do
                Text.print(l, x + tx, ly + (j - 1) * LINE, 2, Pal.B, "left")
            end
            ty = ty + rh + 18
        end
    else
        for i, l in ipairs(self.lines) do
            Text.print(l, x + PAD, ty + (i - 1) * LINE, BODY, Pal.C, "left")
        end
    end
    if s.wait then

        local bx, by = x + w - PAD - 60, y + h - PAD - 28
        for j = 0, 2 do
            local on = floor(self.time * 4) % 3 == j
            Frame.diamond(bx + j * 24, by, 6, on and Pal.C or Pal.I)
        end
    elseif not s.hold then

        Text.print("YOUR MOVE", x + w - PAD, y + h - PAD - 36, 2, floor(self.time * 2) % 2 == 0 and Pal.C or Pal.B, "right")
    end
    lg.pop()

    self:drawDots(x + w / 2, y + h + 22)
    if s.hold then self.nextBtn:draw() end
    self.skipBtn:draw()
end

function T:drawTip()
    local tip = self.tips[1]
    if not tip then return end
    local x, y, w, h = self:tipRect()
    local a = min(1, tip.t * 5, (9 - tip.t) * 3)
    local slide = floor((1 - min(1, tip.t * 5)) * -30)
    y = y + slide
    Pal.set(Pal.N, 0.8 * a)
    rect(x + 8, y + 8, w, h)
    lg.setColor(1, 1, 1, a)
    A.ui.tooltip:draw(x, y, w, h, 2)
    Frame.diamond(x + PAD + 6, y + PAD + 10, 8, Pal.C)
    Text.print("TIP: " .. tip.title, x + PAD + 24, y + PAD, 3, Pal.C, "left", Pal.N, a)
    for i, l in ipairs(tip.lines) do
        Text.print(l, x + PAD, y + PAD + 44 + (i - 1) * LINE, BODY, Pal.C, "left", nil, a)
    end
    Text.print("CLICK TO CLOSE", x + w - PAD, y + h - PAD - 14, 2, Pal.B, "right", nil, a)
end

function T:draw()
    local s = self.running and self.step
    if s then
        self:drawSpotlight(s)

        local L = self.g.spells
        local h = L and L.hover
        if h and self.spot > 0.01 and not L.casting and h.delay <= 0 then L:drawTooltip(h) end
        self:drawPanel(s)
    else
        self:drawTip()
    end
end

return T
