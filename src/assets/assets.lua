local Config = require("src.config")
local NineSlice = require("src.ui.nineslice")
local Pal = require("src.utils.palette")
local Defs = require("src.cards.defs")

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

local SLICES = Config.assets.slices

A.CARD_SLUGS = {}
for _, def in ipairs(Defs.list) do
    A.CARD_SLUGS[#A.CARD_SLUGS + 1] = def.slug
end

local PIECES = Config.assets.pieceNames
local ASSETS = Config.assets
local EXT = ASSETS.imageExt
local UI_DIR, PIECE_DIR, CARD_DIR = ASSETS.ui, ASSETS.pieces, ASSETS.cards
local SIZES = ASSETS.imageSizes

A.FONT_SIZES = Config.ui.fontSizes

function A.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    A.ui = {}
    for name, m in pairs(SLICES) do
        local img = A.image(UI_DIR .. name .. EXT, SIZES.ui, SIZES.ui)
        A.ui[name] = NineSlice.new(img, m[1], m[2], m[3], m[4])
    end
    A.bg = A.image(UI_DIR .. "bg_texture" .. EXT, SIZES.bg, SIZES.bg)
    A.bg:setWrap("repeat", "repeat")

    A.piece = { [1] = {}, [-1] = {} }
    for t, name in ipairs(PIECES) do
        local white = PIECE_DIR .. "white_" .. name .. EXT
        local black = PIECE_DIR .. "black_" .. name .. EXT
        A.piece[1][t] = A.image(white, SIZES.piece, SIZES.piece)
        A.piece[-1][t] = A.image(black, SIZES.piece, SIZES.piece)
    end

    A.card = {}
    for _, slug in ipairs(A.CARD_SLUGS) do
        A.card[slug] = A.image(CARD_DIR .. slug .. EXT, SIZES.cardW, SIZES.cardH)
    end

    A.font = {}
    for k, size in pairs(A.FONT_SIZES) do
        local ok, f = pcall(love.graphics.newFont, Config.assets.font, size, "mono", 1)
        if not ok then f = love.graphics.newFont(size) end
        f:setFilter("nearest", "nearest")
        A.font[k] = f
    end

    local px = love.image.newImageData(1, 1)
    px:setPixel(0, 0, 1, 1, 1, 1)
    A.pixel = love.graphics.newImage(px)
    A.pixel:setFilter("nearest", "nearest")
end

return A
