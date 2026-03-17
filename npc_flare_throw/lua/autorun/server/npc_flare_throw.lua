-- ============================================================
--  NPC Flare Throw  |  npc_flare_throw.lua
--  Server-side only.
--
--  Enemy NPCs periodically have a chance to lob a flare round
--  (entity: obj_vj_flareround) toward the player they are
--  targeting.  No animation is required – the entity simply
--  spawns slightly in front of the NPC and is given a physics
--  impulse aimed at the target.
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars  (FCVAR_REPLICATED = editable from the Options menu
--           on listen servers / singleplayer)
-- ============================================================
-- FCVAR_REPLICATED makes these ConVars visible and settable from the client
-- Options menu (listen server / singleplayer).  FCVAR_NOTIFY announces
-- changes to all players in chat.
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled      = CreateConVar("npc_flare_throw_enabled",     "1",    SHARED_FLAGS, "Enable/disable NPC flare throws.")
local cv_chance       = CreateConVar("npc_flare_throw_chance",      "0.15", SHARED_FLAGS, "Probability (0–1) that an eligible NPC throws a flare each check.")
local cv_interval     = CreateConVar("npc_flare_throw_interval",    "6",    SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown     = CreateConVar("npc_flare_throw_cooldown",    "12",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed        = CreateConVar("npc_flare_throw_speed",       "550",  SHARED_FLAGS, "Launch speed of the flare (units/s).")
local cv_arc          = CreateConVar("npc_flare_throw_arc",         "0.22", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob).")
local cv_spawn_dist   = CreateConVar("npc_flare_throw_spawn_dist",  "52",   SHARED_FLAGS, "Forward distance from NPC origin to spawn flare (avoids self-collision).")
local cv_max_dist     = CreateConVar("npc_flare_throw_max_dist",    "2500", SHARED_FLAGS, "Max distance to player for a throw to be attempted.")
local cv_min_dist     = CreateConVar("npc_flare_throw_min_dist",    "100",  SHARED_FLAGS, "Min distance to player (no throw if closer than this).")

-- ============================================================
--  Helpers
-- ============================================================

--- Returns a valid player to use for disposition checks, or nil.
local function GetAnyPlayer()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then return ply end
    end
    return nil
end

--- Returns true if the NPC is an enemy to players.
local function IsEnemyNPC(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    local ply = GetAnyPlayer()
    -- No players on the server yet – nothing to be an enemy of
    if not ply then return false end
    -- Disposition toward players: D_HT = hate, D_FR = fear
    local disp = npc:Disposition(ply)
    if disp == D_HT or disp == D_FR then return true end
    -- Also accept any NPC whose class starts with "npc_" and is not allied
    if npc:GetClass():sub(1, 4) == "npc_" and disp ~= D_LI and disp ~= D_NU then
        return true
    end
    return false
end

--- Calculates launch velocity to lob from 'from' toward 'to' with
--- the configured speed and arc.  Adds upward component proportionally.
local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir = (to - from)
    local horizontal = Vector(dir.x, dir.y, 0)
    local dist = horizontal:Length()

    -- Normalise horizontal component then scale to desired speed
    if dist < 1 then dist = 1 end
    horizontal:Normalize()

    local velH = horizontal * speed
    -- Vertical component: a fraction of distance creates a natural lob
    local velZ = dist * arcFactor + (to.z - from.z) * 0.3
    -- Clamp vertical so it doesn't fly off into the sky
    velZ = math.Clamp(velZ, -speed * 0.5, speed * 0.8)

    return Vector(velH.x, velH.y, velZ)
end

--- Spawns the flare entity safely in front of the NPC.
local function ThrowFlare(npc, target)
    -- Pick a target position: aim at centre-mass of the target
    local targetPos = target:GetPos() + Vector(0, 0, 28)

    -- Spawn position: offset forward from NPC's eye position so the
    -- entity does not overlap the NPC's collision hull on creation.
    local npcEyePos  = npc:EyePos()
    local toTarget   = (targetPos - npcEyePos):GetNormalized()
    local spawnDist  = cv_spawn_dist:GetFloat()
    local spawnPos   = npcEyePos + toTarget * spawnDist

    -- Safety trace: if something is in the way within spawnDist, abort.
    local tr = util.TraceLine({
        start  = npcEyePos,
        endpos = spawnPos,
        filter = { npc },
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then
        spawnPos = npcEyePos + toTarget * (tr.Fraction * spawnDist * 0.85)
    end

    -- Create the flare entity
    local flare = ents.Create("obj_vj_flareround")
    if not IsValid(flare) then
        -- Fallback: entity name might not exist, silently abort
        return false
    end

    flare:SetPos(spawnPos)
    -- Orient the flare in the direction of travel for aesthetics
    flare:SetAngles(toTarget:Angle())
    flare:Spawn()
    flare:Activate()

    -- Apply physics velocity if the entity has a physics object
    local phys = flare:GetPhysicsObject()
    if IsValid(phys) then
        local vel = CalcLaunchVelocity(spawnPos, targetPos, cv_speed:GetFloat(), cv_arc:GetFloat())
        phys:SetVelocity(vel)
        phys:Wake()
    else
        -- Entity has no physics (e.g. it moves itself); set velocity via entity method if available
        if flare.SetVelocity then
            local vel = CalcLaunchVelocity(spawnPos, targetPos, cv_speed:GetFloat(), cv_arc:GetFloat())
            flare:SetVelocity(vel)
        end
    end

    -- Mark the NPC so we can enforce cooldown
    npc.__flare_lastThrow = CurTime()

    return true
end

-- ============================================================
--  Per-NPC Think hook (using NPC's own Think for efficiency)
-- ============================================================

-- We attach a hook per NPC rather than iterating all NPCs every
-- frame, which keeps performance low.

local function AttachFlareThinkToNPC(npc)
    if not IsValid(npc) then return end
    if npc.__flare_hooked then return end
    npc.__flare_hooked    = true
    npc.__flare_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__flare_lastThrow = 0
end

-- ============================================================
--  Main Think loop  (runs on a timer, not every frame)
-- ============================================================

timer.Create("NPCFlareThrow_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now        = CurTime()
    local interval   = cv_interval:GetFloat()
    local cooldown   = cv_cooldown:GetFloat()
    local chance     = cv_chance:GetFloat()
    local maxDist    = cv_max_dist:GetFloat()
    local minDist    = cv_min_dist:GetFloat()

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not IsEnemyNPC(npc) then continue end

        -- Lazy-init per-NPC state
        AttachFlareThinkToNPC(npc)

        -- Time gate: only check every `interval` seconds per NPC
        if now < (npc.__flare_nextCheck or 0) then continue end
        npc.__flare_nextCheck = now + interval + math.Rand(-1, 1)

        -- Cooldown gate: enough time since last throw?
        if now - (npc.__flare_lastThrow or 0) < cooldown then continue end

        -- NPC must be alive and have an enemy (player)
        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end

        -- Distance check
        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check – don't throw if heavily occluded
        local tr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if tr.Entity ~= enemy and tr.Fraction < 0.85 then continue end

        -- Probability roll
        if math.random() > chance then continue end

        -- All checks passed – throw the flare
        ThrowFlare(npc, enemy)
    end
end)

-- ============================================================
--  Chat / Console feedback
-- ============================================================

hook.Add("InitPostEntity", "NPCFlareThrow_Init", function()
    print("[NPC Flare Throw] Addon loaded.")
    print("[NPC Flare Throw] Use 'npc_flare_throw_*' convars to configure.")
end)
