using Mqtt
using Test
using Sockets

include("server_streams.jl")


@test Mqtt.subscribe_generate_var_header(UInt16(0x00))   == UInt8[ 0x00, 0x00 ]
@test Mqtt.subscribe_generate_var_header(UInt8(0x12))    == UInt8[ 0x00, 0x12 ]
@test Mqtt.subscribe_generate_var_header(UInt16(0x1234)) == UInt8[ 0x12, 0x34 ]

@test Mqtt.add_topic_to_payload("foo/bar", qos=0x02) == UInt8[ 0x00, 0x07, 0x66, 0x6f, 0x6f, 0x2f, 0x62, 0x61, 0x72, 0x02]

@test Mqtt.generate_connect_packet("a/b/c") == UInt8[0x10, 17, 0x00, 0x04, 0x4d, 0x51, 0x54, 0x54, 0x04, 0x02, 0x00, 0x3c, 0x00, 0x05, 0x61, 0x2f, 0x62, 0x2f, 0x63]

server_address = "mqtt.pndsn.com"
server_port = 1883

@test typeof(Mqtt.get_packet_type(0x10)) == Mqtt.Connect

@testset "Connect to MQTT server" begin
    client = connect(server_address, server_port)
    stream = Mqtt.generate_connect_packet("demo/sub-c-5f1b7c8e-fbee-11e3-aa40-02ee2ddab7fe/marko")
    @test typeof(stream) == Array{UInt8, 1}
    Base.write(client, stream)
    bytes_read::Vector{UInt8} = Base.read(client, 4)
    @test bytes_read[1] == 0x20
    @test bytes_read[2] == 0x02
    @test bytes_read[3] == 0x00
    @test bytes_read[4] == 0x00
end # begin

@testset "Process CONNECTACK packet" begin
    @testset "Process a successful connect message" begin
        connect_ack_success_stream = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x00 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_success_stream)
        @test Mqtt.receive_packet(client) == (true, "Connection Accepted")
    end

    @testset "Process an unsuccessful connect message (unacceptable protocol version)" begin
        connect_ack_error1_stream  = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x01 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_error1_stream)
        @test Mqtt.receive_packet(client) == (false, "Connection Refused, unacceptable protocol version")
    end

    @testset "Process an unsuccessful connect message (identifier rejected)" begin
        connect_ack_error1_stream  = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x02 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_error1_stream)
        @test Mqtt.receive_packet(client) |> first == false
    end

    @testset "Process an unsuccessful connect message (server unavailable)" begin
        connect_ack_error1_stream  = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x03 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_error1_stream)
        @test Mqtt.receive_packet(client) |> first == false
    end

    @testset "Process an unsuccessful connect message (bad user name or password)" begin
        connect_ack_error1_stream  = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x04 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_error1_stream)
        @test Mqtt.receive_packet(client) |> first == false
    end

    @testset "Process an unsuccessful connect message (not authorized)" begin
        connect_ack_error1_stream  = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x05 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_error1_stream)
        @test Mqtt.receive_packet(client) |> first == false
    end

    @testset "Process an unsuccessful connect message (unknown)" begin
        connect_ack_error1_stream  = IOBuffer(UInt8[ 0x20, 0x02, 0x00, 0x07 ])
        client = Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, connect_ack_error1_stream)
        @test Mqtt.receive_packet(client) == (false, "Connection Refused, unknown")
    end
end

@testset "Process SUBACK message" begin
    @testset "Process a successful subscribe ack message with only one element" begin
        @test Mqtt.process_packet(Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, IOBuffer()), Mqtt.SubAck(), [0x00, 0x01, 0x00] ) == [ true ]
    end

    @testset "Process a failed subscribe ack message with only one element" begin
        @test Mqtt.process_packet(Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, IOBuffer()), Mqtt.SubAck(), [0x00, 0x01, 0x80] ) == [ false ]
    end

    @testset "Process a subscribe ack message with two elements (a successful and a failed subscription)" begin
        @test Mqtt.process_packet(Mqtt.Client(() -> Nothing, () -> Nothing, () -> Nothing, IOBuffer()), Mqtt.SubAck(), [0x00, 0x01, 0x00, 0x80] ) == [ true, false ]
    end
end

@testset "Process PUBLISH message" begin
    @testset "Processing a message should trigger publish_handler function" begin
        handler_ok = false
        expected_payload = UInt8[0x00, 0x03, 'a', '/', 'b', 0x01, 0x02]
        publish_handler = (payload) -> handler_ok = (payload == expected_payload)

        publish_message = UInt8[0x30, 0x08, 0x00, 0x03, 'a', '/', 'b', 0x01, 0x02]
        buffer = IOBuffer(publish_message)

        client = Mqtt.Client(() -> Nothing, () -> Nothing, publish_handler, buffer)
        Mqtt.receive_packet(client)
        @test handler_ok == true
    end # begin
end

@testset "Trigger correct function based on received packet type" begin

end

@testset "get_packet_type returns correct type" begin
    @test Mqtt.get_packet_type(0x10) ==  Mqtt.Connect()
end
