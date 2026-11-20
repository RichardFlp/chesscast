local M = require("src.states.manager")
local App = require("src.app")
local Config = require("src.config")
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

local CODE_LEN = Config.net.codeLength
local NAME_LEN = Config.net.nameLength
local VALID = Config.net.codeChars
local NAME_VALID = Config.net.nameChars
local PEER_NAME_WAIT = Config.net.peerNameWait
local MODES = Config.net.casualModes
local RATING_MIN, RATING_MAX = Config.net.ratingMin, Config.net.ratingMax
local ELO_LEN = Config.net.ratingDigits

local L = Config.ui.lobby
local NX, NY, NW, NH = L.x, L.y, L.w, L.h
local BOX_W, BOX_GAP, BOX_H = L.boxW, L.boxGap, L.boxH

local function findMode(id)
    for _, mode in ipairs(MODES) do
        if mode.id == id then return mode end
    end
    return MODES[1]
end

local function boxBounds(len, y, h)
    local width = len * BOX_W + (len - 1) * BOX_GAP
    return Screen.W / 2 - width / 2, y, width, h or BOX_H
end

function Lobby:enter(p)
    self.p = p
    self.mm = p.role == "match"
    self.ranked = self.mm and p.ranked == true
    self.mode = self.mm and findMode(p.mode) or nil
    self.role = self.mm and "queue" or p.role
    self.field = "name"
    self.elo = ""
    self.rating, self.opponentRating = nil, nil
    self.peerRating = nil
    self.retry, self.retryLeft, self.retryKind = nil, 0, nil
    self.hostTries, self.guestTries = 0, 0
    self.t = 0
    self.done = false
    self.err = nil
    self.code = ""
    self.copied = 0
    self.session = nil
    self.status = ""
    self.peerName, self.peerWait = nil, nil
    self.hostWait = nil
    self.copyBtn, self.joinBtn = nil, nil
    self.name = Sync.cleanName(App.settings.nickname)
    self:buildButtons()
    self:setPhase(self.role == "guest" and "code" or "name")
end

