local P = {}

function P.hello(_, _, _, _, role) return role == "host" and "H" or role == "queue" and "Q" or "G" end
function P.move(blob) return "M\n" .. blob end
function P.input(blob) return "I\n" .. blob end
function P.leave() return "L" end

function P.decode(s)
    local head, body = s:match("^([^\n]*)\n?(.*)$")
    local kind, a, b, c = head:match("^(%a)%s*(%S*)%s*(%S*)%s*(%S*)")
    if kind == "J" then
        return { t = "joined", code = a, peer = tonumber(b), host = tonumber(c),
            state = body ~= "" and body or nil }
    elseif kind == "P" then return { t = "peer_joined", peer = tonumber(a), hash = "" }
    elseif kind == "X" then return { t = "peer_left", peer = tonumber(a) }
    elseif kind == "S" then return { t = "state", blob = body }
    elseif kind == "I" then return { t = "peer_input", peer = tonumber(a), blob = body }
    elseif kind == "Q" then return { t = "matched", code = a, role = b == "H" and "host" or "guest" }
    elseif kind == "W" then return { t = "queued" }
    elseif kind == "N" then return { t = "pong" }
    elseif kind == "E" then return { t = "error", message = head:sub(3) }
    end
    return nil, "unknown message"
end

return P
