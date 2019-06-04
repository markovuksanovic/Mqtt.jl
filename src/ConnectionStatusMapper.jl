module ConnectionStatusMapper

function process_connack_variable_header(::Val{UInt8(0x00)})
    return (true, "Connection Accepted")
end

function process_connack_variable_header(::Val{UInt8(0x01)})
    return (false, "Connection Refused, unacceptable protocol version")
end

function process_connack_variable_header(::Val{UInt8(0x02)})
    return (false, "Connection Refused, identifier rejected")
end

function process_connack_variable_header(::Val{UInt8(0x03)})
    return (false, "Connection Refused, Server unavailable")
end

function process_connack_variable_header(::Val{UInt8(0x04)})
    return (false, "Connection Refused, bad user name or password")
end

function process_connack_variable_header(::Val{UInt8(0x05)})
    return (false, "Connection Refused, not authorized")
end

function process_connack_variable_header(::Val)
    return (false, "Connection Refused, unknown")
end

end
