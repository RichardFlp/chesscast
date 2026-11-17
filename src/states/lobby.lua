local M = require("src.states.manager")
local App = require("src.app")
local Button = require("src.ui.button")
local W = require("src.ui.widgets")
local BG = require("src.ui.background")
local Frame = require("src.ui.frame")
local Text = require("src.ui.text")
local Pal = require("src.utils.palette")
local Audio = require("src.audio.audio")
local A = require("src.assets.assets")
local Screen = require("src.utils.screen")
local Online = require("src.net.online")
local Sync = require("src.net.sync")
local WebNet = App.WEB and require("src.net.webnet")

local Lobby = {}

local CODE_LEN = 6
local NAME_LEN = 5
local VALID = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local NAME_VALID = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local PEER_NAME_WAIT = 3

local NX, NY, NW, NH = 560, 290, 800, 500

function Lobby:enter(p)
    self.p = p
    self.mm = p.role == "match"
    self.role = self.mm and "queue" or p.role
    self.retry, self.retryLeft = nil, 0
    self.t = 0
    self.done = false
    self.err = nil
    self.code = ""
    self.copied = 0
    self.session = nil
    self.status = ""
    self.peerName, self.peerWait = nil, nil
    self.name = Sync.cleanName(App.settings.nickname)
    self:buildButtons()
    self:setPhase(self.role == "guest" and "code" or "name")
end

