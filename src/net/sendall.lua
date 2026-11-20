local SendAll = {}

-- Partial writes.
-- Byte count.
function SendAll.run(send, data)
    local total = #data
    local sent = 0
    while sent < total do
        local n, err = send(data, sent + 1)
        if not n then return nil, err or "send failed" end
        if n <= 0 then return nil, "send failed" end
        sent = sent + n
    end
    return sent
end

return SendAll
