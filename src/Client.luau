-- FogWar / Client

local Vector3New = Vector3.new
local CFrameNew = CFrame.new
local Angles = CFrame.Angles
local Clock = os.clock
local Clamp = math.clamp
local Pi = math.pi
local TwoPi = math.pi * 2

local RunService = game:GetService("RunService")
local RenderStepped = RunService.RenderStepped

local Packet = require(script.Parent.Packet)


-- Config
local InterpDelay = 0.1
local HideAfter = 0.5


-- Namespace
local FogWarClient = {}

local Ghosts = {}
local Scratch = {}
local Remote
local VisibilityFn

FogWarClient.Configure = function(Options)
    if Options.InterpDelay then
        InterpDelay = Options.InterpDelay
    end

    if Options.HideAfter then
        HideAfter = Options.HideAfter
    end
end


local function AngleLerp(A, B, Alpha)
    local Difference = (B - A) % TwoPi
    if Difference > Pi then
        Difference -= TwoPi
    end

    return A + Difference * Alpha
end


-- Ghosts
do
    FogWarClient.BindGhost = function(Id, Pivotable)
        local Ghost = {
            Pivotable = Pivotable,
            Previous = nil,
            Next = nil,
            Last = 0,
            Hidden = true,
        }

        Ghosts[Id] = Ghost
        return Ghost
    end

    FogWarClient.UnbindGhost = function(Id)
        Ghosts[Id] = nil
    end
end


-- Receive
do
    local function OnPacket(Data)
        local Count = Packet.Read(Data, Scratch)
        local Now = Clock()

        for i = 1, Count do
            local Entry = Scratch[i]
            local Ghost = Ghosts[Entry.Id]

            if not Ghost then
                continue
            end

            Ghost.Previous = Ghost.Next or {
                Time = Now,
                Position = Vector3New(Entry.X, Entry.Y, Entry.Z),
                Yaw = Entry.Yaw,
            }

            Ghost.Next = {
                Time = Now,
                Position = Vector3New(Entry.X, Entry.Y, Entry.Z),
                Yaw = Entry.Yaw,
            }

            Ghost.Last = Now

            if Ghost.Hidden then
                Ghost.Hidden = false
                if VisibilityFn then
                    VisibilityFn(Entry.Id, true)
                end
            end
        end
    end

    FogWarClient.Start = function(RemoteEvent)
        assert(RemoteEvent, "FogWarClient.Start needs the same RemoteEvent the server fires")
        Remote = RemoteEvent
        Remote.OnClientEvent:Connect(OnPacket)

        RenderStepped:Connect(function()
            local Now = Clock()
            local RenderTime = Now - InterpDelay

            for Id, Ghost in next, Ghosts do
                if not Ghost.Hidden and Now - Ghost.Last > HideAfter then
                    Ghost.Hidden = true
                    if VisibilityFn then
                        VisibilityFn(Id, false)
                    end

                    continue
                end

                local Previous = Ghost.Previous
                local Next = Ghost.Next

                if Ghost.Hidden or not Previous or not Next then
                    continue
                end

                local Span = Next.Time - Previous.Time
                local Alpha = Span > 0 and Clamp((RenderTime - Previous.Time) / Span, 0, 1) or 1

                local Position = Previous.Position:Lerp(Next.Position, Alpha)
                local Yaw = AngleLerp(Previous.Yaw, Next.Yaw, Alpha)

                Ghost.Pivotable:PivotTo(CFrameNew(Position) * Angles(0, Yaw, 0))
            end
        end)
    end

    FogWarClient.OnVisibility = function(Callback)
        VisibilityFn = Callback
    end
end


return FogWarClient
