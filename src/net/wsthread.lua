local inbox, outbox, host, port, path = ...
require("love.timer")
local socket = require("socket")
local bit = require("bit")

local MAX_FRAME = 64 * 1024
local BEAT = 3
local now = love.timer.getTime

local function fail(msg, sock)
    inbox:push({ ev = "closed", msg = msg })
    if sock then sock:close() end
end

local sock, err = socket.tcp()
if sock then
    sock:settimeout(8)
    local ok
    ok, err = sock:connect(host, port)
    if not ok then sock:close(); sock = nil end
end
if not sock then return fail("CANNOT REACH SERVER (" .. tostring(err) .. ")") end
sock:setoption("tcp-nodelay", true)

math.randomseed(os.time() + math.floor(now() * 1000))
local key = {}
for i = 1, 16 do key[i] = string.char(math.random(0, 255)) end
local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
    return ((s:gsub(".", function(c)
        local r, b = "", c:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return b64:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#s % 3 + 1])
end

local _, e = sock:send("GET " .. path .. " HTTP/1.1\r\nHost: " .. host ..
    "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " .. base64(table.concat(key)) ..
    "\r\nSec-WebSocket-Version: 13\r\n\r\n")
if e then return fail("CANNOT REACH SERVER (" .. e .. ")", sock) end
local status = sock:receive("*l")
if not status or not status:match("^HTTP/1%.1 101") then
    return fail("SERVER REFUSED (" .. tostring(status) .. ")", sock)
end
repeat
    local line = sock:receive("*l")
    if not line then return fail("CONNECTION LOST", sock) end
until line == ""

sock:settimeout(0.03)
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
    sock:settimeout(5)
    local _, err2 = sock:send(frame(op, payload))
    sock:settimeout(0.03)
    lastSend = now()
    return err2
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

    local data, rerr, partial = sock:receive(8192)
    local chunk = data or partial
    if chunk and #chunk > 0 then buf = buf .. chunk end
    if rerr == "closed" then return fail("SERVER CLOSED THE CONNECTION", sock) end

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
