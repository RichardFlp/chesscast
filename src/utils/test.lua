local Config = require("src.config")
local Board = require("src.chess.board")
local Search = require("src.ai.search")
local Save = require("src.utils.save")
local U = require("src.utils.util")
local bit = require("src.utils.bit")
local Spring = require("src.utils.spring")
local E = require("src.utils.easing")
local Text = require("src.ui.text")
local Online = require("src.net.online")
local App = require("src.app")
local Multiplayer = require("src.states.multiplayer")
local Matchmaking = require("src.states.matchmaking")
local Lobby = require("src.states.lobby")

local T = {}

function T.run(log)
    local ok = true
    local function check(name, cond, extra)
        log(string.format("  %-44s %s%s", name, cond and "ok" or "FAIL", extra and ("  " .. extra) or ""))
        if not cond then ok = false end
    end

    log("configuration tests")
    check("save defaults come from config", Save.defaults == Config.settings.defaults)
    check("save resolutions come from config", Save.RESOLUTIONS == Config.settings.resolutions)
    check("save clocks come from config", Save.CLOCKS == Config.settings.clocks)

    local oldSave = Save.FILE
    Save.FILE = "settings.test.lua"
    local test = {}
    for k, v in pairs(Save.defaults) do test[k] = v end
    test.master, test.music, test.sfx = 2, -1, 0.5
    test.resolution, test.anim, test.difficulty, test.clock = 99, 0, 0, 0
    test.fullscreen, test.spells, test.tutorial = true, false, false
    test.nickname, test.campaign = "tester", 3
    local wrote = Save.write(test)
    local loaded = Save.load()
    check("save writes and clamps values", wrote and loaded.master == 1 and loaded.music == 0
        and loaded.sfx == 0.5 and loaded.resolution == #Save.RESOLUTIONS
        and loaded.anim == 1 and loaded.difficulty == 1 and loaded.clock == 1)
    check("save keeps valid settings", loaded.fullscreen and not loaded.spells
        and not loaded.tutorial and loaded.nickname == "tester" and loaded.campaign == 3)
    love.filesystem.write(Save.FILE, "return { master = 0/0, music = 1/0, resolution = 2 }\n")
    local corrupt = Save.load()
    check("save rejects bad numbers", corrupt.master == Save.defaults.master
        and corrupt.music == Save.defaults.music and corrupt.resolution == 2)
    love.filesystem.write(Save.FILE,
        "return { resolution = 2.5, clock = 3.5, anim = 2.5, difficulty = 2.5, campaign = 2.5 }\n")
    local fractional = Save.load()
    check("save floors fractional indexes", fractional.resolution == 2 and fractional.clock == 3
        and fractional.anim == 2 and fractional.difficulty == 2 and fractional.campaign == 2)
    love.filesystem.remove(Save.FILE)
    Save.FILE = oldSave

    check("screen resolution is a selectable size", Save.RESOLUTIONS[3][1] == Config.screen.width
        and Save.RESOLUTIONS[3][2] == Config.screen.height)
    check("piece values come from config", Board.VALUE == Config.chess.values)
    local empty = Board.fromFEN("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    empty.lastStand[-1] = empty.ply + 4
    check("empty squares are never protected", not empty:isProtected(Board.sq(3, 6)))
    check("search levels come from config", Search.LEVELS == Config.ai.levels)
    check("search mate score comes from config", Search.MATE == Config.ai.mate)
    check("text line height is adaptive", Text.height(1) == Config.ui.lineHeight)
    check("ranked rating config is coherent", Config.net.ratingMin <= Config.net.ratingMax
        and #tostring(Config.net.ratingMax) <= Config.net.ratingDigits)
    check("footer height is positive", Config.ui.footer > 0)
    check("splash keeps the contributor credit", Config.app.contributor == "HURANTH")
    local capturesLayout = false
    for i = 1, 16 do
        local _, value = debug.getupvalue(Multiplayer.draw, i)
        if value == Config.ui.multiplayer then capturesLayout = true; break end
    end
    check("multiplayer draw captures its layout", capturesLayout)
    Matchmaking:enter()
    local casual, ranked = Matchmaking.items[1], Matchmaking.items[2]
    check("matchmaking offers casual", casual and casual.label == "CASUAL" and not casual.disabled)
    check("matchmaking offers ranked", ranked and ranked.label == "RANKED" and not ranked.disabled)
    Matchmaking:enter({ ranked = true })
    check("ranked offers time controls", #Matchmaking.items == #Config.net.casualModes + 1)
    Matchmaking:enter({ casual = true })
    local modes = Config.net.casualModes
    local seen, modeLabels = {}, true
    for i, mode in ipairs(modes) do
        if seen[mode.id] or mode.clock <= 0 or Matchmaking.items[i].label ~= mode.name then modeLabels = false end
        seen[mode.id] = true
    end
    check("casual offers time controls", modeLabels and #Matchmaking.items == #modes + 1)
    local settings = App.settings
    App.settings = { nickname = "TEST" }
    Lobby.hostWait = 5
    Lobby.copyBtn = { disabled = false }
    Lobby.joinBtn = { disabled = false }
    Lobby:enter({ role = "match", mode = "blitz" })
    check("lobby clears stale host wait", Lobby.hostWait == nil)
    check("lobby clears stale room buttons", Lobby.copyBtn == nil and Lobby.joinBtn == nil)
    Lobby.hostWait = 5
    Lobby:fail("TEST")
    check("lobby failure clears host wait", Lobby.hostWait == nil)
    Lobby:enter({ role = "match", mode = "blitz", ranked = true })
    check("ranked lobby asks for Elo", Lobby.ranked and Lobby.phase == "name" and Lobby.elo == "")
    Lobby.name = "TEST"
    Lobby.elo = "1200"
    Lobby:updateOk()
    check("ranked lobby accepts ELO", not Lobby.okBtn.disabled)
    Lobby.elo = ""
    Lobby.field = "elo"
    Lobby:textinput("a1b2c3")
    check("ranked ELO is numbers only", Lobby.elo == "123")
    Lobby.elo = "12a"
    Lobby:updateOk()
    check("ranked lobby rejects injected letters", Lobby.okBtn.disabled)
    Lobby.elo = ""
    Lobby:updateOk()
    check("ranked lobby requires ELO", Lobby.okBtn.disabled)
    Lobby.elo = "0"
    Lobby:updateOk()
    check("ranked lobby accepts zero", not Lobby.okBtn.disabled)
    Lobby.elo = tostring(Config.net.ratingMax + 1)
    Lobby:updateOk()
    check("ranked lobby rejects five digits", Lobby.okBtn.disabled)
    Lobby.role, Lobby.rating = "host", 1200
    Lobby:onMessage({ t = "peer_input", blob = "0|N RIVAL 1300" })
    check("ranked peer Elo is exchanged", Lobby.peerRating == 1300)
    local realOpen = Online.open
    Online.open = function() return {} end
    Lobby:enter({ role = "match", mode = "bullet", ranked = true })
    Lobby.rating = 1200
    Lobby:onMessage({ t = "matched", role = "host", code = "ABC234" })
    Online.open = realOpen
    check("ranked match keeps own Elo", Lobby.rating == 1200)

    Lobby:enter({ role = "match", mode = "bullet", ranked = true })
    Lobby.opponentRating = 1200
    check("ranked handshake falls back to match rating", Lobby:rivalRating() == 1200)

    -- Match-found must stay lit while a guest retries a room the host has not
    -- opened yet. The retry deliberately clears session for half a second.
    Lobby:enter({ role = "match", mode = "blitz" })
    Lobby.role, Lobby.status, Lobby.session = "guest", "MATCH FOUND...", nil
    local found = Lobby:statusLabel()
    check("match status survives room retry", found and found:find("MATCH FOUND", 1, true) ~= nil)
    Lobby:setPhase("wait")
    Lobby.name = "TEST"
    Lobby.session = { state = "open", sendInput = function() end }
    Lobby:onMessage({ t = "joined", code = "ABC234" })
    local waiting = Lobby:statusLabel()
    check("guest waits without blank status", waiting and waiting:find("WAITING FOR HOST", 1, true) ~= nil)
    Lobby.role, Lobby.copyBtn = "host", { disabled = true }
    Lobby:onMessage({ t = "joined", code = "ABC234" })
    local hostWaiting = Lobby:statusLabel()
    check("host waits without blank status", hostWaiting and hostWaiting:find("WAITING FOR OPPONENT", 1, true) ~= nil)
    Lobby:beginRetry("guest")
    check("retry status stays visible", Lobby:statusLabel() ~= nil)
    Lobby.status = ""
    check("cleared status is hidden", Lobby:statusLabel() == nil)

    App.settings = settings
    check("card limits are coherent", Config.ui.card.startHand <= Config.ui.card.maxHand)
    check("background focus follows the screen", Config.ui.background.focusX == Config.screen.width / 2)
    check("tutorial layout is defined", Config.ui.tutorial.tip.w > 0 and Config.ui.tutorial.box.right[2] > 0)
    check("tutorial buttons are configured", Config.ui.tutorial.buttons.width > 0
        and Config.ui.tutorial.buttons.height > 0 and Config.ui.tutorial.tipLife > 0)
    check("game overlay layout is defined", Config.ui.game.result.w > 0 and Config.ui.game.pause.w > 0)
    check("game toast timings are configured", Config.ui.game.toast.max > 0
        and Config.ui.game.toast.life > 0 and Config.ui.game.confetti.seconds > 0)
    check("card animation layout is configured", Config.ui.card.enterX > 0
        and Config.ui.card.castScale > 1 and Config.ui.card.snapshotDepth > 0)
    check("campaign layout is configured", Config.ui.campaign.footer.height > 0
        and Config.ui.campaign.info.w > 0 and Config.ui.campaign.header.w > 0)
    check("history layout is configured", Config.ui.history.headY > 0
        and Config.ui.history.scrollBarW > 0)
    check("board effect pools are configured", Config.ui.board.particles > 0 and Config.ui.board.rings > 0)

    local secure = Online.parseUrl("wss://relay.example.com/parties/main/")
    local plain = Online.parseUrl("ws://relay.example.com:9000/parties/main/")
    check("wss uses the configured secure port", secure and secure.port == Config.relay.ports.secure)
    check("ws uses the configured plain port", plain and plain.port == 9000)
    check("ws defaults to the configured plain port", Online.parseUrl("ws://relay.example.com").port
        == Config.relay.ports.plain)
    check("room codes match the configured alphabet",
        Online.validCode(string.rep(Config.net.codeChars:sub(1, 1), Config.net.codeLength)))
    check("short room codes are rejected", not Online.validCode(string.rep("A", Config.net.codeLength - 1)))
    check("roomie hosts defer code creation", Online.roomCode("host", "roomie", "ABCDEF") == "")
    check("party hosts receive a code", Online.roomCode("host", "party", "") ~= nil)
    check("guests keep a valid code", Online.roomCode("guest", "party", "ABCDEF") == "ABCDEF")
    check("the test list includes this module", Config.tests[#Config.tests] == "src.utils.test")

    log("utility boundaries")
    check("bit band", bit.band(255, 15) == 15)
    check("bit shifts", bit.rshift(256, 4) == 16 and bit.lshift(3, 5) == 96)
    check("clamp edges", U.clamp(-1, 0, 10) == 0 and U.clamp(11, 0, 10) == 10)
    check("lerp", U.lerp(10, 20, 0.25) == 12.5)
    check("round halves", U.round(2.5) == 3 and U.round(-2.5) == -2)
    check("sign", U.sign(-3) == -1 and U.sign(0) == 0 and U.sign(9) == 1)
    check("rectangle edges", U.inRect(0, 0, 0, 0, 10, 10)
        and not U.inRect(10, 0, 0, 0, 10, 10))
    check("clock formatting", U.formatClock(-2) == "0:00.0" and U.formatClock(65) == "1:05")
    local spring = Spring.new(0, 200, 20)
    spring:snap(1)
    check("spring snap settles", spring:settled())
    check("easing endpoints", E.outCubic(0) == 0 and E.outCubic(1) == 1
        and E.inOutCubic(0.5) == 0.5)

    return ok
end

return T
