local Save = {}

Save.FILE = "settings.lua"

Save.defaults = {
    master = 0.8,
    music = 0.6,
    sfx = 0.8,
    fullscreen = false,
    resolution = 2,
    anim = 2,
    difficulty = 2,
    spells = true,
    clock = 3,
    tutorial = true,
    nickname = "",
    campaign = 0,
}

Save.RESOLUTIONS = { { 1280, 720 }, { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 } }
Save.CLOCKS = { { "3 MIN", 180 }, { "5 MIN", 300 }, { "10 MIN", 600 }, { "15 MIN", 900 }, { "NONE", 0 } }
Save.ANIM = { "LOW", "NORMAL", "HIGH" }
Save.ANIM_SCALE = { 0.35, 1, 1.5 }

function Save.load()
    local s = {}
    for k, v in pairs(Save.defaults) do s[k] = v end
    local ok, chunk = false, nil
    if love.filesystem.getInfo(Save.FILE) then ok, chunk = pcall(love.filesystem.load, Save.FILE) end
    if ok and chunk then
        local ok2, data = pcall(chunk)
        if ok2 and type(data) == "table" then
            for k, v in pairs(data) do
                if Save.defaults[k] ~= nil and type(v) == type(Save.defaults[k]) then s[k] = v end
            end
        end
    end
    s.resolution = math.max(1, math.min(#Save.RESOLUTIONS, s.resolution))
    s.clock = math.max(1, math.min(#Save.CLOCKS, s.clock))
    s.anim = math.max(1, math.min(3, s.anim))
    s.difficulty = math.max(1, math.min(3, s.difficulty))
    return s
end

function Save.write(s)
    local lines = { "return {" }
    local keys = {}
    for k in pairs(Save.defaults) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = s[k]
        lines[#lines + 1] = string.format("  %s = %s,", k, type(v) == "number" and string.format("%.3f", v):gsub("%.?0+$", "")
            or type(v) == "string" and string.format("%q", v) or tostring(v))
    end
    lines[#lines + 1] = "}"
    pcall(love.filesystem.write, Save.FILE, table.concat(lines, "\n") .. "\n")
end

return Save
