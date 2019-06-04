struct FakeStream <: IO
    input::IO
    output::IO
end

function Base.read(stream::FakeStream, T::Type{UInt8})
    Base.read(stream.output, T)
end

function Base.read(stream::FakeStream, nb::UInt8)
    Base.read(stream.output, nb)
end

function Base.write(stream::FakeStream, bytes::Array{UInt8, 1})
    Base.write(stream.input, bytes)
end