function Lobby:buildButtons()
    self.items = {}

    if self.role == "host" then
        self.copyBtn = Button.new {
            x = Screen.W / 2 - L.buttonW / 2, y = L.actionY,
            w = L.buttonW, h = L.buttonH, label = "COPY CODE", style = "primary",
            disabled = true, onClick = function()
                if WebNet then
                    WebNet.copy(self.code)
                else
                    love.system.setClipboardText(self.code)
                end
                self.copied = L.copyFlash
            end,
        }
        self.items[#self.items + 1] = self.copyBtn
    elseif self.role == "guest" then
        self.joinBtn = Button.new {
            x = Screen.W / 2 - L.buttonW / 2, y = L.actionY,
            w = L.buttonW, h = L.buttonH, label = "JOIN", style = "primary",
            disabled = true, onClick = function() self:setPhase("name") end,
        }
        self.items[#self.items + 1] = self.joinBtn
    end

    self.items[#self.items + 1] = Button.new {
        x = Screen.W / 2 - L.buttonW / 2, y = L.backY, w = L.buttonW, h = L.buttonH, label = "BACK", backSound = true,
        onClick = function() self:back() end,
    }
    self.focus = W.Focus.new(self.items)

    local y = NY + NH - L.nameButtonOffset
    local leftX = Screen.W / 2 - L.nameButtonW - L.nameGap / 2
    local rightX = Screen.W / 2 + L.nameGap / 2
    self.okBtn = Button.new {
        x = leftX, y = y, w = L.nameButtonW, h = L.nameButtonH, style = "primary",
        label = self.mm and "PLAY" or self.role == "host" and "CREATE" or "JOIN",
        onClick = function() self:confirmName() end,
    }
    self.nameItems = {
        self.okBtn,
        Button.new {
            x = rightX, y = y, w = L.nameButtonW, h = L.nameButtonH, label = "BACK", backSound = true,
            onClick = function() self:back() end,
        },
    }
    self.nameFocus = W.Focus.new(self.nameItems)
end

local function parseRating(text)
    local n = tonumber(text or "")
    if not n or n < RATING_MIN or n > RATING_MAX then return nil end
    return n
end

function Lobby:validElo()
    if #self.elo == 0 or #self.elo > ELO_LEN then return false end
    if not self.elo:match("^%d+$") then return false end
    local n = tonumber(self.elo)
    return n >= RATING_MIN and n <= RATING_MAX
end

function Lobby:updateOk()
    if not self.okBtn then return end
    self.okBtn.disabled = #self.name == 0 or (self.ranked and not self:validElo())
end

function Lobby:nameFieldAt(x, y)
    local fields = {
        { "name", NAME_LEN, NY + L.rankedNameOffset, L.rankedFieldH },
        { "elo", ELO_LEN, NY + L.rankedEloOffset, L.rankedFieldH },
    }
    for _, f in ipairs(fields) do
        local bx, by, bw, bh = boxBounds(f[2], f[3], f[4])
        if x >= bx and x < bx + bw and y >= by and y < by + bh then return f[1] end
    end
    return nil
end

function Lobby:setPhase(phase)
    self.phase = phase
    self.err = nil
    if phase == "name" then
        self.field = "name"
        self:updateOk()
    end
end

function Lobby:current()
    if self.phase == "name" then return self.nameItems, self.nameFocus end
    return self.items, self.focus
end

function Lobby:confirmName()
    if #self.name == 0 or (self.ranked and not self:validElo()) then return end
    if self.ranked then
        self.rating = tonumber(self.elo)
        self.elo = tostring(self.rating)
    end
    App.settings.nickname = self.name
    App.save()
    self.hostTries, self.guestTries = 0, 0
    self:setPhase("wait")
    self:connect()
end

function Lobby:connect()
    self.err = nil
    self.retry, self.retryKind = nil, nil

    if self.mm then
        self.role, self.code, self.peerName, self.retry = "queue", "", nil, nil
        local prefix = self.ranked and Config.net.rankedQueuePrefix or Config.net.queuePrefix
        self.session = Online.open("queue", prefix .. self.mode.id:upper(), "party", { rating = self.rating })
        self.status = "SEARCHING..."
        return
    end

    self.session = Online.open(self.role, self.role == "guest" and self.code or nil)
    self.status = "CONNECTING..."
    if self.joinBtn then self.joinBtn.disabled = true end
end

function Lobby:beginRetry(kind)
    Online.close()
    self.session = nil
    self.retry = Config.net.retryDelay
    self.retryKind = kind
    self.err = nil
    self.status = kind == "host" and "CHOOSING A NEW CODE..." or "LOOKING FOR ROOM..."
end

function Lobby:back()
    if self.mm then
        if M.switch("matchmaking", { casual = not self.ranked, ranked = self.ranked }) then
            Online.close()
            self.session = nil
        end
        return
    end

    if self.phase == "name" and self.role == "guest" then
        self:setPhase("code")
        self.joinBtn.disabled = #self.code < CODE_LEN
        return
    end

    local target = self.role == "host" and "setup" or "multiplayer"
    local params = self.role == "host" and { mode = "online" } or nil
    if M.switch(target, params) then
        Online.close()
        self.session = nil
    end
end

function Lobby:fail(message)
    if self.mm and self.role == "guest" and Online.roomMissing(message) and self.retryLeft > 0 then
        Online.close()
        self.session = nil
        self.retry = Config.net.retryDelay
        self.retryKind = nil
        return
    end

    self.retry, self.retryKind = nil, nil
    Online.close()
    self.session = nil
    self.peerWait, self.hostWait = nil, nil

    if self.mm then
        self.role = "queue"
    elseif self.role == "guest" then
        self:setPhase("code")
    else
        self.code = ""
        self:setPhase("name")
    end

    self.err = Online.normalize(message or "CONNECTION FAILED")
    self.status = ""
    Audio.play("ui_back")
    if self.joinBtn then self.joinBtn.disabled = #self.code < CODE_LEN end
end

function Lobby:startGame(params)
    if self.done or not M.switch("game", params) then return false end
    self.done = true
    return true
end

function Lobby:rivalRating()
    return self.peerRating or self.opponentRating
end

function Lobby:hostStart()
    if self.done or not self.session or self.session.state ~= "open" then return end
    local rival = self:rivalRating()

    local p = self.p
    self.peerWait = nil
    local seed = love.math.random(1, Config.net.maxSeed)
    local headerRating = rival ~= nil and self.rating or nil
    local header = Sync.header(seed, p.spells, p.clock, p.side, self.name, headerRating)
    local started = self:startGame {
        mode = "online",
        human = p.side,
        spells = p.spells,
        clock = p.clock,
        seed = seed,
        role = "host",
        log = { header },
        code = self.code,
        ranked = self.ranked,
        ratings = self.ranked and { [p.side] = self.rating, [-p.side] = rival } or nil,
        names = { [p.side] = self.name, [-p.side] = self.peerName },
    }
    if started then
        self.session:sendMove(header)
        Audio.play("ui_click")
    end
end

function Lobby:handleError(message)
    local code = message.code or message.message
    local text = message.message or "CONNECTION FAILED"

    if not self.mm and self.role == "host" and self.code == "" and Online.codeTaken(code)
        and self.hostTries < Config.net.codeRetries then
        self.hostTries = self.hostTries + 1
        self:beginRetry("host")
        return
    end

    if not self.mm and self.role == "guest" and Online.roomMissing(code)
        and self.guestTries < Config.net.joinGrace then
        self.guestTries = self.guestTries + 1
        self:beginRetry("guest")
        return
    end

    self:fail(text)
end

function Lobby:onMessage(message)
    if message.t == "closed" then
        self:fail(message.msg)
    elseif message.t == "error" then
        self:handleError(message)
    elseif message.t == "queued" then
        self.status = "SEARCHING..."
    elseif message.t == "matched" and self.role == "queue" then
        Online.close()
        self.role, self.code = message.role, message.code
        self.rating = message.rating or self.rating
        self.opponentRating = message.opponentRating
        self.peerRating = nil
        if message.role == "host" then
            self.p = {
                role = "match",
                mode = self.mode.id,
                side = love.math.random(2) == 1 and 1 or -1,
                spells = Config.net.queueSpells,
                clock = self.mode.clock,
            }
            self.hostWait = Config.net.hostWait
        else
            self.retryLeft = Config.net.joinRetry
        end
        self.session = Online.open(message.role, message.code, "party")
        self.status = "MATCH FOUND..."
    elseif message.t == "joined" then
        if self.role == "host" then
            self.hostTries = 0
            self.code = message.code
            if self.copyBtn then
                self.copyBtn.disabled = false
                self.status = "WAITING FOR OPPONENT"
            end
        else
            self.guestTries = 0
            local hello = "0|N " .. self.name
            if self.ranked and self.rating ~= nil then hello = hello .. " " .. self.rating end
            self.session:sendInput(hello)
            self.status = "WAITING FOR HOST"
            if message.state then self:onMessage({ t = "state", blob = message.state }) end
        end
    elseif message.t == "peer_joined" and self.role == "host" then
        self.peerName = nil
        self.peerRating = nil
        self.peerWait = PEER_NAME_WAIT
        self.hostWait = nil
        self.status = "OPPONENT JOINING..."
    elseif message.t == "peer_left" then
        if self.role == "host" then
            self.peerName = nil
            self.peerRating = nil
            self.peerWait = nil
            self.hostWait = nil
            self.err = nil
            self.status = "WAITING FOR OPPONENT"
        else
            self:fail("OPPONENT LEFT")
        end
    elseif message.t == "peer_input" and self.role == "host" then
        local name, rating
        if message.blob then name, rating = message.blob:match("^0|N (%w+) ?(%d*)$") end
        if name then
            name = Sync.cleanName(name)
            self.peerName = name ~= "" and name or nil
            if self.ranked then self.peerRating = parseRating(rating) end
            if self.peerWait then self:hostStart() end
        end
    elseif message.t == "state" and self.role == "guest" then
        local lines = Sync.split(message.blob)
        local header = Sync.parseHeader(lines[1])
        if header then
            Audio.play("ui_click")
            local human = -header.hostSide
            self:startGame {
                mode = "online",
                human = human,
                spells = header.spells,
                clock = header.clock,
                seed = header.seed,
                role = "guest",
                log = lines,
                code = self.code,
                ranked = self.ranked,
                ratings = self.ranked and {
                    [human] = self.rating,
                    [header.hostSide] = header.rating or self.opponentRating,
                } or nil,
                names = { [human] = self.name, [header.hostSide] = header.name },
            }
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
    for _, item in ipairs(items) do item:update(dt, mx, my) end

    while self.session and not self.done do
        local message = self.session:poll()
        if not message then break end
        self:onMessage(message)
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
            local kind = self.retryKind
            self.retry, self.retryKind = nil, nil
            if kind == "host" then
                self.session = Online.open("host")
            elseif kind == "guest" then
                self.session = Online.open("guest", self.code)
            else
                self.retryLeft = self.retryLeft - Config.net.retryDelay
                self.session = Online.open("guest", self.code, "party")
            end
        end
    end

    if self.peerWait and not self.done then
        self.peerWait = self.peerWait - dt
        if self.peerWait <= 0 then self:hostStart() end
    end
end

local function dots(t)
    return string.rep(".", math.floor(t * L.dotsRate) % 4)
end

function Lobby:statusLabel()
    if self.status == "" then return nil end
    local status = self.status
    if status:sub(-3) == "..." then status = status:sub(1, -4) end
    return status .. dots(self.t)
end

function Lobby:drawBoxes(str, len, y, cursor, h, scale)
    local cw, gap = BOX_W, BOX_GAP
    local x0, _, _, height = boxBounds(len, y, h)
    local textScale = scale or L.boxTextScale

    for i = 1, len do
        local x = x0 + (i - 1) * (cw + gap)
        love.graphics.setColor(1, 1, 1, 1)
        A.ui.panel_small:draw(x, y, cw, height, 2)

        local ch = str:sub(i, i)
        if ch ~= "" then
            Text.print(ch, x + cw / 2, y + (height - textScale * L.boxTextHeight) / 2, textScale, Pal.C, "center", Pal.N)
        elseif cursor and i == #str + 1 and math.floor(self.t * L.dotsRate) % 2 == 0 then
            love.graphics.setColor(Pal.C)
            love.graphics.rectangle("fill", x + L.boxCursorX, y + height - L.boxCursorY,
                cw - L.boxCursorX * 2, L.boxCursorH)
        end
    end
end

function Lobby:drawNameWindow()
    Pal.set(Pal.N, 0.7)
    love.graphics.rectangle("fill", 0, 0, Screen.W, Screen.H)
    Frame.panel(NX, NY, NW, NH, self.ranked and "RANKED ENTRY" or "YOUR NICKNAME")
    Text.print("UP TO " .. NAME_LEN .. " LETTERS OR NUMBERS", Screen.W / 2, NY + L.hintOffset, 2, Pal.B, "center")
    Text.print("YOUR OPPONENT SEES THIS NAME", Screen.W / 2, NY + L.helpOffset, 2, Pal.B, "center")
    if self.ranked then
        Text.print("YOUR Elo (UP TO " .. ELO_LEN .. " DIGITS)", Screen.W / 2, NY + L.eloLabelOffset, 2, Pal.B, "center")
        self:drawBoxes(self.name, NAME_LEN, NY + L.rankedNameOffset,
            self.field == "name", L.rankedFieldH, L.rankedScale)
        self:drawBoxes(self.elo, ELO_LEN, NY + L.rankedEloOffset, self.field == "elo", L.rankedFieldH, L.rankedScale)
    else
        self:drawBoxes(self.name, NAME_LEN, NY + L.nameOffset, true)
    end
    for _, item in ipairs(self.nameItems) do item:draw() end
end

function Lobby:draw()
    BG.draw(Config.ui.background.menuDim)
    local f = Config.ui.frame
    local title = self.role == "host" and "HOST ONLINE" or "JOIN ONLINE"
    if self.mm then title = self.mode.name .. (self.ranked and " RANKED" or " MATCHMAKING") end
    Frame.panel(f.x, f.y, f.w, f.h, title)

    if not self.mm and self.role == "host" then
        Text.print("SHARE THIS ROOM CODE WITH YOUR OPPONENT", Screen.W / 2, L.headerY, 2, Pal.B, "center")
        if self.code ~= "" then self:drawBoxes(self.code, CODE_LEN, L.boxesY, false) end
    elseif not self.mm and self.role == "guest" then
        Text.print("TYPE THE ROOM CODE YOUR OPPONENT SHARED", Screen.W / 2, L.headerY, 2, Pal.B, "center")
        Text.print("CTRL+V TO PASTE", Screen.W / 2, L.pasteY, 2, Pal.I, "center")
        self:drawBoxes(self.code, CODE_LEN, L.boxesY, self.phase == "code")
    end

    -- A matched guest can briefly drop its session while it retries a room
    -- that the host has not opened yet. Keep the status visible through that
    -- race so the screen never blanks between "MATCH FOUND" and "WAITING".
    local status = self:statusLabel()
    if self.err then
        Text.print(self.err, Screen.W / 2, L.statusY, 2, Pal.C, "center", Pal.N)
    elseif status then
        Text.print(status, Screen.W / 2, L.statusY, 3, Pal.C, "center", Pal.N)
    end

    if self.copied > 0 then Text.print("COPIED!", Screen.W / 2, L.copiedY, 2, Pal.B, "center") end
    for _, item in ipairs(self.items) do item:draw() end
    if self.phase == "name" then self:drawNameWindow() end
end

function Lobby:leave()
    if self.kb then love.keyboard.setTextInput(false) end
    self.kb = nil
end

function Lobby:textinput(text)
    text = text:upper()

    if self.phase == "name" then
        if self.ranked and self.field == "elo" then
            for c in text:gmatch("%d") do
                if #self.elo < ELO_LEN then self.elo = self.elo .. c end
            end
        else
            for c in text:gmatch(".") do
                if #self.name < NAME_LEN and NAME_VALID:find(c, 1, true) then
                    self.name = self.name .. c
                end
            end
        end
        self:updateOk()
    elseif self.phase == "code" and self.role == "guest" then
        for c in text:gmatch(".") do
            if #self.code < CODE_LEN and VALID:find(c, 1, true) then
                self.code = self.code .. c
            end
        end
        self.err = nil
        self.joinBtn.disabled = #self.code < CODE_LEN
    end
end

function Lobby:mousemoved()
    local _, focus = self:current()
    focus:clearIfMouse()
end

function Lobby:mousepressed(x, y, button)
    if self.kb and not love.keyboard.hasTextInput() then love.keyboard.setTextInput(true) end
    if self.phase == "name" and self.ranked then
        local field = self:nameFieldAt(x, y)
        if field then self.field = field; return end
    end
    local items = self:current()
    for _, item in ipairs(items) do
        if item:mousepressed(x, y, button) then return end
    end
end

function Lobby:mousereleased(x, y, button)
    local items = self:current()
    for _, item in ipairs(items) do item:mousereleased(x, y, button) end
end

function Lobby:keypressed(key)
    if key == "escape" then
        Audio.play("ui_back")
        self:back()
        return
    end

    local typing = self.phase == "name" or (self.phase == "code" and self.role == "guest")
    if typing then
        if self.phase == "name" and self.ranked and key == "tab" then
            self.field = self.field == "name" and "elo" or "name"
            return
        end
        local ctrl = love.keyboard.isDown("lctrl", "rctrl")
        if key == "v" and ctrl then
            if WebNet then return end
            self:textinput(love.system.getClipboardText() or "")
            return
        elseif key == "backspace" then
            if self.phase == "name" then
                if self.ranked and self.field == "elo" then
                    self.elo = self.elo:sub(1, -2)
                else
                    self.name = self.name:sub(1, -2)
                end
                self:updateOk()
            else
                self.code = self.code:sub(1, -2)
                self.err = nil
                self.joinBtn.disabled = true
            end
            return
        elseif key == "return" or key == "kpenter" then
            if self.phase == "name" and #self.name > 0 then
                if self.ranked and self.field == "name" then
                    self.field = "elo"
                    return
                end
                if not self.ranked or self:validElo() then
                    Audio.play("ui_click")
                    self:confirmName()
                end
            elseif self.phase == "code" and #self.code == CODE_LEN then
                Audio.play("ui_click")
                self:setPhase("name")
            end
            return
        end

        if #key == 1 then return end
    end

    local _, focus = self:current()
    focus:keypressed(key)
end

return Lobby
