local Transition = require("src.animations.transition")

local M = { states = {}, current = nil, name = nil }

function M.register(name, state) M.states[name] = state end

function M.set(name, params)
    if M.current and M.current.leave then M.current.leave(M.current) end
    M.name = name
    M.current = M.states[name]
    if M.current.enter then M.current.enter(M.current, params or {}) end
end

function M.switch(name, params)
    if Transition.busy() then return false end
    Transition.start(function() M.set(name, params) end)
    return true
end

function M.call(fn, ...)
    local s = M.current
    if s and s[fn] and not (Transition.busy() and fn ~= "update" and fn ~= "draw") then
        return s[fn](s, ...)
    end
end

return M
