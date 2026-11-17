local Roomie = require("src.net.roomie")

local Online = {
    APP_KEY = "pong",
    HOST = "server.roomielib.com",
    PORT = 8765,

    PARTY_URL = "wss://chessplus-relay.richardabrahamyan9.workers.dev/parties/main/",
    WS_URL = "ws://server.roomielib.com:8766/",
    current = nil,
}

local Session = {}
Session.__index = Session

local clientHash
local function hash()
    if not clientHash then
        local t = {}
        for i = 1, 16 do t[i] = string.format("%02x", love.math.random(0, 255)) end
        clientHash = table.concat(t)
    end
    return clientHash
end

function Online.setServer(s)
    if not s or s == "" then return end
    local h, p = s:match("^([^:]+):(%d+)$")
    Online.HOST = h or s
    Online.PORT = tonumber(p) or Online.PORT
end
Online.setServer(os.getenv("ROOMIE_SERVER"))

function Online.open(role, code)
    Online.close()
    local s = setmetatable({}, Session)
    s.role = role
    s.code = code or ""
    s.state = "connecting"
    s.codec = Roomie
    local web = love.system.getOS() == "Web"
    if Online.PARTY_URL ~= "" then
        s.codec = require("src.net.party")
        if s.code == "" then
            local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
            for _ = 1, 6 do
                local i = love.math.random(#chars)
                s.code = s.code .. chars:sub(i, i)
            end
        end
        if web then
            s.inbox, s.outbox, s.thread = require("src.net.webnet").open(Online.PARTY_URL .. s.code, true)
        else
            local host, path = Online.PARTY_URL:match("^wss?://([^/]+)(/.*)$")
            s.inbox = love.thread.newChannel()
            s.outbox = love.thread.newChannel()
            s.thread = love.thread.newThread("src/net/wsthread.lua")
            s.thread:start(s.inbox, s.outbox, host, 80, path .. s.code)
        end
    elseif web then
        s.inbox, s.outbox, s.thread = require("src.net.webnet").open(Online.WS_URL)
    else
        s.inbox = love.thread.newChannel()
        s.outbox = love.thread.newChannel()
        s.thread = love.thread.newThread("src/net/thread.lua")
        s.thread:start(s.inbox, s.outbox, Online.HOST, Online.PORT)
    end
    Online.current = s
    return s
end

function Online.close()
    local s = Online.current
    if s then s:close() end
    Online.current = nil
end

function Session:send(payload)
    if self.state == "closed" then return end
    self.outbox:push(payload)
end

function Session:sendMove(blob) self:send(self.codec.move(blob)) end
function Session:sendInput(blob) self:send(self.codec.input(blob)) end

function Session:close()
    if self.state ~= "closed" then
        self.outbox:push(self.codec.leave())
        self.outbox:push(false)
        self.state = "closed"
    end
    if Online.current == self then Online.current = nil end
end

function Session:poll()
    if self.state == "closed" and self.inbox:getCount() == 0 then return nil end
    local err = self.thread:getError()
    if err and self.state ~= "closed" then
        print("net thread error: " .. err)
        self.state = "closed"
        return { t = "closed", msg = "NETWORK ERROR" }
    end
    while true do
        local v = self.inbox:pop()
        if v == nil then return nil end
        if type(v) == "table" then
            if v.ev == "open" then
                self.state = "open"
                self.outbox:push(self.codec.hello(Online.APP_KEY, self.code, hash(), nil, self.role))
            elseif v.ev == "closed" then
                self.state = "closed"
                return { t = "closed", msg = v.msg }
            end
        else
            local m, e = self.codec.decode(v)
            if m then
                if m.t == "joined" then
                    self.code = m.code
                    self.peer = m.peer
                    self.hostPeer = m.host
                end
                if m.t ~= "pong" and m.t ~= "move_ok" then return m end
            else
                print("roomie decode error: " .. tostring(e))
            end
        end
    end
end

return Online
