local WebNet = {}

local floor = math.floor
local TAG = "@@CPNET "
local MAX_FRAME = 64 * 1024

local function hex(s)
    return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
local function unhex(s)
    return (s:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end
local function le4(n)
    return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local Queue = {}
Queue.__index = Queue
local function queue() return setmetatable({ items = {}, head = 1, tail = 0 }, Queue) end
function Queue:push(v) self.tail = self.tail + 1; self.items[self.tail] = v end
function Queue:getCount() return self.tail - self.head + 1 end
function Queue:pop()
    if self.head > self.tail then return nil end
    local v = self.items[self.head]
    self.items[self.head] = nil
    self.head = self.head + 1
    return v
end

local counter = 0

function WebNet.open(url, raw)
    counter = counter + 1

    local id = string.format("%d%03d%d", os.time(), floor(love.math.random() * 1000), counter)

    love.filesystem.write("net_ready.txt", "")
    local link = { id = id, seq = 0, buf = "", done = false }
    local inbox, outbox = queue(), queue()

    local function finish(msg)
        if link.done then return end
        link.done = true
        inbox:push({ ev = "closed", msg = msg })
    end

    local function pump()
        while true do
            local name = "net_" .. id .. "_" .. (link.seq + 1) .. ".txt"
            if not love.filesystem.getInfo(name) then break end
            local line = love.filesystem.read(name) or ""
            love.filesystem.remove(name)
            link.seq = link.seq + 1
            local kind, rest = line:match("^(%S+)%s?(.*)$")
            if kind == "open" then
                inbox:push({ ev = "open" })
            elseif kind == "data" and not link.done and raw then
                inbox:push(unhex(rest))
            elseif kind == "data" and not link.done then
                link.buf = link.buf .. unhex(rest)
                while #link.buf >= 4 do
                    local b1, b2, b3, b4 = link.buf:byte(1, 4)
                    local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
                    if n > MAX_FRAME then
                        print(TAG .. "close " .. id)
                        finish("BAD FRAME FROM SERVER")
                        break
                    end
                    if #link.buf < 4 + n then break end
                    inbox:push(link.buf:sub(5, 4 + n))
                    link.buf = link.buf:sub(5 + n)
                end
            elseif kind == "closed" then
                finish(rest ~= "" and rest or "CONNECTION LOST")
            end
        end
    end

    local rawPop = inbox.pop
    function inbox.pop(self) pump(); return rawPop(self) end
    local rawCount = inbox.getCount
    function inbox.getCount(self) pump(); return rawCount(self) end
    function outbox.push(_, payload)
        if payload == false then
            print(TAG .. "close " .. id)
            link.done = true
        elseif not link.done then
            print(TAG .. "send " .. id .. " " .. hex(raw and payload or (le4(#payload) .. payload)))
        end
    end

    print(TAG .. "open " .. id .. " " .. love.filesystem.getSaveDirectory() .. " " .. url .. (raw and " text" or ""))
    return inbox, outbox, { getError = function() return nil end }
end

function WebNet.copy(text) print(TAG .. "copy 0 " .. hex(text)) end

function WebNet.takePaste()
    if not love.filesystem.getInfo("net_paste.txt") then return nil end
    local t = love.filesystem.read("net_paste.txt")
    love.filesystem.remove("net_paste.txt")
    return t and unhex(t) or nil
end

function WebNet.init()
    love.filesystem.write("net_ready.txt", "")
    print(TAG .. "init 0 " .. love.filesystem.getSaveDirectory())
end

return WebNet
