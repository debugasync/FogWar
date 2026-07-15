# FogWar

**Scrapped. Left up as a reference, not maintained.**

The idea is sound (it's how Valorant does fog of war) but the Roblox engine does not
give you the hooks to pull it off cleanly. FogWar only means anything if you stop the
engine from replicating characters by default, and there is no way to un-replicate a
character from one client in stock Roblox. The moment you go full custom replication
to get around that, you inherit everything default replication gave you for free:
animations, tools, accessories, ragdolls, network ownership. Streaming all of that
yourself, animations especially, over an unreliable channel at tick rate is more work
and less reliable than it is worth for basically any real game.

It is still usable for **server-driven entities** (NPCs, AI bots) or for games that
already run their own character replication, since those never depended on the default
path. For a normal game with default characters, it does nothing, a client-side
highlight reads the real body straight out of Workspace and walks right through it.

Everything below is the original writeup.

---

Server-authoritative visibility replication for Roblox. The server only tells a
client where an enemy is when that client can actually see them. If you can't see
someone, your client never receives their position, so wallhacks and ESP have
nothing to read.

This is the same idea Valorant's Fog of War uses. It is not a detection system.
There is nothing to detect because the data never leaves the server.

## the catch, read this first

FogWar does not magically stop Roblox from replicating characters. By default the
engine streams every player's real character to every client, and no amount of
server code changes that. For FogWar to mean anything you have to turn that off and
drive enemies yourself:

- keep the real characters server-side only (own rig, or a folder the client never
  gets), so the engine has nothing to replicate
- give each client a "ghost" model per enemy that starts hidden
- let FogWar decide who is visible and move the ghosts

If you skip that step and leave default replication on, this does nothing. The whole
point is that the client never holds the real transform in the first place.

## how it decides visibility

Every tick, for each viewer, it raycasts from the viewer's eye to a few points on
each nearby enemy (head, torso, feet, both shoulders). One clear point is enough to
count as visible. It uses line of sight, not field of view, on purpose: players can
flick 180 degrees in a frame, so culling by where someone is looking would pop
enemies in and out and get people killed.

Two shortcuts skip the raycasts:

- anyone within `HearingRadius` is always revealed, since you'd hear them anyway
- an optional relation callback can force teammates or spectators to always show

When you lose sight of someone their ghost freezes at the last spot you saw them for
`LingerTime`, then stops updating. The frozen pose is the last-seen one, not the live
one, so nobody can pull a live position through a wall during the grace window.

Broad phase is a spatial hash so a viewer only tests enemies in nearby cells, and
there's a hard raycast budget per tick so a full server can't tank the frame.

## install

wally:

```toml
[dependencies]
FogWar = "debugasync/fogwar@0.1.0"
```

or drop the `src` folder into ReplicatedStorage as a folder named `FogWar`.

## server

```lua
local FogWar = require(game.ReplicatedStorage.FogWar.Server)

FogWar.SetOccluders({ workspace.Map })

FogWar.Configure({
    TickRate = 20,
    MaxRange = 800,
    HearingRadius = 22,
    LingerTime = 0.35,
})

-- optional: keep friendlies visible
FogWar.SetRelation(function(viewer, targetId)
    return SameTeam(viewer.UserId, targetId)
end)

FogWar.BindPlayers()
FogWar.Start(game.ReplicatedStorage.FogWarRelay)
```

`FogWarRelay` should be an UnreliableRemoteEvent. Position updates are fine to drop,
and unreliable events skip the ordering and resend overhead.

If you have your own rigs instead of default characters, skip `BindPlayers` and call
`FogWar.AddViewer` / `FogWar.AddTarget` yourself. Target ids just have to be numbers,
which is why UserId is the default.

## client

```lua
local FogWarClient = require(game.ReplicatedStorage.FogWar.Client)

-- bind each ghost model you spawned for an enemy
FogWarClient.BindGhost(enemyUserId, ghostModel)

FogWarClient.OnVisibility(function(id, visible)
    local ghost = ghostsById[id]
    ghost.Parent = visible and workspace or nil
end)

FogWarClient.Start(game.ReplicatedStorage.FogWarRelay)
```

The client interpolates between the last two snapshots with a small delay so movement
stays smooth at 20 ticks. `OnVisibility` fires when a ghost should be shown or hidden,
you decide what that means (parent swap, transparency, disable, whatever).

## config

| key | default | what it does |
| --- | --- | --- |
| TickRate | 20 | solves per second |
| MaxRange | 800 | studs past which nobody is revealed |
| HearingRadius | 22 | always-reveal radius |
| LingerTime | 0.35 | seconds a ghost stays after losing sight |
| CellSize | 96 | spatial hash cell size in studs |
| MaxRaysPerStep | 2500 | raycast budget per tick |
| UseFieldOfView | false | also require the target be in front |
| FieldOfView | 100 | degrees, only if UseFieldOfView is on |

## the other half: gate your own remotes

Hiding characters is only worth something if nothing else leaks position. Any remote
you fire to all clients with a location in it (gunshot origins, hitmarkers, nametags,
kill feed coordinates, positional sound) hands a cheater exactly what FogWar withheld.
A smart cheater does not hook the client, they go find one of these.

`IsVisible` is the gate. Ask it before you send:

```lua
for _, player in Players:GetPlayers() do
    if FogWar.IsVisible(player, shooter.UserId) then
        GunshotRelay:FireClient(player, shooter.UserId, origin)
    end
end
```

Now the gunshot only reaches people who could already see the shooter. Do this for
every channel that carries a position and the surface actually closes. It returns
true while a target is live or inside the linger window, false otherwise.

## limitations

- you need custom replication, see the top of this readme
- sample points assume a roughly humanoid rig around 5 studs tall. change the offsets
  in Server.luau if your rigs are a different size
- occlusion is whatever you pass to SetOccluders. thin or non-collidable cover that
  isn't in that list won't block sight
- there is no client prediction of your own character here, this is only about what
  you're allowed to see of others

## license

MIT
