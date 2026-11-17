local Search = require("src.ai.search")

local L = {}

local RAMP = { 1.5, 1.3, 1.15, 1.0, 0.85 }

local function strength(difficulty, k)
    local ai = {}
    for key, v in pairs(Search.LEVELS[difficulty]) do ai[key] = v end
    ai.noise = ai.noise * RAMP[k]
    ai.blunder = math.min(0.6, ai.blunder * RAMP[k])
    return ai
end

local function unit(title, sub, difficulty, list)
    local levels = {}
    for k, e in ipairs(list) do
        levels[k] = {
            name = e[1],
            fen = e[2],
            difficulty = difficulty,
            ai = strength(difficulty, k),
            boss = k == #list,
            human = (k % 2 == 0 and k ~= #list) and -1 or 1,
        }
    end
    return { title = title, sub = sub, levels = levels }
end

L.units = {
    unit("UNIT 1", "FIRST SPELLS", 1, {
        { "PIP", "4k3/3ppp2/8/8/8/8/3PPP2/3QK3 w - - 0 5" },
        { "MOSS", "3qk3/3ppp2/8/8/8/8/2PPPP2/2N1K1N1 w - - 0 5" },
        { "WISP", "r3k3/ppp5/8/8/8/8/PPP5/R3KR2 w - - 0 5" },
        { "FERN", "2b1k1n1/3pppp1/8/8/8/8/3PPPP1/4K2R w - - 0 5" },
        { "WARDEN", "r3k2r/ppp2ppp/8/8/8/8/PPP2PPP/R3K2R w - - 0 5" },
    }),
    unit("UNIT 2", "ARCANE DUELS", 2, {
        { "EMBER", "rn2k1nr/ppp2ppp/8/8/8/8/PPP2PPP/RN2KBNR w - - 0 5" },
        { "FROST", "rnb1kbnr/ppp2ppp/8/8/8/8/PPP2PPP/RNB1KBNR w - - 0 5" },
        { "GALE", "r1bqk2r/pppp1ppp/8/8/8/8/PPPP1PPP/R1BQK2R w - - 0 5" },
        { "TIDE", "rnbqk1nr/pppp2pp/8/8/8/8/PPPP2PP/RNBQK1NR w - - 0 5" },
        { "ORACLE", "r1bqkb1r/pppppppp/8/8/8/8/PPPPPPPP/R1BQKB1R w - - 0 5" },
    }),
    unit("UNIT 3", "THE HIGH TOWER", 3, {
        { "RUNE", "r2qk2r/pppp2pp/2n5/8/8/2N5/PPPP2PP/R2QK2R w - - 0 5" },
        { "SHADE", "r1bqk1nr/pppp2pp/8/8/8/8/PPPP2PP/R1BQK1NR w - - 0 5" },
        { "HEX", "rnbqk2r/pppp1ppp/8/8/8/8/PPPP1PPP/RNBQK2R w - - 0 5" },
        { "VOID", "r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKB1R w - - 0 5" },
        { "ARCHMAGE", "rnbqkbnr/pppp2pp/8/8/8/8/PPPP2PP/RNBQKBNR w - - 0 5" },
    }),
}

L.flat = {}
for u, un in ipairs(L.units) do
    for k, lv in ipairs(un.levels) do
        lv.unit, lv.k = u, k
        L.flat[#L.flat + 1] = lv
        lv.index = #L.flat
    end
end

L.count = #L.flat

function L.progress()
    local App = require("src.app")
    return math.max(0, math.min(L.count, App.settings.campaign or 0))
end

function L.complete(index)
    local App = require("src.app")
    if index > L.progress() then
        App.settings.campaign = index
        App.save()
    end
end

return L
