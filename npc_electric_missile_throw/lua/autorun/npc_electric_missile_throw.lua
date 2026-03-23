-- ============================================================
--  NPC Electric Wire Missile Throw  |  npc_electric_missile_throw.lua
--  SERVER-side NPC logic.
--
--  Enemy NPCs periodically lob a wire-guided electric missile
--  (wire_electric_missile SENT) toward the player they are
--  targeting. The missile itself handles:
--    - 4 seconds of safe rope-only phase (no damage, no VFX)
--    - then full-area electric suppression & orbs, etc.
--
--  This file only controls:
--    - Which NPCs are allowed to throw
--    - How often they consider throwing
--    - How strong / high the throw arc is
--
--  Menu UI is provided by:
--    lua/autorun/client/npc_electric_missile_throw_menu.lua
--    under Options → "Bombin Addons".
-- ============================================================

if CLIENT then return end

AddCSLuaFile()

-- ============================================================
--  Shared constants / helpers
-- ============================================================

local MISSILE_CLASS = "wire_electric_missile"

local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- ConVars (mirroring the stun gas structure, but with beefier defaults)
local cv_enabled    = CreateConVar("npc_electric_missile_throw_enabled",    "1",    SHARED_FLAGS, "Enable/disable NPC electric missile throws.")
local cv_chance     = CreateConVar("npc_electric_missile_throw_chance",     "0.20", SHARED_FLAGS, "Probability (0-1) that an eligible NPC throws an electric missile each check.")
local cv_interval   = CreateConVar("npc_electric_missile_throw_interval",   "10",   SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown   = CreateConVar("npc_electric_missile_throw_cooldown",   "24",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed      = CreateConVar("npc_electric_missile_throw_speed",      "1100", SHARED_FLAGS, "Launch speed of the electric missile (units/s). Default higher than stun gas for safer distance.")
local cv_arc        = CreateConVar("npc_electric_missile_throw_arc",        "0.45", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob). Default higher than stun gas (0.25).")
local cv_spawn_dist = CreateConVar("npc_electric_missile_throw_spawn_dist", "80",   SHARED_FLAGS, "Forward distance from NPC eye to spawn the missile (avoids self-collision).")
local cv_max_dist   = CreateConVar("npc_electric_missile_throw_max_dist",   "2800", SHARED_FLAGS, "Max distance to player for a throw to be attempted.")
local cv_min_dist   = CreateConVar("npc_electric_missile_throw_min_dist",   "200",  SHARED_FLAGS, "Min distance to player (no throw if closer than this).")
local cv_announce   = CreateConVar("npc_electric_missile_throw_announce",   "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC throws.")

-- Same eligible thrower set as stun gas addon
local ELECTRIC_MISSILE_THROWERS = {
    ["npc_combine_s"]     = true,
    ["npc_metropolice"]   = true,
    ["npc_combine_elite"] = true,
}

local function IsEligibleThrower(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return ELECTRIC_MISSILE_THROWERS[npc:GetClass()] == true
end

-- Reuses the same style of arc calculation as stun gas, but with
-- higher default arc factor and speed for longer, safer lobs.[cite:137]
local function CalcLaunchVelocity(from, to, speed, arcFactor)
    local dir        = (to - from)
    local horizontal = Vector(dir.x, dir.y, 0)
    local dist       = horizontal:Length()
    if dist < 1 then dist = 1 end

    horizontal:Normalize()

    local velH = horizontal * speed
    local velZ = dist * arcFactor + (to.z - from.z) * 0.3
    velZ = math.Clamp(velZ, -speed * 0.5, speed * 0.9)

    return Vector(velH.x, velH.y, velZ)
end

-- ============================================================
--  Throw logic (adapted from ThrowStunGas, but spawning SENT)
-- ============================================================

local function ThrowElectricMissile(npc, target)
    -- Play the same throw gesture style as the stun gas addon
    do
        local gestureAct  = ACT_GESTURE_RANGE_ATTACK_THROW
        local fallbackAct = ACT_RANGE_ATTACK_THROW
        local seq = npc:SelectWeightedSequence(gestureAct)
        if seq <= 0 then
            seq = npc:SelectWeightedSequence(fallbackAct)
            if seq > 0 then gestureAct = fallbackAct end
        end
        if seq > 0 then npc:AddGesture(gestureAct) end
    end

    npc.__elec_missile_lastThrow = CurTime()
    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    -- Delay spawn to sync roughly with the end of the throw gesture
    timer.Simple(1, function()
        if not IsValid(npc) or not IsValid(target) then return end

        local targetPos = target:GetPos() + Vector(0, 0, 36)
        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()
        local spawnDist = cv_spawn_dist:GetFloat()
        local spawnPos  = npcEyePos + toTarget * spawnDist

        -- Avoid spawning inside walls or the NPC itself, same pattern as stun gas.[cite:137]
        local tr = util.TraceLine({
            start  = npcEyePos,
            endpos = spawnPos,
            filter = { npc },
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            spawnPos = npcEyePos + toTarget * (tr.Fraction * spawnDist * 0.85)
        end

        -- Create the missile instead of a prop vial
        local missile = ents.Create(MISSILE_CLASS)
        if not IsValid(missile) then return end

        missile:SetPos(spawnPos)
        missile:SetAngles(toTarget:Angle())
        missile:SetOwner(npc)
        missile:Spawn()
        missile:Activate()

        -- Let the missile's own init know it's being thrown by an NPC (optional)
        if missile.SetThrower then
            missile:SetThrower(npc)
        end

        -- Override its physics velocity to follow our arc
        local phys = missile:GetPhysicsObject()
        if IsValid(phys) then
            local speed = cv_speed:GetFloat()
            local vel   = CalcLaunchVelocity(spawnPos, targetPos, speed, cv_arc:GetFloat())
            phys:SetVelocity(vel)
            phys:Wake()
        end

        if cv_announce:GetBool() then
            print(string.format(
                "[NPC Electric Missile Throw] %s threw at %s (dist: %.0f)",
                npc:GetClass(),
                target:IsPlayer() and target:Nick() or tostring(target),
                distAtTrigger
            ))
        end
    end)

    return true
end

-- ============================================================
--  Per-NPC state initialisation (lazy)
-- ============================================================

local function InitNPCState(npc)
    if not IsValid(npc) then return end
    if npc.__elec_missile_hooked then return end

    npc.__elec_missile_hooked    = true
    npc.__elec_missile_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__elec_missile_lastThrow = 0
end

-- ============================================================
--  Main Think loop (mirrors stun gas addon, new cvars)
-- ============================================================

timer.Create("NPCElectricMissileThrow_Think", 0.5, 0, function()
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

        InitNPCState(npc)

        if now < (npc.__elec_missile_nextCheck or 0) then continue end
        npc.__elec_missile_nextCheck = now + interval + math.Rand(-1, 1)

        if now - (npc.__elec_missile_lastThrow or 0) < cooldown then continue end

        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- LOS check, same style as stun gas addon.[cite:137]
        local losTr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if losTr.Entity ~= enemy and losTr.Fraction < 0.85 then continue end

        if math.random() > chance then continue end

        ThrowElectricMissile(npc, enemy)
    end
end)

-- ============================================================
--  Startup message
-- ============================================================

hook.Add("InitPostEntity", "NPCElectricMissileThrow_Init", function()
    print("[NPC Electric Missile Throw] Addon loaded.")
    print("[NPC Electric Missile Throw] Use 'npc_electric_missile_throw_*' convars to configure.")
    print("[NPC Electric Missile Throw] Missiles respect their own 4s safe phase and orb limits.")
end)
