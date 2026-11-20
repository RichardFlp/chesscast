local Config = require("src.config")

local AFK = {}

function AFK.limit(match, online, started, connected)
    if not online or not started or not connected or match.result then return nil end
    if match.board.side ~= -match.human then return nil end
    if #match.history > 0 and match.timed then return nil end
    return #match.history == 0 and Config.net.afkStart or Config.net.afkTurn
end

function AFK.remaining(elapsed, limit)
    if not limit or elapsed < Config.net.afkWarn then return nil end
    return math.max(0, math.ceil(limit - elapsed))
end

function AFK.advance(elapsed, limit, dt)
    if not limit then return 0, false end
    elapsed = math.min(elapsed + dt, limit)
    return elapsed, elapsed >= limit
end

return AFK
