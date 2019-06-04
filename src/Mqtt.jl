module Mqtt

include("./ConnectionStatusMapper.jl")
using .ConnectionStatusMapper
const csm = ConnectionStatusMapper

abstract type Packet end
struct Connect <: Packet end
struct ConnAck <: Packet end
struct Publish <: Packet end
struct PubAck <: Packet end
struct PubRec <: Packet end
struct PubRel <: Packet end
struct PubComp <: Packet end
struct Subscribe <: Packet end
struct SubAck <: Packet end
struct Unsubscribe <: Packet end
struct UnsubAck <: Packet end
struct PingReq <: Packet end
struct PingResp <: Packet end
struct Disconnect <: Packet end
struct UndefinedPacket <: Packet end

struct Client
    connect_handler::Function
    subscribe_handler::Function
    publish_handler::Function
    stream::IO
end

function connect(client::Client, id::String)
    packet = generate_connect_packet(id)
    send_packet(client, packet)
    receive_packet(client)
end

function subscribe(client::Client, topic::String)
    packet = generate_subscribe_packet(topic)
    send_packet(client, packet)
end

function unsubscribe(client::Client, topic::String)
    packet = generate_unsubscribe_packet(topic)
    send_packet(client, packet)
end

function disconnect(client::Client)
    send_packet(client, generate_disconnect_packet())
end

function ping(client::Client)
    send_packet(client, generate_ping_packet())
end

function send_packet(client, data)
    write(client.stream, data)
end

function receive_packet(client::Client)
    packet_type_byte = read(client.stream, UInt8)
    remaining_len = read_remaining_len!(client.stream, 1)
    rest = read(client.stream, remaining_len)
    process_packet(client, get_packet_type(packet_type_byte), rest)
end

function read_remaining_len!(stream::IO, iteration)
    if iteration > 4
        error("Invalid variable length field.")
    end
    byte = read(stream, UInt8)
    value = (byte & 0x7f) * (128 ^ (iteration - 1))
    if byte & 0x80 == 0x80
        value = value + read_remaining_len!(stream, iteration + 1)
    else
        value
    end
end

function get_packet_type(b::UInt8)::Packet
    b = b & 0xf0 # We look at only MSB
    if b == 0x10
        return Connect()
    elseif b == 0x20
        return ConnAck()
    elseif b == 0x30
        return Publish()
    elseif b == 0x40
        return PubAck()
    elseif b == 0x50
        return PubRec()
    elseif b == 0x60
        return PubRel()
    elseif b == 0x70
        return PubComp()
    elseif b == 0x80
        return Subscribe()
    elseif b == 0x90
        return SubAck()
    elseif b == 0xa0
        return Unsubscribe()
    elseif b == 0xb0
        return UnsubAck()
    elseif b == 0xc0
        return PingReq()
    elseif b == 0xd0
        return PingResp()
    elseif b == 0xe0
        return Disconnect()
    else
        return UndefinedPacket()
    end
end

function process_packet(client, packet::Connect, payload::Array{UInt8, 1})
    false
end

function process_packet(client, packet::ConnAck, payload::Array{UInt8, 1})
    if payload[1] == UInt8(0x01)
        error("Sessions are not supported")
    elseif payload[1] != UInt8(0x00)
        error("CONNACK packet was malformed")
    end
    return csm.process_connack_variable_header(Val(payload[2]))
end

function process_packet(client, packet::SubAck, payload::Array{UInt8, 1})
    packet_id = [payload[1], payload[2]]
    return map(x -> x in [0x00, 0x01, 0x02] ? true : false, payload[3:end])
end

function process_packet(client, packet::Publish, payload::Array{UInt8, 1})
    client.publish_handler(payload)
end

function process_packet(client, packet::PingResp, payload::Array{UInt8, 1})
    # Do nothing
end

function process_packet(client, packet::UnsubAck, payload::Array{UInt8, 1})
    # Do nothing
end

function connect_generate_var_header()
    # binary sequence of two bytes that indicate length and
    # 4 bytes that represent MQTT string
    proto_name = UInt8[0x00, 0x04, 0x4d, 0x51, 0x54, 0x54]
    proto_level = UInt8[ 0x04 ]
    connect_flags = [ 0x02 ]
    keep_alive_interval = [ 0x00, 0x3c ] # 60 seconds (msb, lsb)
    return vcat(proto_name, proto_level, connect_flags, keep_alive_interval)
end

function connect_generate_payload(client_id::String)
    client_id_array = collect(UInt8, client_id)
    l = length(client_id_array)
    len_msb = UInt8((l) >> 8)
    len_lsb = UInt8(l & 0x00ff)
    return vcat([len_msb, len_lsb], client_id_array)
end

function subscribe_generate_var_header(pid::UInt16)
    msb = UInt8((pid & 0xff00) >> 8)
    lsb = UInt8(pid & 0x00ff)
    return [ msb, lsb ]
end

function subscribe_generate_var_header(pid::UInt8)
    return [ 0x00, pid ]
end

function add_topic_to_payload(topic::String; qos::Union{UInt8, Nothing}=nothing)
    topic_array = collect(UInt8, topic)
    l = length(topic_array)
    len_msb = UInt8((l) >> 8)
    len_lsb = UInt8(l & 0x00ff)
    return qos == nothing ? vcat([len_msb, len_lsb], topic_array) : vcat([len_msb, len_lsb], topic_array, [ qos ])
end

function generate_subscribe_packet(topic::String)
    random_id = rand(collect(UInt8, 1:127), 1)[1]
    var_header = subscribe_generate_var_header(random_id)
    payload = add_topic_to_payload(topic, qos=0x00)
    # Remaining length should be calculated as variable length encoded
    # this only works for values 0 - 127
    # See: https://docs.solace.com/MQTT-311-Prtl-Conformance-Spec/MQTT%20Control%20Packet%20format.htm#_Ref355703004
    remaining_len = UInt8(length(vcat(var_header, payload)))
    return vcat(UInt8[ 0x82 ], [remaining_len], var_header, payload)
end

function generate_unsubscribe_packet(topic::String)
    random_id = rand(collect(UInt8, 1:127), 1)[1]
    var_header = subscribe_generate_var_header(random_id)
    payload = add_topic_to_payload(topic)
    remaining_len = UInt8(length(vcat(var_header, payload)))
    return vcat(UInt8[ 0xa2 ], [remaining_len], var_header, payload)
end

function generate_connect_packet(client_id::String)
    var_header = connect_generate_var_header()
    payload = connect_generate_payload(client_id)
    remaining_len = UInt8(length(vcat(var_header, payload)))
    return vcat([0x10], [remaining_len], var_header, payload)
end

function generate_disconnect_packet()
    return UInt8[0xe0, 0x00]
end

function generate_ping_packet()
    return UInt8[0xc0, 0x00]
end

end  # module Mqtt
