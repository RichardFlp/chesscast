local Board = require("src.chess.board")

local T = {}

local function perft(b, depth, bufs)
    if depth == 0 then return 1 end
    local buf = bufs[depth]
    local n = b:gen(buf, false)
    local side = b.side
    local total = 0
    for i = 1, n do
        b:make(buf[i])
        if not b:inCheck(side) then total = total + perft(b, depth - 1, bufs) end
        b:unmake()
    end
    return total
end
T.perft = perft

T.CASES = {
    { "start", Board.START_FEN, { 20, 400, 8902, 197281, 4865609 } },
    { "kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", { 48, 2039, 97862, 4085603 } },
    { "pos3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238 } },
    { "pos4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", { 6, 264, 9467 } },
    { "pos5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379 } },
}

function T.run(log)
    log = log or print
    local ok = true
    for _, c in ipairs(T.CASES) do
        local b = Board.fromFEN(c[2])
        local bufs = {}
        for d = 1, 8 do bufs[d] = {} end
        for d, want in ipairs(c[3]) do
            local t0 = os.clock()
            local got = perft(b, d, bufs)
            local pass = got == want
            ok = ok and pass
            log(string.format("perft %-9s d%d %8d %s (%.2fs)", c[1], d, got, pass and "ok" or ("FAIL want " .. want), os.clock() - t0))
        end
    end
    return ok
end

return T
