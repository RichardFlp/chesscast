local L = {}

local function unit(title, sub, difficulty, names)
    local levels = {}
    for k, name in ipairs(names) do
        levels[k] = {
            name = name,
            difficulty = difficulty,
            boss = k == #names,
            human = (k % 2 == 0 and k ~= #names) and -1 or 1,
        }
    end
    return { title = title, sub = sub, levels = levels }
end

L.units = {
    unit("UNIT 1", "FIRST SPELLS", 1, { "PIP", "MOSS", "WISP", "FERN", "WARDEN" }),
    unit("UNIT 2", "ARCANE DUELS", 2, { "EMBER", "FROST", "GALE", "TIDE", "ORACLE" }),
    unit("UNIT 3", "THE HIGH TOWER", 3, { "RUNE", "SHADE", "HEX", "VOID", "ARCHMAGE" }),
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
