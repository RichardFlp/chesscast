local R = {}

local char, byte, floor = string.char, string.byte, math.floor
local concat = table.concat

local function le(n, bytes)
    local t = {}
    for i = 1, bytes do
        t[i] = n % 256
        n = floor(n / 256)
    end
    return char(unpack(t))
end

local function varint(n)
    if n < 251 then return char(n) end
    if n < 65536 then return char(251) .. le(n, 2) end
    if n < 4294967296 then return char(252) .. le(n, 4) end
    return char(253) .. le(n, 8)
end

local function str(s) return varint(#s) .. s end
local function opt(s) if s == nil then return "\0" end return "\1" .. str(s) end

function R.frame(payload) return le(#payload, 4) .. payload end

function R.hello(appKey, roomCode, clientHash, displayName)
    return concat { varint(0), str(appKey), str(roomCode or ""), str(clientHash), opt(displayName), opt(nil), opt(nil) }
end

function R.move(blob) return varint(1) .. str(blob) end
function R.input(blob) return varint(2) .. str(blob) end
function R.leave() return varint(3) .. varint(8) end
function R.requestState() return varint(4) end
function R.ping() return varint(5) end

local function rdLE(s, p, bytes)
    local n, mul = 0, 1
    for i = 0, bytes - 1 do
        n = n + byte(s, p + i) * mul
        mul = mul * 256
    end
    return n, p + bytes
end

local function rdVar(s, p)
    local b = byte(s, p)
    if not b then error("truncated") end
    if b < 251 then return b, p + 1 end
    if b == 251 then return rdLE(s, p + 1, 2) end
    if b == 252 then return rdLE(s, p + 1, 4) end
    if b == 253 then return rdLE(s, p + 1, 8) end
    error("bad varint")
end

local function rdStr(s, p)
    local n
    n, p = rdVar(s, p)
    if p + n - 1 > #s then error("truncated") end
    return s:sub(p, p + n - 1), p + n
end

local function rdOptStr(s, p)
    local flag = byte(s, p)
    if flag == 0 then return nil, p + 1 end
    return rdStr(s, p + 1)
end

local function skipJson(s, p)
    local tag
    tag, p = rdVar(s, p)
    if tag == 0 then return p end
    if tag == 1 then return p + 1 end
    if tag == 2 then return p + 8 end
    if tag == 3 then local _; _, p = rdStr(s, p); return p end
    if tag == 4 then
        local n; n, p = rdVar(s, p)
        for _ = 1, n do p = skipJson(s, p) end
        return p
    end
    if tag == 5 then
        local n; n, p = rdVar(s, p)
        for _ = 1, n do
            local _; _, p = rdStr(s, p)
            p = skipJson(s, p)
        end
        return p
    end
    error("bad json tag")
end

local function rdSettings(s, p, out)
    out.max_players, p = rdVar(s, p)
    out.min_players, p = rdVar(s, p)
    out.is_public = byte(s, p) == 1; p = p + 1
    local _
    _, p = rdOptStr(s, p)
    out.accept_required = byte(s, p) == 1; p = p + 1
    if byte(s, p) == 1 then p = skipJson(s, p + 1) else p = p + 1 end
    return p
end

local function decode(s)
    local tag, p = rdVar(s, 1)
    local m = {}
    if tag == 0 then
        m.t = "joined"
        m.code, p = rdStr(s, p)
        m.peer, p = rdVar(s, p)
        m.host, p = rdVar(s, p)
        m.side = byte(s, p); p = p + 1
        p = rdSettings(s, p, m)
        if byte(s, p) == 1 then m.state, p = rdStr(s, p + 1) end
    elseif tag == 1 then
        m.t = "room_list"
    elseif tag == 2 then
        m.t = "peer_joined"
        m.peer, p = rdVar(s, p)
        m.hash, p = rdStr(s, p)
        m.name, p = rdOptStr(s, p)
    elseif tag == 3 then
        m.t = "peer_left"
        m.peer, p = rdVar(s, p)
    elseif tag == 4 then
        m.t = "peer_input"
        m.peer, p = rdVar(s, p)
        m.blob, p = rdStr(s, p)
    elseif tag == 5 then
        m.t = "state"
        m.blob, p = rdStr(s, p)
    elseif tag == 6 then
        m.t = "move_ok"
    elseif tag == 7 then
        m.t = "move_rejected"
        m.reason, p = rdStr(s, p)
    elseif tag == 8 then
        m.t = "event"
        local ev
        ev, p = rdVar(s, p)
        m.event = ({ [0] = "host_transferred", "kicked", "banned", "settings" })[ev] or "unknown"
        if ev == 0 then m.peer, p = rdVar(s, p) end
    elseif tag == 9 then
        m.t = "pong"
    elseif tag == 10 then
        m.t = "error"
        m.message, p = rdStr(s, p)
    else
        m.t = "unknown"
    end
    return m
end

function R.decode(payload)
    local ok, m = pcall(decode, payload)
    if ok then return m end
    return nil, tostring(m)
end

return R
