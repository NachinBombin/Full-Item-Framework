-- ============================================================
--  NPC Crossbow Bolt Throw  |  npc_crossbow_throw.lua
--  Server-side only.
--
--  Enemy NPCs periodically have a chance to fire a crossbow bolt
--  (entity: obj_vj_crossbowbolt) toward the player they are
--  targeting.  The bolt is a fast, low-arc projectile – it will
--  not always hit the player; that is intentional.
-- ============================================================

if CLIENT then return end

-- ============================================================
--  ConVars  (FCVAR_REPLICATED = editable from the Options menu)
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled    = CreateConVar("npc_crossbow_throw_enabled",     "1",    SHARED_FLAGS, "Enable/disable NPC crossbow bolt throws.")
local cv_chance     = CreateConVar("npc_crossbow_throw_chance",      "0.20", SHARED_FLAGS, "Probability (0–1) that an eligible NPC fires a bolt each check.")
local cv_interval   = CreateConVar("npc_crossbow_throw_interval",    "7",    SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown   = CreateConVar("npc_crossbow_throw_cooldown",    "14",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed      = CreateConVar("npc_crossbow_throw_speed",       "1800", SHARED_FLAGS, "Launch speed of the bolt (units/s). Bolts are fast and flat.")
local cv_arc        = CreateConVar("npc_crossbow_throw_arc",         "0.05", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob).")
local cv_spawn_dist = CreateConVar("npc_crossbow_throw_spawn_dist",  "56",   SHARED_FLAGS, "Forward offset from NPC eye to spawn point (avoids self-collision).")
local cv_max_dist   = CreateConVar("npc_crossbow_throw_max_dist",    "3000", SHARED_FLAGS, "Max distance to player for a bolt to be fired.")
local cv_min_dist   = CreateConVar("npc_crossbow_throw_min_dist",    "120",  SHARED_FLAGS, "Min distance to player (no bolt if closer than this).")

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

--- Returns true if the NPC is an active enemy toward players.
local function IsEnemyNPC(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    local ply = GetAnyPlayer()
    -- No players on the server yet – nothing to be an enemy of
    if not ply then return false end
    local disp = npc:Disposition(ply)
    if disp == D_HT or disp == D_FR then return true end
    if npc:GetClass():sub(1, 4) == "npc_" and disp ~= D_LI and disp ~= D_NU then
        return true
    end
    return false
end

--- Calculates launch velocity: fast and flat for a bolt, with a tiny arc.
local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir        = to - from
    local horizontal = Vector(dir.x, dir.y, 0)
    local dist       = math.max(horizontal:Length(), 1)

    horizontal:Normalize()
    local velH = horizontal * speed

    -- Very small upward component – bolts travel in near-straight lines
    local velZ = dist * arcFactor + (to.z - from.z) * 0.35
    velZ = math.Clamp(velZ, -speed * 0.4, speed * 0.4)

    return Vector(velH.x, velH.y, velZ)
end

--- Spawns and launches a crossbow bolt from the NPC toward the target.
local function FireBolt(npc, target)
    -- Aim for centre-mass of the target
    local targetPos = target:GetPos() + Vector(0, 0, 28)
    local npcEyePos = npc:EyePos()
    local toTarget  = (targetPos - npcEyePos):GetNormalized()

    -- Offset spawn forward from the NPC so it clears the hull
    local spawnDist = cv_spawn_dist:GetFloat()
    local spawnPos  = npcEyePos + toTarget * spawnDist

    -- Pull back if solid brush is in the way
    local tr = util.TraceLine({
        start  = npcEyePos,
        endpos = spawnPos,
        filter = { npc },
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then
        spawnPos = npcEyePos + toTarget * (tr.Fraction * spawnDist * 0.85)
    end

    -- Create the bolt entity
    local bolt = ents.Create("obj_vj_crossbowbolt")
    if not IsValid(bolt) then return false end

    bolt:SetPos(spawnPos)
    bolt:SetAngles(toTarget:Angle())

    -- Tag the NPC as the owner so the bolt's damage system knows who fired it
    bolt:SetOwner(npc)

    bolt:Spawn()
    bolt:Activate()

    -- Apply velocity via physics object
    local phys = bolt:GetPhysicsObject()
    if IsValid(phys) then
        local vel = CalcLaunchVelocity(spawnPos, targetPos, cv_speed:GetFloat(), cv_arc:GetFloat())
        phys:SetVelocity(vel)
        -- Kill rotation so it doesn't tumble like a thrown object
        phys:SetAngleVelocity(Vector(0, 0, 0))
        phys:Wake()
    else
        if bolt.SetVelocity then
            local vel = CalcLaunchVelocity(spawnPos, targetPos, cv_speed:GetFloat(), cv_arc:GetFloat())
            bolt:SetVelocity(vel)
        end
    end

    npc.__cbolt_lastFire = CurTime()
    return true
end

-- ============================================================
--  Per-NPC lazy state init
-- ============================================================
local function InitNPCState(npc)
    if npc.__cbolt_hooked then return end
    npc.__cbolt_hooked    = true
    npc.__cbolt_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__cbolt_lastFire  = 0
end

-- ============================================================
--  Main loop  (runs every 0.5 s – not every frame)
-- ============================================================
timer.Create("NPCCrossbowThrow_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now      = CurTime()
    local interval = cv_interval:GetFloat()
    local cooldown = cv_cooldown:GetFloat()
    local chance   = cv_chance:GetFloat()
    local maxDist  = cv_max_dist:GetFloat()
    local minDist  = cv_min_dist:GetFloat()

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not IsEnemyNPC(npc)                  then continue end

        InitNPCState(npc)

        -- Time-gate per NPC
        if now < (npc.__cbolt_nextCheck or 0) then continue end
        npc.__cbolt_nextCheck = now + interval + math.Rand(-1.5, 1.5)

        -- Cooldown per NPC
        if now - (npc.__cbolt_lastFire or 0) < cooldown then continue end

        -- Must be alive and have a player enemy
        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end

        -- Distance gate
        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check (bolts need clear air)
        local tr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        -- Bolts require a cleaner LOS than thrown flares
        if tr.Entity ~= enemy and tr.Fraction < 0.92 then continue end

        -- Probability roll
        if math.random() > chance then continue end

        FireBolt(npc, enemy)
    end
end)

-- ============================================================
--  Init message
-- ============================================================
hook.Add("InitPostEntity", "NPCCrossbowThrow_Init", function()
    print("[NPC Crossbow Bolt Throw] Addon loaded.")
    print("[NPC Crossbow Bolt Throw] Use 'npc_crossbow_throw_*' convars to configure.")
end)
