local Party = require("src.net.party")
local Roomie = require("src.net.roomie")
local Online = require("src.net.online")
local Sync = require("src.net.sync")
local AFK = require("src.net.afk")
local SendAll = require("src.net.sendall")
local Board = require("src.chess.board")
local Defs = require("src.cards.defs")
local Config = require("src.config")
local Manager = require("src.states.manager")
local Transition = require("src.animations.transition")

local T = {}

local function check(log, name, condition)
    log(string.format("  %-34s %s", name, condition and "ok" or "FAIL"))
    return condition
end

local function testParty(log)
    local ok = true

    local message = Party.decode("J ABC123 2 1\nS 7 1 600 1 HOST")
    ok = check(log, "join decode", message and message.t == "joined"
        and message.code == "ABC123" and message.peer == 2 and message.host == 1) and ok

    message = Party.decode("I 2\nM 1 2 0 600")
    ok = check(log, "input decode", message and message.t == "peer_input"
        and message.peer == 2 and message.blob == "M 1 2 0 600") and ok

    message = Party.decode("Q ABC123 H")
    ok = check(log, "queue decode", message and message.t == "matched"
        and message.code == "ABC123" and message.role == "host") and ok

    message = Party.decode("Q ABC123 G")
    ok = check(log, "queue guest decode", message and message.t == "matched"
        and message.code == "ABC123" and message.role == "guest") and ok

    message = Party.decode("Q ABC123 H 1200 1300")
    ok = check(log, "ranked queue decode", message and message.rating == 1200
        and message.opponentRating == 1300) and ok

    message = Party.decode("Q ABC123 G 1300 1200")
    ok = check(log, "ranked guest queue decode", message and message.rating == 1300
        and message.opponentRating == 1200) and ok

    message = Party.decode("W")
    ok = check(log, "queue wait decode", message and message.t == "queued") and ok

    ok = check(log, "queue hello", Party.hello(Config.app.key, "", "", "", "queue") == "Q") and ok
    ok = check(log, "ranked queue hello", Party.hello(Config.app.key, "", "", "", "queue", 1200) == "Q\n1200") and ok
    ok = check(log, "zero ELO is sent", Party.hello(Config.app.key, "", "", "", "queue", 0) == "Q\n0") and ok

    message = Party.decode("N")
    ok = check(log, "pong decode", message and message.t == "pong") and ok

    message = Party.decode("E CODE_TAKEN")
    ok = check(log, "new error text", message and message.message == "ROOM CODE TAKEN"
        and message.code == "CODE_TAKEN") and ok

    message = Party.decode("E ROOM NOT FOUND")
    ok = check(log, "old error text", message and message.message == "ROOM NOT FOUND") and ok

    ok = check(log, "bad message", Party.decode("???") == nil) and ok
    return ok
end

