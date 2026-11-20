local inbox, outbox, host, port = ...
local Config = require("src.config")
require("love.timer")
local socket = require("socket")
local SendAll = require("src.net.sendall")

local MAX_FRAME = Config.net.maxFrame
local PING_EVERY = Config.net.pingEvery
local PING = "\5"

local function le4(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local sock, err = socket.tcp()
if sock then
    sock:settimeout(Config.net.connectTimeout)
    local ok
    ok, err = sock:connect(host, port)
    if not ok then sock:close(); sock = nil end
end
if not sock then
    inbox:push({ ev = "closed", msg = "CANNOT REACH SERVER (" .. tostring(err) .. ")" })
    return
end
sock:setoption("tcp-nodelay", true)
sock:settimeout(Config.net.pollTimeout)
inbox:push({ ev = "open" })

local buf = ""
local lastSend = love.timer.getTime()

local function sendAll(data)
    return SendAll.run(function(payload, first)
        return sock:send(payload, first)
    end, data)
end

local function send(payload)
    local data = le4(#payload) .. payload
    sock:settimeout(Config.net.sendTimeout)
    local _, e = sendAll(data)
    sock:settimeout(Config.net.pollTimeout)
    lastSend = love.timer.getTime()
    return e
end

while true do

    local msg = outbox:pop()
    while msg ~= nil do
        if msg == false then
            sock:close()
            return
        end
        local e = send(msg)
        if e then
            inbox:push({ ev = "closed", msg = "CONNECTION LOST" })
            sock:close()
            return
        end
        msg = outbox:pop()
    end
    if love.timer.getTime() - lastSend > PING_EVERY then send(PING) end

    local data, e, partial = sock:receive(Config.net.receiveBytes)
    local chunk = data or partial
    if chunk and #chunk > 0 then buf = buf .. chunk end
    if e and e ~= "timeout" then
        local msg = e == "closed" and "SERVER CLOSED THE CONNECTION" or "CONNECTION LOST"
        inbox:push({ ev = "closed", msg = msg })
        sock:close()
        return
    end
    while #buf >= 4 do
        local b1, b2, b3, b4 = buf:byte(1, 4)
        local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        if n > MAX_FRAME then
            inbox:push({ ev = "closed", msg = "BAD FRAME FROM SERVER" })
            sock:close()
            return
        end
        if #buf < 4 + n then break end
        inbox:push(buf:sub(5, 4 + n))
        buf = buf:sub(5 + n)
    end
end
