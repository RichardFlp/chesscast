local inbox, outbox, host, port, path = ...
local Config = require("src.config")
require("love.timer")
local socket = require("socket")
local bit = require("bit")
local SendAll = require("src.net.sendall")

local MAX_FRAME = Config.net.maxFrame
local BEAT = Config.net.heartbeat
local now = love.timer.getTime

local function fail(msg, sock)
    inbox:push({ ev = "closed", msg = msg })
    if sock then sock:close() end
end

local sock, err = socket.tcp()
if sock then
    sock:settimeout(Config.net.connectTimeout)
    local ok
    ok, err = sock:connect(host, port)
    if not ok then sock:close(); sock = nil end
end
if not sock then return fail("CANNOT REACH SERVER (" .. tostring(err) .. ")") end
sock:setoption("tcp-nodelay", true)

local function sendAll(data)
    return SendAll.run(function(payload, first)
        return sock:send(payload, first)
    end, data)
end

math.randomseed(os.time() + math.floor(now() * 1000))
local key = {}
for i = 1, 16 do key[i] = string.char(math.random(0, 255)) end
local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = b64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = b64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        out[#out + 1] = b64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        out[#out + 1] = b64:sub(n % 64 + 1, n % 64 + 1)
    end
    local pad = (3 - #s % 3) % 3
    for _ = 1, pad do out[#out + 1] = "=" end
    return table.concat(out)
end

local ok, e = sendAll("GET " .. path .. " HTTP/1.1\r\nHost: " .. host ..
    "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " .. base64(table.concat(key)) ..
    "\r\nSec-WebSocket-Version: 13\r\n\r\n")
if not ok then return fail("CANNOT REACH SERVER (" .. tostring(e) .. ")", sock) end
local status = sock:receive("*l")
if not status or not status:match("^HTTP/1%.1 101") then
    return fail("SERVER REFUSED (" .. tostring(status) .. ")", sock)
end
repeat
    local line = sock:receive("*l")
    if not line then return fail("CONNECTION LOST", sock) end
until line == ""

sock:settimeout(Config.net.pollTimeout)
inbox:push({ ev = "open" })

local lastSend = now()

local function frame(op, payload)
    local n = #payload
    local head = string.char(0x80 + op)
    if n < 126 then
        head = head .. string.char(0x80 + n)
    elseif n < 65536 then
        head = head .. string.char(0x80 + 126, math.floor(n / 256), n % 256)
    else
        head = head .. string.char(0x80 + 127, 0, 0, 0, 0,
            math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    end
    local m = { math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255) }
    local out = {}
    for i = 1, n do out[i] = string.char(bit.bxor(payload:byte(i), m[(i - 1) % 4 + 1])) end
    return head .. string.char(m[1], m[2], m[3], m[4]) .. table.concat(out)
end

local function send(op, payload)
    sock:settimeout(Config.net.sendTimeout)
    local ok, err2 = sendAll(frame(op, payload))
    sock:settimeout(Config.net.pollTimeout)
    lastSend = now()
    if not ok then return err2 or "send failed" end
    return nil
end

local buf, parts = "", {}

while true do
    local msg = outbox:pop()
    while msg ~= nil do
        if msg == false then
            send(8, "")
            sock:close()
            return
        end
        if send(1, msg) then return fail("CONNECTION LOST", sock) end
        msg = outbox:pop()
    end
    if now() - lastSend > BEAT and send(1, "I\nHB") then return fail("CONNECTION LOST", sock) end

    local data, rerr, partial = sock:receive(Config.net.receiveBytes)
    local chunk = data or partial
    if chunk and #chunk > 0 then buf = buf .. chunk end
    if rerr and rerr ~= "timeout" then
        local msg = rerr == "closed" and "SERVER CLOSED THE CONNECTION" or "CONNECTION LOST"
        return fail(msg, sock)
    end

    while #buf >= 2 do
        local b1, b2 = buf:byte(1, 2)
        local fin, op = b1 >= 128, b1 % 16
        local n, at = b2 % 128, 3
        if n == 126 then
            if #buf < 4 then break end
            n, at = buf:byte(3) * 256 + buf:byte(4), 5
        elseif n == 127 then
            if #buf < 10 then break end
            n = 0
            for i = 7, 10 do n = n * 256 + buf:byte(i) end
            at = 11
        end
        if n > MAX_FRAME then return fail("BAD FRAME FROM SERVER", sock) end
        local masked = b2 >= 128
        local mstart = at
        if masked then at = at + 4 end
        if #buf < at + n - 1 then break end
        local payload = buf:sub(at, at + n - 1)
        if masked then
            local o = {}
            for i = 1, n do o[i] = string.char(bit.bxor(payload:byte(i), buf:byte(mstart + (i - 1) % 4))) end
            payload = table.concat(o)
        end
        buf = buf:sub(at + n)
        if op == 8 then
            return fail("SERVER CLOSED THE CONNECTION", sock)
        elseif op == 9 then
            send(10, payload)
        elseif op == 0 or op == 1 or op == 2 then
            parts[#parts + 1] = payload
            if fin then
                inbox:push(table.concat(parts))
                parts = {}
            end
        end
    end
end
