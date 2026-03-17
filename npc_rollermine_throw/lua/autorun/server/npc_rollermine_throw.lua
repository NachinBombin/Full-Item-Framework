-- ============================================================
--  NPC Rollermine Throw  |  npc_rollermine_throw.lua
--  Server-side only.
--
--  Combine soldiers, metrocops, and elites periodically have a
--  chance to lob a rollermine (npc_rollermine) toward the player
--  they are targeting.
--
--  Animation and delay logic mirrors npc_molotov_throw.lua:
--  the throw gesture plays immediately, the rollermine spawns
--  exactly 1 second later to match the animation release point.
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled    = CreateConVar("npc_rollermine_throw_enabled",    "1",    SHARED_FLAGS, "Enable/disable NPC rollermine throws.")
local cv_chance     = CreateConVar("npc_rollermine_throw_chance",     "0.15", SHARED_FLAGS, "Probability (0–1) that an eligible NPC throws a rollermine each check.")
local cv_interval   = CreateConVar("npc_rollermine_throw_interval",   "10",   SHARED_FLAGS, "Seconds between throw-eligibility checks per NPC.")
local cv_cooldown   = CreateConVar("npc_rollermine_throw_cooldown",   "25",   SHARED_FLAGS, "Minimum seconds between throws for the same NPC.")
local cv_speed      = CreateConVar("npc_rollermine_throw_speed",      "600",  SHARED_FLAGS, "Launch speed of the rollermine (units/s).")
local cv_arc        = CreateConVar("npc_rollermine_throw_arc",        "0.30", SHARED_FLAGS, "Upward arc factor (0 = flat, higher = more lob).")
local cv_spawn_dist = CreateConVar("npc_rollermine_throw_spawn_dist", "52",   SHARED_FLAGS, "Forward distance from NPC origin to spawn rollermine (avoids self-collision).")
local cv_max_dist   = CreateConVar("npc_rollermine_throw_max_dist",   "2000", SHARED_FLAGS, "Max distance to player for a throw to be attempted.")
local cv_min_dist   = CreateConVar("npc_rollermine_throw_min_dist",   "150",  SHARED_FLAGS, "Min distance to player (no throw if closer than this).")
local cv_spin       = CreateConVar("npc_rollermine_throw_spin",       "1",    SHARED_FLAGS, "Apply a random spin impulse to the rollermine (1 = enabled).")
local cv_announce   = CreateConVar("npc_rollermine_throw_announce",   "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC throws.")

-- ============================================================
--  NPC whitelist
-- ============================================================

local ROLLERMINE_THROWERS = {
    ["npc_combine_s"]     = true,   -- Combine Soldier
    ["npc_metropolice"]   = true,   -- Metrocop
    ["npc_combine_elite"] = true,   -- Combine Elite
}

local function IsEligibleThrower(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return ROLLERMINE_THROWERS[npc:GetClass()] == true
end

-- ============================================================
--  Helpers
-- ============================================================

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

local function ThrowRollermine(npc, target)

    -- --------------------------------------------------------
    --  STEP 1 (immediate): play the throw gesture.
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

    -- Stamp cooldown immediately so the timer loop cannot queue
    -- a second throw during the 1-second delay window.
    npc.__rollermine_lastThrow = CurTime()

    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    -- --------------------------------------------------------
    --  STEP 2 (1 second later): spawn and launch the rollermine.
    --  Target position is re-evaluated at launch time.
    -- --------------------------------------------------------
    timer.Simple(1, function()

        if not IsValid(npc) or not IsValid(target) then return end

        local targetPos = target:GetPos() + Vector(0, 0, 28)

        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()
        local spawnDist = cv_spawn_dist:GetFloat()
        local spawnPos  = npcEyePos + toTarget * spawnDist

        local tr = util.TraceLine({
            start  = npcEyePos,
            endpos = spawnPos,
            filter = { npc },
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            spawnPos = npcEyePos + toTarget * (tr.Fraction * spawnDist * 0.85)
        end

        local mine = ents.Create("npc_rollermine")
        if not IsValid(mine) then
            if cv_announce:GetBool() then
                print("[NPC Rollermine Throw] ERROR: npc_rollermine could not be created.")
            end
            return
        end

        local eyeAng = toTarget:Angle()
        local right  = eyeAng:Right()
        local up     = eyeAng:Up()

        mine:SetPos(spawnPos + right * 6 + up * -2)
        mine:SetAngles(npc:GetAngles())
        mine:SetOwner(npc)
        mine.Owner = npc

        mine:Spawn()
        mine:Activate()

        local phys = mine:GetPhysicsObject()
        if IsValid(phys) then
            local speed = cv_speed:GetFloat()
            local vel   = CalcLaunchVelocity(spawnPos, targetPos, speed, cv_arc:GetFloat())
            phys:SetVelocity(vel)

            if cv_spin:GetBool() then
                local spin   = vel:GetNormalized() * math.random(5, 10)
                local offset = mine:LocalToWorld(mine:OBBCenter())
                             + Vector(0, 0, math.random(5, 10))
                phys:ApplyForceOffset(spin, offset)
            end

            phys:Wake()
        end

        if cv_announce:GetBool() then
            print(string.format("[NPC Rollermine Throw] %s threw a rollermine at %s (dist at trigger: %.0f)",
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
    if npc.__rollermine_hooked then return end
    npc.__rollermine_hooked    = true
    npc.__rollermine_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__rollermine_lastThrow = 0
end

-- ============================================================
--  Main Think loop
-- ============================================================

timer.Create("NPCRollermineThrow_Think", 0.5, 0, function()
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

        if now < (npc.__rollermine_nextCheck or 0) then continue end
        npc.__rollermine_nextCheck = now + interval + math.Rand(-1, 1)

        if now - (npc.__rollermine_lastThrow or 0) < cooldown then continue end

        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        local losTr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if losTr.Entity ~= enemy and losTr.Fraction < 0.85 then continue end

        if math.random() > chance then continue end

        ThrowRollermine(npc, enemy)
    end
end)

-- ============================================================
--  Startup message
-- ============================================================

hook.Add("InitPostEntity", "NPCRollermineThrow_Init", function()
    print("[NPC Rollermine Throw] Addon loaded.")
    print("[NPC Rollermine Throw] Use 'npc_rollermine_throw_*' convars to configure.")
end)
