-- FogWar packet

local Create = buffer.create
local WriteU8 = buffer.writeu8
local WriteF64 = buffer.writef64
local WriteF32 = buffer.writef32
local ReadU8 = buffer.readu8
local ReadF64 = buffer.readf64
local ReadF32 = buffer.readf32

local Packet = {}

Packet.Header = 1
Packet.EntrySize = 25

Packet.Live = 1
Packet.Linger = 2

Packet.Write = function(Entries, Count)
    local Data = Create(Packet.Header + Count * Packet.EntrySize)
    WriteU8(Data, 0, Count)

    local Cursor = 1

    for i = 1, Count do
        local Entry = Entries[i]
        local Position = Entry.Position

        WriteF64(Data, Cursor, Entry.Id)
        WriteF32(Data, Cursor + 8, Position.X)
        WriteF32(Data, Cursor + 12, Position.Y)
        WriteF32(Data, Cursor + 16, Position.Z)
        WriteF32(Data, Cursor + 20, Entry.Yaw)
        WriteU8(Data, Cursor + 24, Entry.Flags)

        Cursor += Packet.EntrySize
    end

    return Data
end

Packet.Read = function(Data, Out)
    local Count = ReadU8(Data, 0)
    local Cursor = 1

    for i = 1, Count do
        local Entry = Out[i]
        if not Entry then
            Entry = {}
            Out[i] = Entry
        end

        Entry.Id = ReadF64(Data, Cursor)
        Entry.X = ReadF32(Data, Cursor + 8)
        Entry.Y = ReadF32(Data, Cursor + 12)
        Entry.Z = ReadF32(Data, Cursor + 16)
        Entry.Yaw = ReadF32(Data, Cursor + 20)
        Entry.Flags = ReadU8(Data, Cursor + 24)

        Cursor += Packet.EntrySize
    end

    return Count
end

return Packet