function Lobby:buildButtons()
    self.items = {}
    if self.mm then
        self.searchBtn = Button.new { x = 960 - 200, y = 700, w = 400, h = 76, label = "SEARCH", style = "primary",
            disabled = true, onClick = function() self:connect() end }
        self.items[#self.items + 1] = self.searchBtn
    elseif self.role == "host" then
        self.copyBtn = Button.new { x = 960 - 200, y = 700, w = 400, h = 76, label = "COPY CODE", style = "primary",
            disabled = true, onClick = function()
                if WebNet then WebNet.copy(self.code) else love.system.setClipboardText(self.code) end
                self.copied = 2
            end }
        self.items[#self.items + 1] = self.copyBtn
    else
        self.joinBtn = Button.new { x = 960 - 200, y = 700, w = 400, h = 76, label = "JOIN", style = "primary",
            disabled = true, onClick = function() self:setPhase("name") end }
        self.items[#self.items + 1] = self.joinBtn
    end
    self.items[#self.items + 1] = Button.new { x = 960 - 200, y = 820, w = 400, h = 76, label = "BACK",
        backSound = true, onClick = function() self:back() end }
    self.focus = W.Focus.new(self.items)

    self.okBtn = Button.new { x = 960 - 320, y = NY + NH - 120, w = 300, h = 76, style = "primary",
        label = self.mm and "SEARCH" or self.role == "host" and "CREATE" or "JOIN", onClick = function() self:confirmName() end }
    self.nameItems = {
        self.okBtn,
        Button.new { x = 960 + 20, y = NY + NH - 120, w = 300, h = 76, label = "BACK", backSound = true,
            onClick = function() self:back() end },
    }
    self.nameFocus = W.Focus.new(self.nameItems)
end

function Lobby:setPhase(ph)
    self.phase = ph
    self.err = nil
    if ph == "name" then self.okBtn.disabled = #self.name == 0 end
end

function Lobby:current()
    if self.phase == "name" then return self.nameItems, self.nameFocus end
    return self.items, self.focus
end

function Lobby:confirmName()
    if #self.name == 0 then return end
    App.settings.nickname = self.name
    App.save()
    self:setPhase("wait")
    self:connect()
end

function Lobby:connect()
    self.err = nil
    if self.mm then
        self.role, self.code, self.peerName, self.retry = "queue", "", nil, nil
        self.session = Online.open("queue", "MATCHMAKING")
        self.status = "SEARCHING FOR AN OPPONENT..."
        self.searchBtn.disabled = true
        return
    end
    self.session = Online.open(self.role, self.role == "guest" and self.code or nil)
    self.status = "CONNECTING..."
    if self.joinBtn then self.joinBtn.disabled = true end
end

function Lobby:back()
    if self.mm then
        Online.close()
        self.session = nil
        M.switch("multiplayer")
        return
    end
    if self.phase == "name" and self.role == "guest" then
        self:setPhase("code")
        self.joinBtn.disabled = #self.code < CODE_LEN
        return
    end
    Online.close()
    self.session = nil
    M.switch(self.role == "host" and "setup" or "multiplayer", self.role == "host" and { mode = "online" } or nil)
end

function Lobby:fail(msg)
    if self.mm and self.role == "guest" and msg == "ROOM NOT FOUND" and self.retryLeft > 0 then
        self.retry = 0.5
        return
    end
    Online.close()
    self.session = nil
    self.peerWait = nil
    if self.mm then
        self.role = "queue"
        self.searchBtn.disabled = false
    elseif self.role == "guest" then self:setPhase("code") end
    self.err = string.upper(msg or "CONNECTION FAILED")
    self.status = ""
    Audio.play("ui_back")
    if self.joinBtn then self.joinBtn.disabled = #self.code < CODE_LEN end
end

function Lobby:startGame(params)
    self.done = true
    M.switch("game", params)
end

function Lobby:hostStart()
    local p = self.p
    self.peerWait = nil
    local seed = love.math.random(1, 2 ^ 31 - 1)
    local header = Sync.header(seed, p.spells, p.clock, p.side, self.name)
    self.session:sendMove(header)
    Audio.play("ui_click")
    self:startGame { mode = "online", human = p.side, spells = p.spells, clock = p.clock, seed = seed,
        role = "host", log = { header }, code = self.code,
        names = { [p.side] = self.name, [-p.side] = self.peerName } }
end

function Lobby:onMessage(m)
    if m.t == "closed" then
        self:fail(m.msg)
    elseif m.t == "error" then
        self:fail(m.message)
    elseif m.t == "queued" then
        self.status = "SEARCHING FOR AN OPPONENT..."
    elseif m.t == "matched" and self.role == "queue" then
        Online.close()
        self.role, self.code = m.role, m.code
        if m.role == "host" then
            self.p = { role = "match", side = love.math.random(2) == 1 and 1 or -1, spells = true, clock = 600 }
            self.hostWait = 15
        else
            self.retryLeft = 10
        end
        self.session = Online.open(m.role, m.code)
        self.status = "OPPONENT FOUND..."
    elseif m.t == "joined" then
        if self.role == "host" then
            self.code = m.code
            if self.copyBtn then
                self.copyBtn.disabled = false
                self.status = "WAITING FOR OPPONENT"
            end
        else
            self.session:sendInput("0|N " .. self.name)
            self.status = "WAITING FOR HOST"
            if m.state then self:onMessage({ t = "state", blob = m.state }) end
        end
    elseif m.t == "peer_joined" and self.role == "host" then
        self.status = "OPPONENT JOINING..."
        self.hostWait = nil
        self.peerWait = PEER_NAME_WAIT
        if self.peerName then self:hostStart() end
    elseif m.t == "peer_input" and self.role == "host" then
        local name = m.blob:match("^0|N (%w+)$")
        if name then
            name = Sync.cleanName(name)
            self.peerName = name ~= "" and name or nil
            if self.peerWait then self:hostStart() end
        end
    elseif m.t == "state" and self.role == "guest" then
        local lines = Sync.split(m.blob)
        local h = Sync.parseHeader(lines[1])
        if h then
            Audio.play("ui_click")
            local human = -h.hostSide
            self:startGame { mode = "online", human = human, spells = h.spells, clock = h.clock, seed = h.seed,
                role = "guest", log = lines, code = self.code,
                names = { [human] = self.name, [h.hostSide] = h.name } }
        end
    end
end

function Lobby:update(dt, mx, my)
    self.t = self.t + dt
    if self.copied > 0 then self.copied = self.copied - dt end
    if WebNet then
        local pasted = WebNet.takePaste()
        if pasted then self:textinput(pasted) end
    end
    if Screen.lite then
        local typing = self.phase == "name" or (self.phase == "code" and self.role == "guest")
        if typing ~= self.kb then
            self.kb = typing
            love.keyboard.setTextInput(typing)
        end
    end
    BG.update(dt)
    local items = self:current()
    for _, it in ipairs(items) do it:update(dt, mx, my) end

    while self.session and not self.done do
        local m = self.session:poll()
        if not m then break end
        self:onMessage(m)
    end
    if self.hostWait and not self.done then
        self.hostWait = self.hostWait - dt
        if self.hostWait <= 0 then
            self.hostWait = nil
            self:fail("OPPONENT DID NOT CONNECT")
        end
    end
    if self.retry and not self.done then
        self.retry = self.retry - dt
        if self.retry <= 0 then
            self.retry = nil
            self.retryLeft = self.retryLeft - 0.5
            self.session = Online.open("guest", self.code)
        end
    end
    if self.peerWait and not self.done then
        self.peerWait = self.peerWait - dt
        if self.peerWait <= 0 then self:hostStart() end
    end
end

local function dots(t) return string.rep(".", math.floor(t * 2) % 4) end

function Lobby:drawBoxes(str, len, y, cursor)
    local cw, gap = 104, 16
    local x0 = 960 - (len * cw + (len - 1) * gap) / 2
    for i = 1, len do
        local x = x0 + (i - 1) * (cw + gap)
        love.graphics.setColor(1, 1, 1, 1)
        A.ui.panel_small:draw(x, y, cw, 120, 2)
        local ch = str:sub(i, i)
        if ch ~= "" then
            Text.print(ch, x + cw / 2, y + 28, 8, Pal.C, "center", Pal.N)
        elseif cursor and i == #str + 1 and math.floor(self.t * 2) % 2 == 0 then
            love.graphics.setColor(Pal.C)
            love.graphics.rectangle("fill", x + 28, y + 92, cw - 56, 8)
        end
    end
end

function Lobby:drawNameWindow()
    Pal.set(Pal.N, 0.7)
    love.graphics.rectangle("fill", 0, 0, 1920, 1080)
    Frame.panel(NX, NY, NW, NH, "YOUR NICKNAME")
    Text.print("UP TO 5 LETTERS OR NUMBERS", 960, NY + 80, 2, Pal.B, "center")
    Text.print("YOUR OPPONENT SEES THIS NAME", 960, NY + 110, 2, Pal.B, "center")
    self:drawBoxes(self.name, NAME_LEN, NY + 160, true)
    for _, it in ipairs(self.nameItems) do it:draw() end
end

function Lobby:draw()
    BG.draw(0.35)
    Frame.panel(340, 150, 1240, 810, self.mm and "MATCHMAKING" or self.role == "host" and "HOST ONLINE" or "JOIN ONLINE")
    local connecting = self.session and self.status ~= ""
    if self.mm then
        Text.print("PLAY AGAINST A RANDOM OPPONENT", 960, 230, 2, Pal.B, "center")
        Text.print("10 MIN CLOCK, SPELLS ON, RANDOM SIDES", 960, 270, 2, Pal.B, "center")
    elseif self.role == "host" then
        Text.print("SHARE THIS ROOM CODE WITH YOUR OPPONENT", 960, 230, 2, Pal.B, "center")
        if self.code ~= "" then self:drawBoxes(self.code, CODE_LEN, 430, false) end
    else
        Text.print("TYPE THE ROOM CODE YOUR OPPONENT SHARED", 960, 230, 2, Pal.B, "center")
        Text.print("CTRL+V TO PASTE", 960, 270, 2, Pal.I, "center")
        self:drawBoxes(self.code, CODE_LEN, 430, self.phase == "code")
    end
    if self.phase == "wait" and self.name ~= "" then
        Text.print("PLAYING AS " .. self.name, 960, 340, 2, Pal.C, "center", Pal.N)
    end
    if self.err then
        Text.print(self.err, 960, 620, 2, Pal.C, "center", Pal.N)
    elseif connecting then
        local s = self.status
        if s:sub(-3) == "..." then s = s:sub(1, -4) end
        Text.print(s .. dots(self.t), 960, 620, 3, Pal.C, "center", Pal.N)
    end
    if self.copied > 0 then Text.print("COPIED!", 960, 660, 2, Pal.B, "center") end
    for _, it in ipairs(self.items) do it:draw() end
    if self.phase == "name" then self:drawNameWindow() end
end

function Lobby:leave()
    if self.kb then love.keyboard.setTextInput(false) end
    self.kb = nil
end

function Lobby:textinput(t)
    t = t:upper()
    if self.phase == "name" then
        for c in t:gmatch(".") do
            if #self.name < NAME_LEN and NAME_VALID:find(c, 1, true) then self.name = self.name .. c end
        end
        self.okBtn.disabled = #self.name == 0
    elseif self.phase == "code" and self.role == "guest" then
        for c in t:gmatch(".") do
            if #self.code < CODE_LEN and VALID:find(c, 1, true) then self.code = self.code .. c end
        end
        self.err = nil
        self.joinBtn.disabled = #self.code < CODE_LEN
    end
end

function Lobby:mousemoved()
    local _, focus = self:current()
    focus:clearIfMouse()
end
function Lobby:mousepressed(x, y, b)
    if self.kb and not love.keyboard.hasTextInput() then love.keyboard.setTextInput(true) end
    local items = self:current()
    for _, it in ipairs(items) do if it:mousepressed(x, y, b) then return end end
end
function Lobby:mousereleased(x, y, b)
    local items = self:current()
    for _, it in ipairs(items) do it:mousereleased(x, y, b) end
end
function Lobby:keypressed(key)
    if key == "escape" then Audio.play("ui_back"); self:back(); return end
    local typing = self.phase == "name" or (self.phase == "code" and self.role == "guest")
    if typing then
        local ctrl = love.keyboard.isDown("lctrl", "rctrl")
        if key == "v" and ctrl then
            if WebNet then return end
            self:textinput(love.system.getClipboardText() or "")
            return
        elseif key == "backspace" then
            if self.phase == "name" then
                self.name = self.name:sub(1, -2)
                self.okBtn.disabled = #self.name == 0
            else
                self.code = self.code:sub(1, -2)
                self.err = nil
                self.joinBtn.disabled = true
            end
            return
        elseif key == "return" or key == "kpenter" then
            if self.phase == "name" and #self.name > 0 then
                Audio.play("ui_click"); self:confirmName()
            elseif self.phase == "code" and #self.code == CODE_LEN then
                Audio.play("ui_click"); self:setPhase("name")
            end
            return
        end

        if #key == 1 then return end
    end
    local _, focus = self:current()
    focus:keypressed(key)
end

return Lobby
