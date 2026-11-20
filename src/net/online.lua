local Config = require("src.config")
local Roomie = require("src.net.roomie")

local Online = {
    APP_KEY = Config.app.key,
    HOST = Config.roomie.host,
    PORT = Config.roomie.port,
    current = nil,
}

local Session = {}
Session.__index = Session

local clientHash

local function hash()
    if not clientHash then
        local t = {}
        for i = 1, 16 do
            t[i] = string.format("%02x", love.math.random(0, 255))
        end
        clientHash = table.concat(t)
    end
    return clientHash
end

local function randomCode()
    local chars = Config.net.codeChars
    local t = {}
    for i = 1, Config.net.codeLength do
        local n = love.math.random(#chars)
        t[i] = chars:sub(n, n)
    end
    return table.concat(t)
end

function Online.validCode(code)
    if type(code) ~= "string" then return false end
    if #code ~= Config.net.codeLength then return false end
    for i = 1, #code do
        if not Config.net.codeChars:find(code:sub(i, i), 1, true) then return false end
    end
    return true
end

function Online.roomCode(role, backend, code)
    code = code or ""
    if role == "guest" then
        if not Online.validCode(code) then return nil end
        return code
    end
    if role == "host" then
        if backend == "roomie" then return "" end
        if code == "" then return randomCode() end
    end
    return code
end

function Online.normalize(value)
    return (string.upper(tostring(value or "")):gsub("_", " "))
end

function Online.codeTaken(code)
    local text = Online.normalize(code)
    return text == "CODE TAKEN" or text == "ROOM CODE TAKEN"
end

function Online.roomMissing(code)
    return Online.normalize(code) == "ROOM NOT FOUND"
end

function Online.parseUrl(url)
    local scheme, rest = url:match("^(%a[%w+.-]*)://(.+)$")
    if not scheme then return nil, "INVALID RELAY URL" end

    local hostport, path = rest:match("^([^/]+)(/.*)$")
    if not hostport then
        hostport, path = rest, "/"
    end

    local host, port = hostport:match("^([^:]+):(%d+)$")
    host = host or hostport
    local ports = Config.relay.ports
    port = tonumber(port) or (scheme == "wss" and ports.secure or ports.plain)

    if path:sub(-1) ~= "/" then path = path .. "/" end
    return {
        scheme = scheme,
        host = host,
        port = port,
        path = path,
    }
end

function Online.url(web)
    local env = os.getenv(Config.relay.env)
    if env and env ~= "" then return env end
    local scheme = web and Config.relay.webScheme or Config.relay.nativeScheme
    return scheme .. "://" .. Config.relay.host .. Config.relay.path
end

local function withCode(url, code)
    if url:sub(-1) == "/" then return url .. code end
    return url .. "/" .. code
end

local function failed(message)
    local s = setmetatable({}, Session)
    s.state = "closed"
    s.error = message
    s.role = "guest"
    s.code = ""
    Online.current = s
    return s
end

function Online.setServer(server)
    if not server or server == "" then return end
    local host, port = server:match("^([^:]+):(%d+)$")
    Online.HOST = host or server
    Online.PORT = tonumber(port) or Online.PORT
end

function Online.backend(role, forced)
    if forced then return forced end
    local web = love.system and love.system.getOS() == "Web"
    if web or role == "queue" then return "party" end
    return Config.net.backend == "roomie" and "roomie" or "party"
end

function Online.open(role, code, backend, opts)
    Online.close()

    local web = love.system.getOS() == "Web"
    local useRoomie = Online.backend(role, backend) == "roomie"
    local session = setmetatable({}, Session)
    session.role = role
    session.code = code or ""
    session.rating = opts and opts.rating
    session.state = "connecting"
    session.codec = useRoomie and Roomie or require("src.net.party")
    session.code = Online.roomCode(role, useRoomie and "roomie" or "party", session.code)
    if session.code == nil then
        return failed("INVALID ROOM CODE")
    end

    if useRoomie then
        -- server code
        session.inbox = love.thread.newChannel()
        session.outbox = love.thread.newChannel()
        session.thread = love.thread.newThread(Config.net.threads.roomie)
        session.thread:start(session.inbox, session.outbox, Online.HOST, Online.PORT)
        Online.current = session
        return session
    end

    local url = Online.url(web)
    local parsed, reason = Online.parseUrl(url)
    if not parsed then return failed(reason) end

    if web then
        local target = withCode(url, session.code)
        session.inbox, session.outbox, session.thread = require("src.net.webnet").open(target, true)
        Online.current = session
        return session
    end

    if parsed.scheme == "wss" then
        return failed("SECURE RELAY NEEDS THE BROWSER BUILD")
    end

    if parsed.scheme ~= "ws" then
        return failed("RELAY MUST USE WS")
    end

    session.inbox = love.thread.newChannel()
    session.outbox = love.thread.newChannel()
    session.thread = love.thread.newThread(Config.net.threads.party)
    session.thread:start(session.inbox, session.outbox, parsed.host, parsed.port, parsed.path .. session.code)
    Online.current = session
    return session
end

function Online.close()
    local session = Online.current
    if session then session:close() end
    Online.current = nil
end

function Session:send(payload)
    if self.state == "closed" or not self.outbox then return end
    self.outbox:push(payload)
end

function Session:sendMove(blob)
    self:send(self.codec.move(blob))
end

function Session:sendInput(blob)
    self:send(self.codec.input(blob))
end

function Session:close()
    if self.state ~= "closed" then
        if self.outbox then
            self.outbox:push(self.codec.leave())
            self.outbox:push(false)
        end
        self.state = "closed"
    end
    if Online.current == self then Online.current = nil end
end

function Session:poll()
    if self.error then
        local message = self.error
        self.error = nil
        self.state = "closed"
        return { t = "closed", msg = message }
    end

    if not self.inbox then return nil end
    if self.state == "closed" and self.inbox:getCount() == 0 then return nil end

    local threadError = self.thread and self.thread:getError()
    if threadError and self.state ~= "closed" then
        print("net thread error: " .. threadError)
        self.state = "closed"
        return { t = "closed", msg = "NETWORK ERROR" }
    end

    while true do
        local value = self.inbox:pop()
        if value == nil then return nil end

        if type(value) == "table" then
            if value.ev == "open" then
                self.state = "open"
                self.outbox:push(self.codec.hello(Online.APP_KEY, self.code, hash(), nil, self.role, self.rating))
            elseif value.ev == "closed" then
                self.state = "closed"
                return { t = "closed", msg = value.msg }
            end
        else
            local message, reason = self.codec.decode(value)
            local fromPeer = message and (message.t == "peer_input" or message.t == "state" or message.t == "peer_left")
            if fromPeer then self.heard = love.timer.getTime() end

            if message and message.t == "peer_input" and message.blob == Config.net.heartbeatBlob then
                message = nil
            elseif message then
                if message.t == "joined" then
                    if not Online.validCode(message.code) then
                        self:close()
                        return { t = "closed", msg = "INVALID ROOM CODE" }
                    end
                    self.code = message.code
                    self.peer = message.peer
                    self.hostPeer = message.host
                end
                if message.t ~= "pong" and message.t ~= "move_ok" then
                    return message
                end
            elseif reason then
                print("relay decode error: " .. tostring(reason))
            end
        end
    end
end

Online.setServer(os.getenv(Config.roomie.env))

return Online
