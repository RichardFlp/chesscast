local P = {}

local ERRORS = {
    CODE_TAKEN = "ROOM CODE TAKEN",
    ROOM_FULL = "ROOM IS FULL",
    ROOM_NOT_FOUND = "ROOM NOT FOUND",
    ROOM_ENDED = "ROOM HAS ENDED",
    BAD_CODE = "INVALID ROOM CODE",
    BAD_ROLE = "INVALID PLAYER ROLE",
    BAD_ROOM = "INVALID ROOM",
    BAD_REQUEST = "CONNECTION ERROR",
    ["ROOM CODE TAKEN"] = "ROOM CODE TAKEN",
    ["ROOM IS FULL"] = "ROOM IS FULL",
    ["ROOM NOT FOUND"] = "ROOM NOT FOUND",
}

local function errorMessage(code)
    return ERRORS[code] or code or "CONNECTION ERROR"
end

function P.hello(_, _, _, _, role, rating)
    if role == "host" then return "H" end
    if role == "queue" then
        if rating ~= nil then return "Q\n" .. tostring(rating) end
        return "Q"
    end
    return "G"
end

function P.move(blob) return "M\n" .. blob end
function P.input(blob) return "I\n" .. blob end
function P.leave() return "L" end

function P.decode(raw)
    if type(raw) ~= "string" then return nil, "bad message" end

    local head, body = raw:match("^([^\n]*)\n?(.*)$")
    local kind, a, b, c = head:match("^(%a)%s*(%S*)%s*(%S*)%s*(%S*)")
    if not kind then return nil, "unknown message" end

    if kind == "J" then
        local code, peer, host = head:match("^J%s+(%S+)%s+(%d+)%s+(%d+)")
        if not code then return nil, "bad join" end
        return {
            t = "joined",
            code = code,
            peer = tonumber(peer),
            host = tonumber(host),
            state = body ~= "" and body or nil,
        }
    elseif kind == "P" then
        return { t = "peer_joined", peer = tonumber(a), hash = "" }
    elseif kind == "X" then
        return { t = "peer_left", peer = tonumber(a) }
    elseif kind == "S" then
        return { t = "state", blob = body }
    elseif kind == "I" then
        return { t = "peer_input", peer = tonumber(a), blob = body }
    elseif kind == "Q" then
        local code, tag, own, rival = head:match("^Q%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)")
        return {
            t = "matched",
            code = code or a,
            role = tag == "H" and "host" or "guest",
            rating = tonumber(own),
            opponentRating = tonumber(rival),
        }
    elseif kind == "W" then
        return { t = "queued" }
    elseif kind == "N" then
        return { t = "pong" }
    elseif kind == "E" then
        local code = head:match("^E%s+(.*)$") or "CONNECTION ERROR"
        return { t = "error", code = code, message = errorMessage(code) }
    end

    return nil, "unknown message"
end

return P
