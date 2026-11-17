local NineSlice = require("src.ui.nineslice")
local Pal = require("src.utils.palette")

local A = {}

local function placeholder(w, h)
    local d = love.image.newImageData(w, h)
    d:mapPixel(function(x, y)
        local c = ((math.floor(x / 4) + math.floor(y / 4)) % 2 == 0) and Pal.C or Pal.I
        return c[1], c[2], c[3], 1
    end)
    return love.graphics.newImage(d)
end

function A.image(path, w, h)
    local ok, img = false, nil
    if love.filesystem.getInfo(path) then ok, img = pcall(love.graphics.newImage, path) end
    if not ok then
        print("missing asset: " .. path)
        img = placeholder(w or 16, h or 16)
    end
    img:setFilter("nearest", "nearest")
    return img
end

local SLICES = {
    panel_large = { 12, 12, 12, 12 },
    panel_small = { 8, 8, 8, 8 },
    button_primary = { 4, 4, 4, 5 },
    button_secondary = { 4, 4, 4, 5 },
    button_disabled = { 4, 4, 4, 5 },
    slot = { 6, 6, 6, 6 },
    slot_selected = { 6, 6, 6, 6 },
    tooltip = { 6, 6, 6, 6 },
    dialogue = { 12, 12, 12, 12 },
    divider_h = { 8, 0, 8, 0 },
    divider_v = { 0, 8, 0, 8 },
}

A.CARD_SLUGS = {
    "teleport", "swap", "magnetic_pull", "reverse_gravity", "rooks_gambit", "double_strike",
    "shield", "dispel", "sanctuary", "fog_of_war", "checkmates_grace", "counterspell",
    "sacrifice", "resurrection", "berserk", "blood_pact", "rebirth", "last_stand",
    "time_rewind", "freeze", "haste", "en_passant", "temporal_echo", "meteor",
}

local PIECES = { "pawn", "knight", "bishop", "rook", "queen", "king" }

A.FONT_SIZES = { [1] = 10, [2] = 20, [3] = 31, [4] = 41, [6] = 61, [8] = 82 }

function A.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    A.ui = {}
    for name, m in pairs(SLICES) do
        local img = A.image("assets/ui/" .. name .. ".png", 24, 24)
        A.ui[name] = NineSlice.new(img, m[1], m[2], m[3], m[4])
    end
    A.bg = A.image("assets/ui/bg_texture.png", 16, 16)
    A.bg:setWrap("repeat", "repeat")

    A.piece = { [1] = {}, [-1] = {} }
    for t, name in ipairs(PIECES) do
        A.piece[1][t] = A.image("assets/pieces/white_" .. name .. ".png", 32, 32)
        A.piece[-1][t] = A.image("assets/pieces/black_" .. name .. ".png", 32, 32)
    end

    A.card = {}
    for _, slug in ipairs(A.CARD_SLUGS) do
        A.card[slug] = A.image("assets/cards/" .. slug .. ".png", 64, 96)
    end

    A.font = {}
    for k, size in pairs(A.FONT_SIZES) do
        local ok, f = pcall(love.graphics.newFont, "assets/fonts/PixelEmulator-xq08.ttf", size, "mono", 1)
        if not ok then f = love.graphics.newFont(size) end
        f:setFilter("nearest", "nearest")
        A.font[k] = f
    end

    local px = love.image.newImageData(1, 1)
    px:setPixel(0, 0, 1, 1, 1, 1)
    A.pixel = love.graphics.newImage(px)
end

return A
