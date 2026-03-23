-- ============================================================
--  NPC Smoke Throw  |  npc_smoke_throw.lua
--  Server-side only.
--
--  Combine soldiers, metrocops, and elites periodically have a
--  chance to lob a smoke grenade (entity: cup_smoke_maniac)
--  toward the player they are targeting.
--
--  Animation and delay logic mirrors npc_molotov_throw.lua:
--  the throw gesture plays immediately, the grenade spawns
--  exactly 1 second later to match the animation release point.
--
--  Requires: the cup_smoke_maniac entity to be registered.
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled    = CreateConVar("npc_smoke_throw_enabled",    "1",    SHARED_FLAGS, "Enable/disable NPC smoke grenade throws.")
local cv_chance     = CreateConVar("npc_smoke_throw_chance",     "0.20", SHARED_FLAGS, "Probability (0–1) that an eligible NPC throws a smoke grenade each check.")
local cv_interval   = CreateConVar("npc_smoke_throw_interval",   "8",    SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown   = CreateConVar("npc_smoke_throw_cooldown",   "18",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed      = CreateConVar("npc_smoke_throw_speed",      "700",  SHARED_FLAGS, "Launch speed of the smoke grenade (units/s).")
local cv_arc        = CreateConVar("npc_smoke_throw_arc",        "0.25", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob).")
local cv_spawn_dist = CreateConVar("npc_smoke_throw_spawn_dist", "52",   SHARED_FLAGS, "Forward distance from NPC origin to spawn grenade (avoids self-collision).")
local cv_max_dist   = CreateConVar("npc_smoke_throw_max_dist",   "2200", SHARED_FLAGS, "Max distance to player for a throw to be attempted.")
local cv_min_dist   = CreateConVar("npc_smoke_throw_min_dist",   "120",  SHARED_FLAGS, "Min distance to player (no throw if closer than this).")
local cv_spin       = CreateConVar("npc_smoke_throw_spin",       "1",    SHARED_FLAGS, "Apply a random spin impulse to the grenade (1 = enabled).")
local cv_announce   = CreateConVar("npc_smoke_throw_announce",   "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC throws.")

-- ============================================================
--  NPC whitelist
-- ============================================================

local SMOKE_THROWERS = {
    ["npc_combine_s"]     = true,   -- Combine Soldier
    ["npc_metropolice"]   = true,   -- Metrocop
    ["npc_combine_elite"] = true,   -- Combine Elite
}

local function IsEligibleThrower(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return SMOKE_THROWERS[npc:GetClass()] == true
end

-- ============================================================
--  Helpers
-- ============================================================

--- Calculates launch velocity to lob from 'from' toward 'to'.
local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir        = (to - from)
    local horizontal = Vector(dir.x, dir.y, 0)
    local dist       = horizontal:Length()

    if dist < 1 then dist = 1 end
    horizontal:Normalize()

    local velH = horizontal * speed
    local velZ = dist * arcFactor + (to.z - from.z) * 0.3
    velZ = math.Clamp(velZ, -speed * 0.5, speed * 0.8)

    return Vector(velH.x, velH.y, velZ)
end

-- ============================================================
--  Core throw function
-- ============================================================

--- Triggers the throw animation immediately, then spawns and
--- launches cup_smoke_maniac exactly 1 second later.
---@param npc Entity  The throwing NPC.
---@param target Entity  The target (player).
---@return boolean  true on success, false on failure.
local function ThrowSmoke(npc, target)

    -- --------------------------------------------------------
    --  STEP 1 (immediate): play the throw animation gesture.
    --  The projectile is spawned 1 second later in STEP 2 so
    --  that the release point of the animation lines up with
    --  the moment the grenade actually leaves the NPC's hand.
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
    npc.__smoke_lastThrow = CurTime()

    -- Snapshot distance for the optional announce log.
    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    -- --------------------------------------------------------
    --  STEP 2 (1 second later): spawn and launch the grenade.
    --  Target position is re-evaluated at launch time so the
    --  aim reflects where the player actually is.
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

        -- Create the smoke grenade entity.
        local smoke = ents.Create("cup_smoke_maniac")
        if not IsValid(smoke) then
            if cv_announce:GetBool() then
                print("[NPC Smoke Throw] ERROR: cup_smoke_maniac entity could not be created. Is the required addon installed?")
            end
            return
        end

        local eyeAng = toTarget:Angle()
        local right  = eyeAng:Right()
        local up     = eyeAng:Up()

        smoke:SetPos(spawnPos + right * 6 + up * -2)
        smoke:SetAngles(npc:GetAngles() + Angle(-90, 0, 0))

        smoke:SetOwner(npc)
        smoke.Owner     = npc
        smoke.Inflictor = npc

        smoke:Spawn()
        smoke:Activate()

        -- Apply physics impulse after spawn.
        local phys = smoke:GetPhysicsObject()
        if IsValid(phys) then
            local speed = cv_speed:GetFloat()
            local vel   = CalcLaunchVelocity(spawnPos, targetPos, speed, cv_arc:GetFloat())
            phys:SetVelocity(vel)

            -- Optional random spin for natural tumbling in flight.
            if cv_spin:GetBool() then
                local spin   = vel:GetNormalized() * math.random(5, 10)
                local offset = smoke:LocalToWorld(smoke:OBBCenter())
                             + Vector(0, 0, math.random(10, 15))
                phys:ApplyForceOffset(spin, offset)
            end

            phys:Wake()
        end

        if cv_announce:GetBool() then
            print(string.format("[NPC Smoke Throw] %s threw a smoke grenade at %s (dist at trigger: %.0f)",
                npc:GetClass(), target:Nick(), distAtTrigger))
        end

    end)  -- end timer.Simple

    return true
end

-- ============================================================
--  Per-NPC state initialisation (lazy)
-- ============================================================

local function InitNPCState(npc)
    if not IsValid(npc) then return end
    if npc.__smoke_hooked then return end
    npc.__smoke_hooked    = true
    npc.__smoke_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__smoke_lastThrow = 0
end

-- ============================================================
--  Main Think loop  (timer-based, avoids per-frame iteration)
-- ============================================================

timer.Create("NPCSmokeThrow_Think", 0.5, 0, function()
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
        if now < (npc.__smoke_nextCheck or 0) then continue end
        npc.__smoke_nextCheck = now + interval + math.Rand(-1, 1)

        -- Cooldown gate
        if now - (npc.__smoke_lastThrow or 0) < cooldown then continue end

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
        ThrowSmoke(npc, enemy)
    end
end)

-- ============================================================
--  Startup message
-- ============================================================

hook.Add("InitPostEntity", "NPCSmokeThrow_Init", function()
    print("[NPC Smoke Throw] Addon loaded.")
    print("[NPC Smoke Throw] Use 'npc_smoke_throw_*' convars to configure.")
    print("[NPC Smoke Throw] Requires the cup_smoke_maniac entity.")
end)
