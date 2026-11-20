local Board = require("src.chess.board")
local Match = require("src.chess.match")

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
    { "kiwipete",
      "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
      { 48, 2039, 97862, 4085603 } },
    { "pos3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238 } },
    { "pos4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", { 6, 264, 9467 } },
    { "pos5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379 } },
}

local P, Q = Board.P, Board.Q

local function sqn(name)
    return Board.sq(name:byte(1) - 97, name:byte(2) - 49)
end

local function moveOf(b, from, to, promo)
    local list, n = b:legalMoves({})
    for i = 1, n do
        local m = list[i]
        if Board.from(m) == from and Board.to(m) == to
            and (promo == nil or Board.promo(m) == promo) then return m, list end
    end
    return nil, list
end

local function castleCount(b, flag)
    local list, n = b:legalMoves({})
    local count = 0
    for i = 1, n do if Board.flag(list[i]) == flag then count = count + 1 end end
    return count
end

function T.run(log)
    log = log or print
    local ok = true
    local function check(name, cond, extra)
        log(string.format("  %-46s %s%s", name, cond and "ok" or "FAIL", extra and ("  " .. extra) or ""))
        if not cond then ok = false end
    end

    for _, c in ipairs(T.CASES) do
        local b = Board.fromFEN(c[2])
        local bufs = {}
        for d = 1, 8 do bufs[d] = {} end
        for d, want in ipairs(c[3]) do
            local t0 = os.clock()
            local got = perft(b, d, bufs)
            local pass = got == want
            ok = ok and pass
            log(string.format("perft %-9s d%d %8d %s (%.2fs)", c[1], d, got,
                pass and "ok" or ("FAIL want " .. want), os.clock() - t0))
        end
    end

    log("chess rules")
    local function insufficient(fen)
        return Board.fromFEN(fen):insufficientMaterial()
    end
    check("K vs K is insufficient", insufficient("4k3/8/8/8/8/8/8/4K3 w - - 0 1"))
    check("K+B vs K is insufficient", insufficient("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1"))
    check("K+N vs K is insufficient", insufficient("4k3/8/8/8/8/8/8/1N2K3 w - - 0 1"))
    check("same-colour bishops are insufficient", insufficient("5bk1/8/8/8/8/8/8/2B1K3 w - - 0 1"))
    check("opposite-colour bishops are not insufficient", not insufficient("2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1"))
    check("K+N vs K+N is not insufficient", not insufficient("4kn2/8/8/8/8/8/8/1N2K3 w - - 0 1"))

    local b = Board.fromFEN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    check("both white castles are generated", castleCount(b, 3) == 1 and castleCount(b, 4) == 1)

    local through = Board.fromFEN("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    check("castle through an attacked square is refused",
        castleCount(through, 3) == 0 and castleCount(through, 4) == 1)

    local rights = Board.fromFEN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    local rookMove = moveOf(rights, sqn("a1"), sqn("a2"))
    if rookMove then rights:play(rookMove); rights:removeExpired() end
    check("moving a rook clears its castle right", rookMove ~= nil and rights.castle == 13,
        tostring(rights.castle))

    local ep = Board.fromFEN("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1")
    local push = moveOf(ep, sqn("d7"), sqn("d5"))
    if push then ep:play(push); ep:removeExpired() end
    local epMove = moveOf(ep, sqn("e5"), sqn("d6"))
    check("double push sets the en passant square", push ~= nil and ep.ep == sqn("d6"))
    check("en passant capture is legal", epMove ~= nil and Board.flag(epMove) == 2)
    if epMove then ep:play(epMove); ep:removeExpired() end
    check("en passant removes the passed pawn",
        epMove ~= nil and ep.p[sqn("d5")] == 0 and ep.p[sqn("d6")] == P)

    local promo = Board.fromFEN("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    local list, n = promo:legalMoves({})
    local choices, queen = 0, nil
    for i = 1, n do
        local m = list[i]
        if Board.from(m) == sqn("a7") and Board.to(m) == sqn("a8") then
            choices = choices + 1
            if Board.promo(m) == Q then queen = m end
        end
    end
    check("a pawn has four promotion choices", choices == 4, tostring(choices))
    check("promotion SAN names the piece", queen ~= nil and promo:san(queen, list) == "a8=Q")
    if queen then promo:play(queen); promo:removeExpired() end
    check("promotion places the chosen piece", queen ~= nil and promo.p[sqn("a8")] == Q)

    local dis = Board.fromFEN("4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1")
    local knightMove = moveOf(dis, sqn("b1"), sqn("d2"))
    check("ambiguous knight move is disambiguated by file",
        knightMove ~= nil and dis:san(knightMove, select(2, moveOf(dis, sqn("b1"), sqn("d2")))) == "Nbd2")

    local epPos = Board.fromFEN(Board.START_FEN)
    local epPush = moveOf(epPos, sqn("e2"), sqn("e4"))
    if epPush then epPos:play(epPush) end
    local noEp = Board.fromFEN("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
    check("an uncapturable ep square is not in the key", epPos:key() == noEp:key())
    local epLegal = Board.fromFEN("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    local epPlain = Board.fromFEN("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1")
    check("a legal ep square is in the key", epLegal:key() ~= epPlain:key())

    local epPawned = Board.fromFEN("4k3/8/8/3pR3/8/8/8/4K3 w - d6 0 1")
    local epPawnedPlain = Board.fromFEN("4k3/8/8/3pR3/8/8/8/4K3 w - - 0 1")
    epPawned:setStatus(epPawned.id[sqn("e5")], "pawned", epPawned.ply + 6)
    epPawnedPlain:setStatus(epPawnedPlain.id[sqn("e5")], "pawned", epPawnedPlain.ply + 6)
    local epPawnedMove = moveOf(epPawned, sqn("e5"), sqn("d6"))
    check("a pawned piece can capture en passant", epPawnedMove ~= nil and Board.flag(epPawnedMove) == 2)
    check("an ep capture by a pawned piece is in the key", epPawned:key() ~= epPawnedPlain:key())

    local statusKey = Board.fromFEN("4k3/8/8/3q4/8/8/8/4K3 w - - 0 1")
    local plainStatusKey = statusKey:key()
    statusKey:setStatus(statusKey.id[sqn("d5")], "shield", statusKey.ply + 4)
    check("an active status is part of the position key", statusKey:key() ~= plainStatusKey)
    statusKey.ply = statusKey.ply + 4
    statusKey:removeExpired()
    check("an expired status leaves the position key", statusKey:key() == plainStatusKey)

    local zoneKey = Board.fromFEN("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    local plainZoneKey = zoneKey:key()
    zoneKey.zones[1] = { owner = 1, f = 3, r = 3, untilPly = zoneKey.ply + 4 }
    check("an active zone is part of the position key", zoneKey:key() ~= plainZoneKey)

    local effectKey = Board.fromFEN("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    local plainEffectKey = effectKey:key()
    effectKey.fog[1], effectKey.epAny[1], effectKey.lastStand[1] =
        effectKey.ply + 4, effectKey.ply + 4, effectKey.ply + 4
    check("active global effects are part of the position key", effectKey:key() ~= plainEffectKey)

    local capturedKey = Board.fromFEN("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    local plainCapturedKey = capturedKey:key()
    capturedKey.captured[1][1] = { t = Q, id = 99, pawned = false }
    check("captured pieces are part of the position key", capturedKey:key() ~= plainCapturedKey)

    local noted = Match.new { mode = "local" }
    noted.board:setStatus(noted.board.id[sqn("e1")], "shield", noted.board.ply + 4)
    local notedKey = noted.board:key()
    noted:positionChanged()
    check("a non-move position change is recorded", noted.reps[notedKey] == 1)
    noted:positionChanged()
    check("an unchanged position is not counted twice", noted.reps[notedKey] == 1)

    local original = Board.new()
    local first = moveOf(original, sqn("e2"), sqn("e4"))
    if first then original:play(first); original:removeExpired() end
    local cloned = original:clone()
    check("clone preserves the position key", cloned:key() == original:key())
    local reply = moveOf(cloned, sqn("e7"), sqn("e5"))
    if reply then cloned:play(reply); cloned:removeExpired() end
    check("playing on a clone does not change the original",
        reply ~= nil and original.p[sqn("e4")] == P and original.p[sqn("e5")] == 0
        and cloned.p[sqn("e4")] == P and cloned.p[sqn("e5")] == -P)

    local mate = Match.new { fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", mode = "local" }
    local mateMove = mate:findMove(sqn("d1"), sqn("d8"), 0)
    if mateMove then mate:playMove(mateMove) end
    check("checkmate is detected", mate.result and mate.result.reason == "CHECKMATE"
        and mate.result.winner == 1)
    check("checkmate is written with #", mate.history[#mate.history]
        and mate.history[#mate.history].san:sub(-1) == "#")

    local stale = Match.new { fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", mode = "local" }
    check("stalemate is detected", stale.result and stale.result.reason == "STALEMATE"
        and stale.result.winner == 0)

    local fifty = Match.new { fen = "4k3/8/8/8/8/8/8/4K2R w - - 100 1", mode = "local" }
    check("fifty-move draw is detected", fifty.result and fifty.result.reason == "FIFTY MOVES")

    local rep = Match.new { mode = "local" }
    local cycle = { { "g1", "f3" }, { "g8", "f6" }, { "f3", "g1" }, { "f6", "g8" } }
    for _ = 1, 2 do
        for _, pair in ipairs(cycle) do
            local m = rep:findMove(sqn(pair[1]), sqn(pair[2]), 0)
            if m then rep:playMove(m) end
        end
    end
    check("threefold repetition is detected", rep.result and rep.result.reason == "REPETITION")

    local rewind = Match.new { mode = "local" }
    local key = rewind.board:key()
    local before = {}
    for k, v in pairs(rewind.reps) do before[k] = v end
    for _, pair in ipairs(cycle) do
        local m = rewind:findMove(sqn(pair[1]), sqn(pair[2]), 0)
        if m then rewind:playMove(m) end
    end
    local cycled = rewind.reps[key] == 2
    rewind:rewind(0, before)
    local restored = rewind.reps[key] == 1 and #rewind.history == 0
    for _, pair in ipairs(cycle) do
        local m = rewind:findMove(sqn(pair[1]), sqn(pair[2]), 0)
        if m then rewind:playMove(m) end
    end
    check("time rewind restores repetition counts", cycled and restored
        and rewind.reps[key] == 2 and not rewind.result)

    local timed = Match.new { clock = 10, mode = "local" }
    local timedOut = timed:tick(11)
    check("the side to move is flagged at zero", timedOut and timed.result and timed.result.reason == "TIMEOUT"
        and timed.result.winner == -1)

    local remoteTick = Match.new { clock = 10, mode = "online", human = 1 }
    remoteTick.board.side = -1
    local remoteTimedOut = remoteTick:tick(11)
    check("a remote timeout is not announced locally", not remoteTimedOut and not remoteTick.result)

    local bare = Match.new { fen = "4k3/8/8/8/8/8/8/4K3 w - - 0 1", clock = 10, mode = "local" }
    bare.result = nil
    bare:flag(1)
    check("timeout with no mating material is a draw", bare.result and bare.result.winner == 0
        and bare.result.reason == "TIMEOUT")

    local bishop = Match.new { fen = "2b1k3/8/8/8/8/8/8/4K3 w - - 0 1", clock = 10, mode = "local" }
    bishop.result = nil
    bishop:flag(1)
    check("timeout against only a bishop is a draw", bishop.result and bishop.result.winner == 0)

    local knight = Match.new { fen = "1n2k3/8/8/8/8/8/8/4K3 w - - 0 1", clock = 10, mode = "local" }
    knight.result = nil
    knight:flag(1)
    check("timeout against only a knight is a draw", knight.result and knight.result.winner == 0)

    local rook = Match.new { fen = "r3k3/8/8/8/8/8/8/4K3 w - - 0 1", clock = 10, mode = "local" }
    rook.result = nil
    rook:flag(1)
    check("timeout against a rook is a win", rook.result and rook.result.winner == -1)

    local twoKnights = Match.new { fen = "1n2kn2/8/8/8/8/8/8/4K3 w - - 0 1", clock = 10, mode = "local" }
    twoKnights.result = nil
    twoKnights:flag(1)
    check("timeout against two knights is a win", twoKnights.result and twoKnights.result.winner == -1)

    local loneWinner = Match.new { fen = "4k3/8/8/8/8/8/8/3QK3 w - - 0 1", clock = 10, mode = "local" }
    loneWinner.result = nil
    loneWinner:flag(1)
    check("timeout when the winner has only a king is a draw", loneWinner.result
        and loneWinner.result.winner == 0 and loneWinner.result.reason == "TIMEOUT")

    local resigned = Match.new { mode = "local" }
    resigned:resign(1)
    check("resignation gives the game to the other side", resigned.result
        and resigned.result.reason == "RESIGNED" and resigned.result.winner == -1)

    return ok
end

return T
