-- ============================================================
--  NPC Cluster Throw  |  npc_cluster_throw.lua
--  Server-side only.
--
--  Combine soldiers, metrocops, and elites periodically have a
--  chance to lob a glass bottle (model: glassjug01.mdl) packed
--  with grenades toward the player they are targeting.
--
--  On impact the bottle shatters from the physics collision and
--  releases a randomised number of already-armed npc_grenade_frag
--  sub-munitions in an upward spread pattern.  There is no
--  explosion – the bottle simply breaks and the grenades scatter.
--
--  Animation and delay logic mirrors npc_smoke_throw.lua:
--  the throw gesture plays immediately, the bottle spawns
--  exactly 1 second later to match the animation release point.
--
--  The cluster bottle entity (npc_cluster_bomb_proj) lives in
--  lua/entities/npc_cluster_bomb_proj/ so GMod registers it on
--  both client and server automatically.
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled    = CreateConVar("npc_cluster_throw_enabled",      "1",    SHARED_FLAGS, "Enable/disable NPC cluster bomb throws.")
local cv_chance     = CreateConVar("npc_cluster_throw_chance",       "0.15", SHARED_FLAGS, "Probability (0-1) that an eligible NPC throws a cluster bomb each check.")
local cv_interval   = CreateConVar("npc_cluster_throw_interval",     "10",   SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown   = CreateConVar("npc_cluster_throw_cooldown",     "25",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed      = CreateConVar("npc_cluster_throw_speed",        "1200", SHARED_FLAGS, "Launch speed of the cluster bottle (units/s).")
local cv_arc        = CreateConVar("npc_cluster_throw_arc",          "0.30", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob).")
local cv_spawn_dist = CreateConVar("npc_cluster_throw_spawn_dist",   "58",   SHARED_FLAGS, "Forward distance from NPC eye to spawn point (avoids self-collision).")
local cv_max_dist   = CreateConVar("npc_cluster_throw_max_dist",     "2000", SHARED_FLAGS, "Max distance to player for a throw to be attempted.")
local cv_min_dist   = CreateConVar("npc_cluster_throw_min_dist",     "150",  SHARED_FLAGS, "Min distance to player (no throw if closer than this).")
local cv_spin       = CreateConVar("npc_cluster_throw_spin",         "1",    SHARED_FLAGS, "Apply a random spin impulse to the bottle in flight (1 = enabled).")
local cv_announce   = CreateConVar("npc_cluster_throw_announce",     "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC throws.")
-- The following convars are read by the entity (init.lua) via GetConVar.
-- They are declared here so they exist at server startup and the menu panel
-- can reference them before any bottle has ever been spawned.
CreateConVar("npc_cluster_throw_fuse",         "3.5",  SHARED_FLAGS, "Seconds before the bottle shatters via hard fuse (fallback for soft-geometry landings).")
CreateConVar("npc_cluster_throw_sub_fuse",     "2.0",  SHARED_FLAGS, "Fuse length of each sub-munition (seconds, +/- 0.25 s jitter applied).")
CreateConVar("npc_cluster_throw_grenade_min",  "3",    SHARED_FLAGS, "Minimum number of sub-munitions scattered on detonation.")
CreateConVar("npc_cluster_throw_grenade_max",  "9",    SHARED_FLAGS, "Maximum number of sub-munitions scattered on detonation.")
CreateConVar("npc_cluster_throw_launch_h_min", "250",  SHARED_FLAGS, "Minimum outward launch speed for sub-munitions (units/s).")
CreateConVar("npc_cluster_throw_launch_h_max", "550",  SHARED_FLAGS, "Maximum outward launch speed for sub-munitions (units/s).")
CreateConVar("npc_cluster_throw_launch_v_min", "200",  SHARED_FLAGS, "Minimum upward launch speed for sub-munitions (units/s).")
CreateConVar("npc_cluster_throw_launch_v_max", "400",  SHARED_FLAGS, "Maximum upward launch speed for sub-munitions (units/s).")

-- ============================================================
--  NPC whitelist
-- ============================================================

local CLUSTER_THROWERS = {
    ["npc_combine_s"]     = true,   -- Combine Soldier
    ["npc_metropolice"]   = true,   -- Metrocop
    ["npc_combine_elite"] = true,   -- Combine Elite
}

local function IsEligibleThrower(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return CLUSTER_THROWERS[npc:GetClass()] == true
end

-- ============================================================
--  Helpers
-- ============================================================

--- Calculates launch velocity to lob from 'from' toward 'to'.
--  Horizontal component is always the full throw speed toward target.
--  Vertical component is speed-proportional so arc height scales
--  naturally with throw power regardless of distance.
local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir        = (to - from)
    local horizontal = Vector(dir.x, dir.y, 0)

    if horizontal:Length() < 1 then horizontal = Vector(1, 0, 0) end
    horizontal:Normalize()

    local velH = horizontal * speed
    local velZ = speed * arcFactor + (to.z - from.z) * 0.5
    velZ = math.Clamp(velZ, -speed * 0.6, speed * 1.4)

    return Vector(velH.x, velH.y, velZ)
end

-- ============================================================
--  Core throw function
-- ============================================================

--- Triggers the throw animation immediately, then spawns and
--- launches npc_cluster_bomb_proj exactly 1 second later.
---@param npc Entity  The throwing NPC.
---@param target Entity  The target (player).
---@return boolean  true on success, false on failure.
local function ThrowClusterBomb(npc, target)

    -- --------------------------------------------------------
    --  STEP 1 (immediate): play the throw animation gesture.
    --  The projectile is spawned 1 second later in STEP 2 so
    --  that the release point of the animation lines up with
    --  the moment the bottle actually leaves the NPC's hand.
    -- --------------------------------------------------------
    do
        local gestureAct  = ACT_GESTURE_RANGE_ATTACK_THROW
        local fallbackAct = ACT_RANGE_ATTACK_THROW

        -- Only attempt gestures on a still-valid, living NPC.
        if IsValid( npc ) and npc:Health() > 0 then
            local seq = npc:SelectWeightedSequence( gestureAct )
            if seq <= 0 then
                seq = npc:SelectWeightedSequence( fallbackAct )
                if seq > 0 then gestureAct = fallbackAct end
            end
            if seq > 0 then
                npc:AddGesture( gestureAct )
            end
        end
    end

    -- Stamp the cooldown immediately so the timer loop cannot
    -- queue a second throw while we are waiting for the delay.
    npc.__cluster_lastThrow = CurTime()

    -- Snapshot distance for the optional announce log.
    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    -- --------------------------------------------------------
    --  STEP 2 (1 second later): spawn and launch the bottle.
    --  Target position is re-evaluated at launch time so the
    --  aim reflects where the player actually is.
    -- --------------------------------------------------------
    timer.Simple(1, function()

        -- Abort if either entity was removed or the NPC died during the delay.
        if not IsValid(npc) or not IsValid(target) then return end
        if npc:Health() <= 0 then return end

        -- Re-evaluate target position at the moment of release.
        local targetPos = target:GetPos() + Vector(0, 0, 36)

        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()
        local spawnDist = cv_spawn_dist:GetFloat()
        local spawnPos  = npcEyePos + toTarget * spawnDist

        -- Safety trace: pull back if something solid is in the way.
        local tr = util.TraceLine({
            start  = npcEyePos,
            endpos = spawnPos,
            filter = { npc },
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            spawnPos = npcEyePos + toTarget * (tr.Fraction * spawnDist * 0.85)
        end

        -- Create the cluster bottle entity.
        local bomb = ents.Create("npc_cluster_bomb_proj")
        if not IsValid(bomb) then
            if cv_announce:GetBool() then
                print("[NPC Cluster Throw] ERROR: npc_cluster_bomb_proj could not be created.")
            end
            return
        end

        local eyeAng = toTarget:Angle()
        local right  = eyeAng:Right()
        local up     = eyeAng:Up()

        bomb:SetPos(spawnPos + right * 6 + up * -2)
        bomb:SetAngles(npc:GetAngles() + Angle(-90, 0, 0))

        -- Store the throwing NPC so sub-munition kills are attributed correctly.
        bomb.ThrowerNPC = npc
        bomb:SetOwner(npc)

        -- Roll and bake the grenade count before Spawn() so the entity's
        -- Initialize() finds it already set and skips its own fallback roll.
        local gMin = math.max(1, GetConVar("npc_cluster_throw_grenade_min"):GetInt())
        local gMax = math.max(gMin, GetConVar("npc_cluster_throw_grenade_max"):GetInt())
        bomb.GrenadeCount = math.random(gMin, gMax)

        bomb:Spawn()
        bomb:Activate()

        -- Apply physics impulse after spawn.
        local phys = bomb:GetPhysicsObject()
        if IsValid(phys) then
            local speed = cv_speed:GetFloat()
            local vel   = CalcLaunchVelocity(spawnPos, targetPos, speed, cv_arc:GetFloat())
            phys:SetVelocity(vel)

            -- Optional random spin so the bottle tumbles visibly in flight.
            if cv_spin:GetBool() then
                local spin   = vel:GetNormalized() * math.random(4, 9)
                local offset = bomb:LocalToWorld(bomb:OBBCenter())
                             + Vector(0, 0, math.random(8, 14))
                phys:ApplyForceOffset(spin, offset)
            end

            phys:Wake()
        end

        if cv_announce:GetBool() then
            print(string.format(
                "[NPC Cluster Throw] %s threw a cluster bottle at %s (dist: %.0f, grenades: %d)",
                npc:GetClass(), target:Nick(), distAtTrigger, bomb.GrenadeCount
            ))
        end

    end)  -- end timer.Simple

    return true
end

-- ============================================================
--  Per-NPC state initialisation (lazy)
-- ============================================================

local function InitNPCState(npc)
    if not IsValid(npc)         then return end
    if npc.__cluster_hooked     then return end
    npc.__cluster_hooked    = true
    npc.__cluster_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__cluster_lastThrow = 0
end

-- ============================================================
--  Main Think loop  (timer-based, avoids per-frame iteration)
-- ============================================================

timer.Create("NPCClusterThrow_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now      = CurTime()
    local interval = cv_interval:GetFloat()
    local cooldown = cv_cooldown:GetFloat()
    local chance   = cv_chance:GetFloat()
    local maxDist  = cv_max_dist:GetFloat()
    local minDist  = cv_min_dist:GetFloat()

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not IsEligibleThrower(npc)           then continue end

        -- Lazy state initialisation
        InitNPCState(npc)

        -- Time gate: only run the full check every `interval` seconds per NPC
        if now < (npc.__cluster_nextCheck or 0) then continue end
        npc.__cluster_nextCheck = now + interval + math.Rand(-1, 1)

        -- Cooldown gate
        if now - (npc.__cluster_lastThrow or 0) < cooldown then continue end

        -- NPC must be alive and actively targeting a player
        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        -- Distance check
        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check
        local losTr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if losTr.Entity ~= enemy and losTr.Fraction < 0.85 then continue end

        -- Probability roll
        if math.random() > chance then continue end

        -- All checks passed – throw!
        ThrowClusterBomb(npc, enemy)
    end
end)

-- ============================================================
--  Startup message
-- ============================================================

hook.Add("InitPostEntity", "NPCClusterThrow_Init", function()
    print("[NPC Cluster Throw] Addon loaded.")
    print("[NPC Cluster Throw] Use 'npc_cluster_throw_*' convars to configure.")
    print("[NPC Cluster Throw] Entity: lua/entities/npc_cluster_bomb_proj/")
end)
