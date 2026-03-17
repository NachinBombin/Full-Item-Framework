-- ============================================================
--  NPC Molotov Throw  |  npc_molotov_throw.lua
--  Server-side only.
--
--  Enemy NPCs periodically have a chance to lob a molotov
--  cocktail (entity: rj_molotov) toward the player they are
--  targeting.  Uses the full rj_molotov entity including all
--  fire/explosion particles and vFire support.
--
--  Requires: Molotov SWEP (rj_molotov entity must be registered)
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars  (FCVAR_REPLICATED = editable from the Options menu
--           on listen servers / singleplayer)
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled      = CreateConVar("npc_molotov_throw_enabled",     "1",    SHARED_FLAGS, "Enable/disable NPC molotov throws.")
local cv_chance       = CreateConVar("npc_molotov_throw_chance",      "0.20", SHARED_FLAGS, "Probability (0–1) that an eligible NPC throws a molotov each check.")
local cv_interval     = CreateConVar("npc_molotov_throw_interval",    "8",    SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown     = CreateConVar("npc_molotov_throw_cooldown",    "18",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed        = CreateConVar("npc_molotov_throw_speed",       "700",  SHARED_FLAGS, "Launch speed of the molotov (units/s).")
local cv_arc          = CreateConVar("npc_molotov_throw_arc",         "0.25", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob).")
local cv_spawn_dist   = CreateConVar("npc_molotov_throw_spawn_dist",  "52",   SHARED_FLAGS, "Forward distance from NPC origin to spawn molotov (avoids self-collision).")
local cv_max_dist     = CreateConVar("npc_molotov_throw_max_dist",    "2200", SHARED_FLAGS, "Max distance to player for a throw to be attempted.")
local cv_min_dist     = CreateConVar("npc_molotov_throw_min_dist",    "120",  SHARED_FLAGS, "Min distance to player (no throw if closer than this).")
local cv_spin         = CreateConVar("npc_molotov_throw_spin",        "1",    SHARED_FLAGS, "Apply a random spin impulse to the bottle (1 = enabled).")
local cv_announce     = CreateConVar("npc_molotov_throw_announce",    "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC throws.")

-- ============================================================
--  Helpers
-- ============================================================


-- Whitelist of NPC classes allowed to throw molotovs.
-- Only Combine soldiers, metrocops, and elites qualify.
local MOLOTOV_THROWERS = {
    ["npc_combine_s"]     = true,   -- Combine Soldier
    ["npc_metropolice"]   = true,   -- Metrocop
    ["npc_combine_elite"] = true,   -- Combine Elite
}

--- Returns true only if the NPC is one of the whitelisted thrower classes.
local function IsEligibleThrower(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return MOLOTOV_THROWERS[npc:GetClass()] == true
end

--- Calculates launch velocity to lob from 'from' toward 'to' with
--- the configured speed and arc. Mirrors the molotov SWEP's throw logic.
local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir        = (to - from)
    local horizontal = Vector(dir.x, dir.y, 0)
    local dist       = horizontal:Length()

    if dist < 1 then dist = 1 end
    horizontal:Normalize()

    local velH = horizontal * speed
    -- Vertical component: distance-based lob + height compensation
    local velZ = dist * arcFactor + (to.z - from.z) * 0.3
    velZ = math.Clamp(velZ, -speed * 0.5, speed * 0.8)

    return Vector(velH.x, velH.y, velZ)
end

--- Spawns and launches an rj_molotov entity from the NPC toward the target.
---@param npc Entity  The throwing NPC.
---@param target Entity  The target (player).
---@return boolean  true on success, false on failure.
local function ThrowMolotov(npc, target)

    -- --------------------------------------------------------
    --  STEP 1 (immediate): play the throw animation gesture.
    --  The projectile is spawned 1 second later in STEP 2 so
    --  that the release point of the animation lines up with
    --  the moment the bottle actually leaves the NPC's hand.
    -- --------------------------------------------------------
    do
        local gestureAct  = ACT_GESTURE_RANGE_ATTACK_THROW
        local fallbackAct = ACT_RANGE_ATTACK_THROW

        local seq = npc:SelectWeightedSequence(gestureAct)
        if seq <= 0 then
            seq = npc:SelectWeightedSequence(fallbackAct)
            if seq > 0 then
                gestureAct = fallbackAct
            end
        end

        if seq > 0 then
            npc:AddGesture(gestureAct)
        end
    end

    -- Stamp the cooldown immediately so the timer loop cannot
    -- queue a second throw while we are waiting for the delay.
    npc.__molotov_lastThrow = CurTime()

    -- Snapshot the distance for the optional announce log.
    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    -- --------------------------------------------------------
    --  STEP 2 (1 second later): spawn and launch the bottle.
    --  Target position is re-evaluated at launch time so the
    --  aim reflects where the player actually is, not where
    --  they were when the animation started.
    -- --------------------------------------------------------
    timer.Simple(1, function()

        -- Abort if either entity was removed during the delay.
        if not IsValid(npc) or not IsValid(target) then return end

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

        -- Create the molotov projectile.
        local molotov = ents.Create("rj_molotov")
        if not IsValid(molotov) then
            if cv_announce:GetBool() then
                print("[NPC Molotov Throw] ERROR: rj_molotov entity could not be created. Is the Molotov SWEP addon installed?")
            end
            return
        end

        local eyeAng = toTarget:Angle()
        local right  = eyeAng:Right()
        local up     = eyeAng:Up()

        molotov:SetPos(spawnPos + right * 6 + up * -2)
        molotov:SetAngles(npc:GetAngles() + Angle(-90, 0, 0))

        molotov:SetOwner(npc)
        molotov.Owner     = npc
        molotov.Inflictor = npc

        local speed = cv_speed:GetFloat()
        molotov.Vel = speed / 2

        molotov:Spawn()
        molotov:Activate()

        local phys = molotov:GetPhysicsObject()
        if IsValid(phys) then
            local vel = CalcLaunchVelocity(spawnPos, targetPos, speed, cv_arc:GetFloat())
            phys:SetVelocity(vel)

            if cv_spin:GetBool() then
                local spin   = vel:GetNormalized() * math.random(5, 10)
                local offset = molotov:LocalToWorld(molotov:OBBCenter())
                             + Vector(0, 0, math.random(10, 15))
                phys:ApplyForceOffset(spin, offset)
            end

            phys:Wake()
        end

        if cv_announce:GetBool() then
            print(string.format("[NPC Molotov Throw] %s threw a molotov at %s (dist at trigger: %.0f)",
                npc:GetClass(), target:Nick(), distAtTrigger))
        end

    end)  -- end timer.Simple

    return true
end

-- ============================================================
--  Per-NPC state initialisation (lazy, called inside the timer)
-- ============================================================

local function InitNPCState(npc)
    if not IsValid(npc) then return end
    if npc.__molotov_hooked then return end
    npc.__molotov_hooked    = true
    npc.__molotov_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__molotov_lastThrow = 0
end

-- ============================================================
--  Main Think loop  (timer-based, avoids per-frame iteration)
-- ============================================================

timer.Create("NPCMolotovThrow_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now      = CurTime()
    local interval = cv_interval:GetFloat()
    local cooldown = cv_cooldown:GetFloat()
    local chance   = cv_chance:GetFloat()
    local maxDist  = cv_max_dist:GetFloat()
    local minDist  = cv_min_dist:GetFloat()

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not IsEligibleThrower(npc) then continue end

        -- Lazy state initialisation
        InitNPCState(npc)

        -- Time gate: only run the full check every `interval` seconds per NPC
        if now < (npc.__molotov_nextCheck or 0) then continue end
        npc.__molotov_nextCheck = now + interval + math.Rand(-1, 1)

        -- Cooldown gate
        if now - (npc.__molotov_lastThrow or 0) < cooldown then continue end

        -- NPC must be alive and actively targeting a player
        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        -- Distance check
        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check – require reasonable visibility
        local losTr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        -- Allow a bit of occlusion (thin walls etc.) but not full cover
        if losTr.Entity ~= enemy and losTr.Fraction < 0.85 then continue end

        -- Probability roll
        if math.random() > chance then continue end

        -- All checks passed – throw!
        ThrowMolotov(npc, enemy)
    end
end)

-- ============================================================
--  Startup message
-- ============================================================

hook.Add("InitPostEntity", "NPCMolotovThrow_Init", function()
    print("[NPC Molotov Throw] Addon loaded.")
    print("[NPC Molotov Throw] Use 'npc_molotov_throw_*' convars to configure.")
    print("[NPC Molotov Throw] Requires the Molotov SWEP addon (rj_molotov).")
end)
