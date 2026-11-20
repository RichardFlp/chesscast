local Board = require("src.chess.board")
local Search = require("src.ai.search")

local T = {}

local function moveName(m)
    local f, t, promo = Board.decode(m)
    return Board.name(f) .. Board.name(t) .. (promo > 0 and Board.LETTER[promo]:lower() or "")
end

function T.run(log)
    local ok = true
    local function check(name, cond, extra)
        log(string.format("  %-46s %s%s", name, cond and "ok" or "FAIL", extra and ("  " .. extra) or ""))
        if not cond then ok = false end
    end
    log("AI tests")
    local SHARP = { depth = 4, qs = true, time = 2, noise = 0, blunder = 0 }

    local b = Board.fromFEN("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
    local m = Search.best(b, SHARP, 2)
    check("mate in one (Rd8#)", moveName(m) == "d1d8", moveName(m))

    b = Board.fromFEN("3r2k1/8/8/8/8/8/5PPP/6K1 b - - 0 1")
    m = Search.best(b, SHARP, 2)
    check("mate in one for black (Rd1#)", moveName(m) == "d8d1", moveName(m))

    b = Board.fromFEN("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1")
    m = Search.best(b, SHARP, 2)
    check("takes a hanging queen", moveName(m) == "d2d5", moveName(m))

    b = Board.fromFEN("4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1")
    m = Search.best(b, SHARP, 2)
    check("avoids a defended pawn with the queen", moveName(m) ~= "d1d5", moveName(m))

    b = Board.fromFEN("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1")
    b:setStatus(b.id[Board.sq(3, 4)], "shield", b.ply + 4)
    m = Search.best(b, SHARP, 2)
    check("respects a shield", moveName(m) ~= "d2d5", moveName(m))

    b = Board.fromFEN("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
    b:setStatus(b.id[Board.sq(3, 0)], "frozen", b.ply + 2)
    m = Search.best(b, SHARP, 2)
    check("frozen rook does not move", Board.from(m) ~= Board.sq(3, 0), moveName(m))

    b = Board.fromFEN("7k/8/6K1/8/8/8/8/5Q2 w - - 0 1")
    m = Search.best(b, SHARP, 2)
    local c = b:clone()
    c:play(m)
    local mated = c:inCheck(c.side) and not c:hasLegalMove()
    local stale = not c:inCheck(c.side) and not c:hasLegalMove()
    check("K+Q vs K: no stalemate", not stale, moveName(m) .. (mated and " (mate)" or ""))

    b = Board.new()
    local allLegal = true
    for _ = 1, 16 do
        local mv = Search.best(b, 1, 0.3)
        local legal = b:legalMoves({})
        local found = false
        for _, l in ipairs(legal) do if l == mv then found = true end end
        if not found then allLegal = false; break end
        b:play(mv)
        if not b:hasLegalMove() then break end
    end
    check("16 easy-CPU plies are all legal", allLegal)

    local t0 = os.clock()
    local score, nodes = Search.score(Board.new(), 4, 20)
    local dt = os.clock() - t0
    check("start position depth 4 visits nodes", type(score) == "number" and nodes > 0,
        string.format("%d nodes, %.2fs, %d knps", nodes, dt, nodes / math.max(dt, 1e-3) / 1000))

    local job = Search.start(Board.new(), SHARP)
    local steps = 0
    while not job:step(0.004) do steps = steps + 1; if steps > 100000 then break end end
    check("coroutine search completes", job.move ~= nil, string.format("%d yields, depth %d", steps, job.depth or 0))

    check("unknown level falls back to medium", Search.level(999) == Search.LEVELS[2])
    local custom = { depth = 1 }
    check("level tables pass through", Search.level(custom) == custom)
    local finished = Search.start(Board.fromFEN("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"), SHARP)
    local done = false
    for _ = 1, 1000 do
        done = finished:step(0.004)
        if done then break end
    end
    check("finished position returns no move", done and finished.move == nil)
    return ok
end

return T
