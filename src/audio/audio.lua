
local Audio = {}
Audio.enabled = love.audio ~= nil
Audio.volume = { master = 0.8, music = 0.6, sfx = 0.8 }

local CHANNEL = {
    ui_hover = "ui", ui_click = "ui", ui_back = "ui", tick = "ui",
    move = "move", capture = "capture", explode = "capture",
    card_hover = "card_hover", card_draw = "card_draw", card_select = "card_hover",
    spell = "spell", impact = "spell", freeze = "spell",
    check = "check", victory = "check", defeat = "check",
}
local GAIN = { ui = 0.7, move = 0.9, capture = 0.9, card_hover = 0.5, card_draw = 0.7, spell = 0.9, check = 0.8 }

local sources = {}
local music = {}
local current
local lastPlay = {}

local function loadFile(name, kind)
    for _, ext in ipairs({ ".ogg", ".wav", ".mp3" }) do
        local path = "assets/audio/" .. name .. ext
        if love.filesystem.getInfo(path) then
            local ok, src = pcall(love.audio.newSource, path, kind)
            if ok then return src end
        end
    end
    return nil
end

function Audio.load()
    if not Audio.enabled then return end
    for name in pairs(CHANNEL) do
        local src = loadFile(name, "static")
        if src then
            sources[name] = { src }
            for _ = 2, 4 do sources[name][#sources[name] + 1] = src:clone() end
        end
    end
    local song = loadFile("music_menu", "stream")
    if song then
        song:setLooping(true)
        music.music_menu, music.music_game = song, song
    end
end

function Audio.setVolumes(master, mus, sfx)
    Audio.volume.master, Audio.volume.music, Audio.volume.sfx = master, mus, sfx
    if current and music[current] then
        music[current]:setVolume(master * mus * 0.55)
    end
end

function Audio.play(name, pitch, vol)
    local list = sources[name]
    if not list then return end
    local now = love.timer.getTime()
    if lastPlay[name] and now - lastPlay[name] < 0.025 then return end
    lastPlay[name] = now
    local v = Audio.volume
    local gain = (GAIN[CHANNEL[name] or "ui"] or 1) * (vol or 1) * v.master * v.sfx
    if gain <= 0 then return end
    for _, s in ipairs(list) do
        if not s:isPlaying() then
            pcall(function()
                s:setVolume(gain)
                s:setPitch(pitch or 1)
                s:play()
            end)
            return
        end
    end
    pcall(function()
        list[1]:stop(); list[1]:setVolume(gain); list[1]:setPitch(pitch or 1); list[1]:play()
    end)
end

function Audio.music(name)
    if current == name then return end
    local m = name and music[name]
    if m and current and music[current] == m then current = name; return end
    if current and music[current] then pcall(function() music[current]:stop() end) end
    current = name
    if m then
        pcall(function()
            m:setVolume(Audio.volume.master * Audio.volume.music * 0.55)
            m:play()
        end)
    end
end

return Audio