local function roomieString(text)
    return string.char(#text) .. text
end

local function testRoomie(log)
    local ok = true
    local joined = string.char(0) .. roomieString("ABC234")
        .. string.char(1, 1, 0, 2, 2, 0, 0, 0, 0, 0)

    local message = Roomie.decode(joined)
    ok = check(log, "roomie join", message and message.t == "joined"
        and message.code == "ABC234" and message.peer == 1) and ok

    message = Roomie.decode(string.char(10) .. roomieString("room not found"))
    ok = check(log, "roomie error", message and message.t == "error"
        and message.message == "room not found") and ok

    ok = check(log, "roomie bad frame", Roomie.decode("\0") == nil) and ok
    ok = check(log, "roomie host hello", Roomie.hello(Config.app.key, "", "0123456789abcdef") ~= "") and ok
    return ok
end

local function testOnline(log)
    local ok = true

    ok = check(log, "valid code", Online.validCode("ABC234")) and ok
    ok = check(log, "roomie code", Online.validCode("2GXNU6")) and ok
    ok = check(log, "short code", not Online.validCode("ABC23")) and ok
    ok = check(log, "ambiguous code", not Online.validCode("ABCO23")) and ok
    ok = check(log, "guest room code", Online.roomCode("guest", "party", "ABC234") == "ABC234") and ok
    ok = check(log, "guest empty code", Online.roomCode("guest", "party", "") == nil) and ok
    ok = check(log, "roomie host empty", Online.roomCode("host", "roomie", "") == "") and ok
    ok = check(log, "party host code", Online.validCode(Online.roomCode("host", "party", ""))) and ok
    local bulletRoom = Config.net.queuePrefix .. "BULLET"
    local blitzRoom = Config.net.queuePrefix .. "BLITZ"
    local rankedRoom = Config.net.rankedQueuePrefix .. "BLITZ"
    ok = check(log, "queue code", Online.roomCode("queue", "party", bulletRoom) == bulletRoom) and ok
    ok = check(log, "queue modes are split", bulletRoom ~= blitzRoom) and ok
    ok = check(log, "ranked queue is separate", rankedRoom ~= blitzRoom
        and Online.roomCode("queue", "party", rankedRoom) == rankedRoom) and ok
    ok = check(log, "queue backend", Online.backend("queue") == "party") and ok
    ok = check(log, "party pin", Online.backend("host", "party") == "party") and ok
    ok = check(log, "error normalize", Online.normalize("room_not_found") == "ROOM NOT FOUND") and ok
    ok = check(log, "room missing", Online.roomMissing("room not found")) and ok
    ok = check(log, "room missing old", Online.roomMissing("ROOM_NOT_FOUND")) and ok
    ok = check(log, "room full", not Online.roomMissing("ROOM_IS_FULL")) and ok
    ok = check(log, "code taken", Online.codeTaken("CODE_TAKEN")) and ok

    local parsed = Online.parseUrl("ws://127.0.0.1:8787/parties/main")
    ok = check(log, "local url", parsed and parsed.host == "127.0.0.1"
        and parsed.port == 8787 and parsed.path == "/parties/main/") and ok

    parsed = Online.parseUrl("wss://relay.example/room/")
    ok = check(log, "secure url", parsed and parsed.scheme == "wss"
        and parsed.port == 443 and parsed.path == "/room/") and ok

    ok = check(log, "bad url", Online.parseUrl("relay.example") == nil) and ok
    ok = check(log, "code type and case", not Online.validCode(nil)
        and not Online.validCode("abc234")) and ok
    parsed = Online.parseUrl("ws://relay.example")
    ok = check(log, "url default path", parsed and parsed.path == "/"
        and parsed.port == Config.relay.ports.plain) and ok
    return ok
end

local function testSendAll(log)
    local ok = true

    local wire, starts = "", {}
    local sent = SendAll.run(function(data, first)
        starts[#starts + 1] = first
        local n = math.min(3, #data - first + 1)
        wire = wire .. data:sub(first, first + n - 1)
        return n
    end, "abcdefgh")
    ok = check(log, "sendall writes all bytes", sent == 8 and wire == "abcdefgh") and ok
    ok = check(log, "sendall advances by sent bytes", #starts == 3 and starts[1] == 1
        and starts[2] == 4 and starts[3] == 7) and ok

    local failed, err = SendAll.run(function(_, first)
        if first > 3 then return nil, "socket closed" end
        return 3
    end, "abcdefgh")
    ok = check(log, "sendall reports a closed socket", failed == nil and err == "socket closed") and ok

    local stalled, stallErr = SendAll.run(function() return 0 end, "abc")
    ok = check(log, "sendall rejects zero progress", stalled == nil and stallErr == "send failed") and ok

    local calls = 0
    local empty = SendAll.run(function() calls = calls + 1 return 0 end, "")
    ok = check(log, "sendall handles an empty frame", empty == 0 and calls == 0) and ok

    return ok
end

local function fakeSync(role, human, side)
    local game = {
        match = { human = human, board = { side = side }, result = nil, timed = false,
            findMove = function() return 1 end },
        applyMove = function() end,
    }
    local sent = {}
    local session = {
        heard = 0,
        sendMove = function(_, blob) sent.move = blob end,
        sendInput = function(_, blob) sent.input = blob end,
    }
    local sync = Sync.new(game, session, role, { "S 1 1 600 1 HOST" })
    sync.lastBeat = 0
    return sync, game, sent
end

local function testAfk(log)
    local ok = true
    local match = { human = 1, timed = true, history = {}, board = { side = -1 }, result = nil }

    ok = check(log, "first move deadline", AFK.limit(match, true, true, true)
        == Config.net.afkStart) and ok
    match.board.side = 1
    ok = check(log, "no deadline on own turn", AFK.limit(match, true, true, true) == nil) and ok
    match.board.side = -1
    match.history = { 1 }
    ok = check(log, "clock owns timed turns", AFK.limit(match, true, true, true) == nil) and ok
    match.timed = false
    ok = check(log, "untimed turn deadline", AFK.limit(match, true, true, true)
        == Config.net.afkTurn) and ok
    match.result = { winner = 0, reason = "AFK" }
    ok = check(log, "finished game has no deadline", AFK.limit(match, true, true, true) == nil) and ok
    match.result = nil
    ok = check(log, "offline game has no deadline", AFK.limit(match, false, true, true) == nil) and ok

    local elapsed, expired = AFK.advance(0, Config.net.afkStart, Config.net.afkStart - 1)
    ok = check(log, "deadline advances", elapsed == Config.net.afkStart - 1 and not expired) and ok
    elapsed, expired = AFK.advance(elapsed, Config.net.afkStart, 1)
    ok = check(log, "deadline expires", elapsed == Config.net.afkStart and expired) and ok
    elapsed, expired = AFK.advance(12, nil, 1)
    ok = check(log, "deadline clears", elapsed == 0 and not expired) and ok
    ok = check(log, "warning waits", AFK.remaining(Config.net.afkWarn - 1,
        Config.net.afkStart) == nil) and ok
    ok = check(log, "warning counts down", AFK.remaining(Config.net.afkWarn,
        Config.net.afkStart) == Config.net.afkStart - Config.net.afkWarn) and ok
    return ok
end

local function testSync(log)
    local ok = true

    local header = Sync.parseHeader("S 7 1 600 1 HOST")
    ok = check(log, "header decode", header and header.seed == 7 and header.spells
        and header.clock == 600 and header.hostSide == 1 and header.name == "HOST"
        and header.rating == nil) and ok

    local rated = Sync.parseHeader(Sync.header(7, true, 600, 1, "HOST", 1200))
    ok = check(log, "header carries rating", rated and rated.rating == 1200) and ok
    ok = check(log, "header rating bound", Sync.parseHeader("S 7 1 600 1 HOST "
        .. (Config.net.ratingMax + 1)) == nil) and ok

    ok = check(log, "header side", Sync.parseHeader("S 7 1 600 0 HOST") == nil) and ok
    ok = check(log, "header clock", Sync.parseHeader("S 7 1 " .. (Config.net.maxClock + 1) .. " 1 HOST") == nil) and ok
    ok = check(log, "header seed", Sync.parseHeader("S 0 1 600 1 HOST") == nil) and ok
    ok = check(log, "header spells", Sync.parseHeader("S 7 2 600 1 HOST") == nil) and ok
    ok = check(log, "header seed bounds", Sync.parseHeader("S " .. Config.net.maxSeed .. " 1 600 1 A") ~= nil
        and Sync.parseHeader("S " .. (Config.net.maxSeed + 1) .. " 1 600 1 A") == nil) and ok
    ok = check(log, "header clock bound", Sync.parseHeader("S 7 1 " .. Config.net.maxClock .. " 1 A") ~= nil) and ok

    local action = Sync.parseAction("M 1 2 0 600")
    ok = check(log, "move action", action and action.kind == "M" and action.from == 1
        and action.to == 2 and action.promo == 0 and action.clock == 600) and ok

    ok = check(log, "move square", Sync.parseAction("M 0 2 0 600") == nil) and ok
    ok = check(log, "move promo", Sync.parseAction("M 1 2 6 600") == nil) and ok
    ok = check(log, "move clock", Sync.parseAction("M 1 2 0 -1") == nil) and ok

    action = Sync.parseAction("C shield 1 - 600")
    ok = check(log, "card action", action and action.kind == "C"
        and action.slug == "shield" and action.a == "1" and action.c == "-") and ok

    action = Sync.parseAction("C magnetic_pull 1 - 600")
    ok = check(log, "underscored card", action and action.slug == "magnetic_pull") and ok

    ok = check(log, "unknown card", Sync.parseAction("C nope 1 - 600") == nil) and ok
    ok = check(log, "resign action", Sync.parseAction("R -1") ~= nil) and ok
    ok = check(log, "abort action", Sync.parseAction("A -1") ~= nil) and ok
    ok = check(log, "bad side", Sync.parseAction("T 2") == nil
        and Sync.parseAction("A 0") == nil) and ok

    ok = check(log, "clean name", Sync.cleanName("hELLo!") == "HELLO") and ok
    ok = check(log, "clean name truncates", Sync.cleanName("abcdefgh") == "ABCDE") and ok
    ok = check(log, "split lines", #Sync.split("a\nb\n") == 2) and ok
    ok = check(log, "empty split", #Sync.split("") == 0) and ok
    ok = check(log, "action target bounds", Sync.parseAction("C shield 0 - 600") == nil
        and Sync.parseAction("C shield 65 - 600") == nil
        and Sync.parseAction("C shield 64 - 600") ~= nil) and ok

    local sync, game = fakeSync("host", 1, 1)
    sync:onMessage({ t = "peer_input", peer = 2, blob = "2|M 1 2 0 600" })
    ok = check(log, "reject action on host turn", sync.qn == 0) and ok

    sync:onMessage({ t = "peer_input", peer = 2, blob = "0|R 1" })
    ok = check(log, "reject resign for host", sync.qn == 0) and ok

    game.match.board.side = -1
    sync:onMessage({ t = "peer_input", peer = 2, blob = "2|M 49 41 0 600" })
    ok = check(log, "accept action on guest turn", sync.qn == 1) and ok

    local bad, badGame = fakeSync("host", 1, -1)
    badGame.match.findMove = function() return nil end
    bad:onMessage({ t = "peer_input", peer = 2, blob = "2|M 1 2 0 600" })
    ok = check(log, "reject illegal move at receipt", bad.qn == 0) and ok

    local noSpells = fakeSync("host", 1, -1)
    noSpells:onMessage({ t = "peer_input", peer = 2, blob = "2|C shield 1 - 600" })
    ok = check(log, "reject card without layer", noSpells.qn == 0) and ok

    local queued, queuedGame = fakeSync("host", 1, -1)
    queued:onMessage({ t = "peer_input", peer = 2, blob = "2|M 49 41 0 600" })
    queuedGame.match.findMove = function() return nil end
    queued:onMessage({ t = "peer_input", peer = 2, blob = "3|M 1 2 0 600" })
    ok = check(log, "defer legality while pending", queued.qn == 2) and ok

    game.match.board.side = 1
    ok = check(log, "reject apply on host turn", not sync:apply("M 1 2 0 600", false)) and ok

    local host, _, hostSent = fakeSync("host", 1, -1)
    host:localAction("M 1 2 0 600")
    ok = check(log, "host broadcasts state", hostSent.move == "S 1 1 600 1 HOST\nM 1 2 0 600"
        and hostSent.input == nil) and ok

    local guest, guestGame = fakeSync("guest", -1, 1)
    guestGame.match.findMove = function() return 1 end
    guest:onMessage({ t = "peer_input", peer = 1, blob = "2|M 49 41 0 600" })
    ok = check(log, "guest accepts incremental action", guest.qn == 1 and guest.known == 2) and ok

    local guestState, stateGame = fakeSync("guest", -1, 1)
    stateGame.match.findMove = function() return 1 end
    guestState:onMessage({ t = "state", blob = "S 1 1 600 1 HOST\nM 49 41 0 600" })
    ok = check(log, "guest accepts host state", guestState.qn == 1 and guestState.known == 2) and ok
    guestState:onMessage({ t = "state", blob = "S 1 1 600 1 HOST\nM 49 41 0 600" })
    ok = check(log, "guest ignores repeated state", guestState.qn == 1) and ok

    local selfOnly = fakeSync("host", 1, -1)
    selfOnly.session.peer = 1
    selfOnly:onMessage({ t = "peer_input", peer = 1, blob = "2|M 49 41 0 600" })
    ok = check(log, "host ignores own input", selfOnly.qn == 0) and ok
    selfOnly:onMessage({ t = "peer_input", peer = 9, blob = "2|M 49 41 0 600" })
    ok = check(log, "host accepts any guest peer", selfOnly.qn == 1) and ok

    local beat, _, sent = fakeSync("host", 1, -1)
    ok = check(log, "heartbeat sends", beat:beat(Config.net.heartbeat)) and ok
    ok = check(log, "host heartbeat is state", sent.move == "S 1 1 600 1 HOST" and sent.input == nil) and ok
    ok = check(log, "heartbeat throttles", not beat:beat(Config.net.heartbeat + 0.1)) and ok

    local gbeat, _, gsent = fakeSync("guest", -1, 1)
    ok = check(log, "guest heartbeat is input", gbeat:beat(Config.net.heartbeat)
        and gsent.input == Config.net.heartbeatBlob and gsent.move == nil) and ok

    local untimed = fakeSync("host", 1, -1)
    ok = check(log, "reject flag when untimed", not untimed:apply("T -1", false)) and ok

    local abort = fakeSync("host", 1, -1)
    ok = check(log, "apply abort action", abort:apply("A -1", false)
        and abort.game.match.result and abort.game.match.result.reason == "AFK") and ok

    local guestAbort, guestAbortGame = fakeSync("guest", -1, 1)
    ok = check(log, "guest applies host abort", guestAbort:apply("A 1", false)
        and guestAbortGame.match.result.reason == "AFK") and ok

    local finished = fakeSync("host", 1, -1)
    finished.game.match.result = { winner = 1, reason = "RESIGNED" }
    ok = check(log, "abort cannot overwrite a result", not finished:apply("A -1", false)) and ok

    local echo = fakeSync("guest", -1, 1)
    echo.game.match.result = { winner = 0, reason = "AFK" }
    ok = check(log, "abort echo is idempotent", echo:apply("A 1", false)
        and echo.game.match.result.reason == "AFK") and ok

    local abortInput = fakeSync("host", 1, -1)
    abortInput:onMessage({ t = "peer_input", peer = 2, blob = "0|A -1" })
    ok = check(log, "host accepts abort input", abortInput.qn == 1) and ok

    local guestInput = fakeSync("guest", -1, 1)
    guestInput:onMessage({ t = "peer_input", peer = 1, blob = "2|A 1" })
    ok = check(log, "guest accepts abort input", guestInput.qn == 1
        and guestInput.known == 2) and ok

    local rematch, rematchGame = fakeSync("host", 1, -1)
    local requests = 0
    rematchGame.rematchRequested = function() requests = requests + 1 end
    rematch:onMessage({ t = "peer_input", blob = Config.net.rematchBlob })
    ok = check(log, "reject early rematch", requests == 0) and ok
    rematchGame.match.result = { winner = 1, reason = "RESIGNED" }
    rematch:onMessage({ t = "peer_input", blob = Config.net.rematchBlob })
    ok = check(log, "accept rematch after result", requests == 1) and ok

    local previous = Transition.state
    Transition.state = "out"
    ok = check(log, "transition guard", Manager.switch("game", {}) == false) and ok
    Transition.state = previous
    return ok
end

local function testCardValidation(log)
    local b = Board.fromFEN(Board.START_FEN)
    b.ply, b.side = 10, -1
    local match = { human = 1, board = b, timed = false, result = nil,
        findMove = function() return 1 end }
    local layer = {
        match = match,
        hand = { [1] = {}, [-1] = { { def = Defs.bySlug.shield } } },
        manaOf = { [1] = 0, [-1] = 1 },
        castThisTurn = { [1] = false, [-1] = false },
        ward = { [1] = 0, [-1] = 0 },
        double = {}, lastSpell = {},
    }
    function layer:ctxFor() return {} end
    local game = { match = match, spells = layer }
    local sync = Sync.new(game, nil, "host", { "S 7 1 600 -1 HOST" })

    local ok = true
    ok = check(log, "accept a legal card", sync:validRemote("C shield 49 - 600")) and ok
    ok = check(log, "reject an empty target", not sync:validRemote("C shield 1 - 600")) and ok
    layer.manaOf[-1] = 0
    ok = check(log, "reject a card without mana", not sync:validRemote("C shield 49 - 600")) and ok
    layer.manaOf[-1] = 1
    layer.castThisTurn[-1] = true
    ok = check(log, "reject a second spell", not sync:validRemote("C shield 49 - 600")) and ok
    layer.castThisTurn[-1] = false
    layer.hand[-1] = {}
    ok = check(log, "reject a card not in hand", not sync:validRemote("C shield 49 - 600")) and ok
    return ok
end

function T.run(log)
    log = log or print
    log("network tests")

    local ok = true
    ok = testParty(log) and ok
    ok = testRoomie(log) and ok
    ok = testOnline(log) and ok
    ok = testSendAll(log) and ok
    ok = testAfk(log) and ok
    ok = testSync(log) and ok
    ok = testCardValidation(log) and ok
    return ok
end

return T
