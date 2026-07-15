-- FogWar / Server

local Vector3New = Vector3.new
local Clock = os.clock
local Floor = math.floor
local Atan2 = math.atan2
local Cos = math.cos
local Rad = math.rad

local Remove = table.remove
local Spawn = task.spawn

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Raycast = Workspace.Raycast
local Heartbeat = RunService.Heartbeat

local Packet = require(script.Parent.Packet)


-- Config
local Config = {
    TickRate = 20,
    MaxRange = 800,
    HearingRadius = 22,
    LingerTime = 0.35,
    CellSize = 96,
    MaxRaysPerStep = 2500,
    UseFieldOfView = false,
    FieldOfView = 100,
}


-- Namespaces
local FogWar = {}

local Grid = {}
local Solver = {}

local Targets = {}
local TargetsIndex = 0

local Viewers = {}
local ViewersIndex = 0

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Include
RayParams.RespectCanCollide = false
RayParams.IgnoreWater = true

local Remote
local RelationFn

local Samples = {
    Vector3New(0, 1.5, 0),
    Vector3New(0, 0, 0),
    Vector3New(0, -2.5, 0),
    Vector3New(0.9, 0, 0),
    Vector3New(-0.9, 0, 0),
}
local SamplesIndex = #Samples


-- Grid
do
    Grid.Cells = {}
    Grid.CellSize = Config.CellSize

    local function Key(X, Z)
        return Floor(X / Grid.CellSize) .. "," .. Floor(Z / Grid.CellSize)
    end

    Grid.Insert = function(Target)
        local Position = Target.RootPosition
        if not Position then
            return
        end

        local CellKey = Key(Position.X, Position.Z)
        local Cell = Grid.Cells[CellKey]

        if not Cell then
            Cell = {}
            Grid.Cells[CellKey] = Cell
        end

        Cell[Target] = true
        Target.CellKey = CellKey
    end

    Grid.Remove = function(Target)
        local CellKey = Target.CellKey
        if not CellKey then
            return
        end

        local Cell = Grid.Cells[CellKey]
        if Cell then
            Cell[Target] = nil
        end

        Target.CellKey = nil
    end

    Grid.Update = function(Target)
        local Position = Target.RootPosition
        if not Position then
            Grid.Remove(Target)
            return
        end

        local CellKey = Key(Position.X, Position.Z)
        if CellKey == Target.CellKey then
            return
        end

        Grid.Remove(Target)
        Grid.Insert(Target)
    end

    Grid.Query = function(Origin, Range, Output)
        local OutputIndex = 0
        local CellSize = Grid.CellSize

        local MinX = Floor((Origin.X - Range) / CellSize)
        local MaxX = Floor((Origin.X + Range) / CellSize)
        local MinZ = Floor((Origin.Z - Range) / CellSize)
        local MaxZ = Floor((Origin.Z + Range) / CellSize)

        for X = MinX, MaxX do
            for Z = MinZ, MaxZ do
                local Cell = Grid.Cells[X .. "," .. Z]
                if not Cell then
                    continue
                end

                for Target in next, Cell do
                    OutputIndex += 1
                    Output[OutputIndex] = Target
                end
            end
        end

        return OutputIndex
    end
end


-- Solver
do
    Solver.CanSee = function(Eye, Target, Budget)
        local RootCFrame = Target.RootCFrame
        if not RootCFrame then
            return false, Budget
        end

        for i = 1, SamplesIndex do
            if Budget <= 0 then
                return false, 0
            end

            local Point = RootCFrame:PointToWorldSpace(Samples[i])
            local Result = Raycast(Workspace, Eye, Point - Eye, RayParams)

            Budget -= 1

            if not Result then
                return true, Budget
            end
        end

        return false, Budget
    end

    Solver.InFieldOfView = function(EyeCFrame, Position, CosHalf)
        local Offset = Position - EyeCFrame.Position
        local Magnitude = Offset.Magnitude

        if Magnitude < 0.001 then
            return true
        end

        return EyeCFrame.LookVector:Dot(Offset / Magnitude) >= CosHalf
    end
end


-- Targets
do
    FogWar.AddTarget = function(Id, Root)
        assert(type(Id) == "number", "target id must be a number (UserId works)")

        if Targets[Id] then
            return Targets[Id]
        end

        local Data = {
            Id = Id,
            Root = Root,
            RootCFrame = nil,
            RootPosition = nil,
            CellKey = nil,
        }

        TargetsIndex += 1
        Targets[TargetsIndex] = Data
        Targets[Id] = Data

        if Root then
            Data.RootCFrame = Root.CFrame
            Data.RootPosition = Root.Position
            Grid.Insert(Data)
        end

        return Data
    end

    FogWar.RemoveTarget = function(Id)
        local Data = Targets[Id]
        if not Data then
            return
        end

        Grid.Remove(Data)
        Targets[Id] = nil

        for i = 1, TargetsIndex do
            if Targets[i] == Data then
                Remove(Targets, i)
                TargetsIndex -= 1
                break
            end
        end

        for i = 1, ViewersIndex do
            Viewers[i].Seen[Id] = nil
        end
    end
end


-- Viewers
do
    FogWar.AddViewer = function(Player, Root)
        if Viewers[Player] then
            return Viewers[Player]
        end

        local Data = {
            Player = Player,
            Root = Root,
            Seen = {},
            Candidates = {},
        }

        ViewersIndex += 1
        Viewers[ViewersIndex] = Data
        Viewers[Player] = Data

        return Data
    end

    FogWar.RemoveViewer = function(Player)
        local Data = Viewers[Player]
        if not Data then
            return
        end

        Viewers[Player] = nil

        for i = 1, ViewersIndex do
            if Viewers[i] == Data then
                Remove(Viewers, i)
                ViewersIndex -= 1
                break
            end
        end
    end
