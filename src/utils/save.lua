local Config = require("src.config")

local Save = {}

Save.FILE = Config.app.saveFile

Save.defaults = Config.settings.defaults
Save.RESOLUTIONS = Config.settings.resolutions
Save.CLOCKS = Config.settings.clocks
Save.ANIM = Config.settings.anim
Save.ANIM_SCALE = Config.settings.animScale

local function valid(k, v)
    if Save.defaults[k] == nil or type(v) ~= type(Save.defaults[k]) then return false end
    if type(v) == "number" then return math.abs(v) < math.huge end
    return true
end

local function whole(value, low, high)
    return math.max(low, math.min(high, math.floor(value)))
end

function Save.load()
    local s = {}
    for k, v in pairs(Save.defaults) do s[k] = v end
    local ok, chunk = false, nil
    if love.filesystem.getInfo(Save.FILE) then ok, chunk = pcall(love.filesystem.load, Save.FILE) end
    if ok and chunk then
        local ok2, data = pcall(chunk)
        if ok2 and type(data) == "table" then
            for k, v in pairs(data) do
                if valid(k, v) then s[k] = v end
            end
        end
    end
    for _, key in ipairs({ "master", "music", "sfx" }) do
        s[key] = math.max(0, math.min(1, s[key]))
    end
    s.resolution = whole(s.resolution, 1, #Save.RESOLUTIONS)
    s.clock = whole(s.clock, 1, #Save.CLOCKS)
    s.anim = whole(s.anim, 1, #Save.ANIM)
    s.difficulty = whole(s.difficulty, 1, #Config.ai.levels)
    s.campaign = math.max(0, math.floor(s.campaign))
    return s
end

function Save.write(s)
    local lines = { "return {" }
    local keys = {}
    for k in pairs(Save.defaults) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = s[k]
        local value = type(v) == "number" and string.format("%.3f", v):gsub("%.?0+$", "")
            or type(v) == "string" and string.format("%q", v) or tostring(v)
        lines[#lines + 1] = string.format("  %s = %s,", k, value)
    end
    lines[#lines + 1] = "}"
    local ok, wrote, err = pcall(love.filesystem.write, Save.FILE, table.concat(lines, "\n") .. "\n")
    if not ok then print("settings save failed: " .. tostring(wrote))
    elseif not wrote then print("settings save failed: " .. tostring(err)) end
    return ok and wrote
end

return Save