end


-- Solve
do
    local Entries = {}

    local function Refresh()
        for i = 1, TargetsIndex do
            local Data = Targets[i]
            local Root = Data.Root

            if Root and Root.Parent then
                Data.RootCFrame = Root.CFrame
                Data.RootPosition = Root.Position
                Grid.Update(Data)
            else
                Data.RootCFrame = nil
                Data.RootPosition = nil
                Grid.Remove(Data)
            end
        end
    end

    FogWar.Solve = function()
        Refresh()

        local Now = Clock()
        local Budget = Config.MaxRaysPerStep
        local MaxRange = Config.MaxRange
        local MaxRangeSq = MaxRange * MaxRange
        local HearingSq = Config.HearingRadius * Config.HearingRadius
        local LingerTime = Config.LingerTime
        local UseFov = Config.UseFieldOfView
        local CosHalf = Cos(Rad(Config.FieldOfView) / 2)

        for v = 1, ViewersIndex do
            local Viewer = Viewers[v]
            local Root = Viewer.Root

            if not Root or not Root.Parent then
                continue
            end

            local EyeCFrame = Root.CFrame
            local Eye = EyeCFrame.Position + Vector3New(0, 1.5, 0)
            local Seen = Viewer.Seen
            local Candidates = Viewer.Candidates
            local CandidatesIndex = Grid.Query(Eye, MaxRange, Candidates)

            local EntriesIndex = 0

            for c = 1, CandidatesIndex do
                local Target = Candidates[c]
                local Position = Target.RootPosition

                if not Position or Target.Root == Root then
                    continue
                end

                local Offset = Position - Eye
                if Offset:Dot(Offset) > MaxRangeSq then
                    continue
                end

                local Visible

                if RelationFn and RelationFn(Viewer.Player, Target.Id) then
                    Visible = true
                elseif Offset:Dot(Offset) <= HearingSq then
                    Visible = true
                elseif UseFov and not Solver.InFieldOfView(EyeCFrame, Position, CosHalf) then
                    Visible = false
                else
                    Visible, Budget = Solver.CanSee(Eye, Target, Budget)
                end

                local Memory = Seen[Target.Id]
                local EntryPosition
                local EntryYaw
                local EntryFlags

                if Visible then
                    if not Memory then
                        Memory = {}
                        Seen[Target.Id] = Memory
                    end

                    local Look = Target.RootCFrame.LookVector
                    Memory.Time = Now
                    Memory.Position = Position
                    Memory.Yaw = Atan2(Look.X, Look.Z)

                    EntryPosition = Position
                    EntryYaw = Memory.Yaw
                    EntryFlags = Packet.Live
                else
                    if not Memory then
                        continue
                    end

                    if Now - Memory.Time > LingerTime then
                        Seen[Target.Id] = nil
                        continue
                    end

                    EntryPosition = Memory.Position
                    EntryYaw = Memory.Yaw
                    EntryFlags = Packet.Linger
                end

                EntriesIndex += 1

                local Entry = Entries[EntriesIndex]
                if not Entry then
                    Entry = {}
                    Entries[EntriesIndex] = Entry
                end

                Entry.Id = Target.Id
                Entry.Position = EntryPosition
                Entry.Yaw = EntryYaw
                Entry.Flags = EntryFlags
            end

            if EntriesIndex > 0 then
                Remote:FireClient(Viewer.Player, Packet.Write(Entries, EntriesIndex))
            end
        end
    end
end


-- API
do
    FogWar.Configure = function(Options)
        for K, V in next, Options do
            Config[K] = V
        end

        Grid.CellSize = Config.CellSize
    end

    FogWar.SetOccluders = function(Instances)
        RayParams.FilterDescendantsInstances = Instances
    end

    FogWar.SetRelation = function(Callback)
        RelationFn = Callback
    end

    FogWar.BindPlayers = function()
        local function OnCharacter(Player, Character)
            local Root = Character:WaitForChild("HumanoidRootPart", 10)
            if not Root then
                return
            end

            FogWar.AddViewer(Player, Root)
            FogWar.AddTarget(Player.UserId, Root)
        end

        local function OnPlayer(Player)
            if Player.Character then
                Spawn(OnCharacter, Player, Player.Character)
            end

            Player.CharacterAdded:Connect(function(Character)
                OnCharacter(Player, Character)
            end)
        end

        local List = Players:GetPlayers()
        for i = 1, #List do
            OnPlayer(List[i])
        end

        Players.PlayerAdded:Connect(OnPlayer)
        Players.PlayerRemoving:Connect(function(Player)
            FogWar.RemoveViewer(Player)
            FogWar.RemoveTarget(Player.UserId)
        end)
    end

    FogWar.Start = function(RemoteEvent)
        assert(RemoteEvent, "FogWar.Start needs an unreliable RemoteEvent")
        Remote = RemoteEvent

        local Interval = 1 / Config.TickRate
        local Accumulator = 0

        Heartbeat:Connect(function(DeltaTime)
            Accumulator += DeltaTime
            if Accumulator < Interval then
                return
            end

            Accumulator -= Interval
            if Accumulator > Interval then
                Accumulator = 0
            end

            FogWar.Solve()
        end)
    end
end

return FogWar
