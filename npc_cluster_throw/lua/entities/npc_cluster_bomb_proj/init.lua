-- ============================================================
--  npc_cluster_bomb_proj  |  init.lua
--  Server-side entity logic.
--
--  A glass bottle packed with armed frag grenades.  Thrown by
--  NPC Cluster Throw (npc_cluster_throw.lua).  On physics impact
--  or hard-fuse expiry the bottle shatters and releases a
--  randomised spread of npc_grenade_frag sub-munitions.
-- ============================================================

AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  Initialize
-- ============================================================
function ENT:Initialize()
    self:SetModel( "models/props_junk/glassjug01.mdl" )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_WEAPON )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then
        phys:Wake()
        phys:SetMass( 1.5 )
    end

    -- GrenadeCount is baked in by the throw script before Spawn() is
    -- called.  The block below is a safe fallback only.
    if not self.GrenadeCount or self.GrenadeCount < 1 then
        local gMin = math.max( 1, GetConVar( "npc_cluster_throw_grenade_min" ):GetInt() )
        local gMax = math.max( gMin, GetConVar( "npc_cluster_throw_grenade_max" ):GetInt() )
        self.GrenadeCount = math.random( gMin, gMax )
    end

    self._shattered = false
    self.Detonated  = false
    self.Armed      = false

    -- Arm after 0.25 s so the bottle clears the NPC before collisions trigger.
    timer.Simple( 0.25, function()
        if IsValid( self ) then self.Armed = true end
    end )

    -- Hard fuse: guarantees detonation even if PhysicsCollide never fires
    -- (e.g. the bottle rolls to rest in soft geometry).
    local fuseTime = math.max( 0.5, GetConVar( "npc_cluster_throw_fuse" ):GetFloat() )
    timer.Simple( fuseTime, function()
        if IsValid( self ) and not self._shattered then
            self:Shatter( nil )
        end
    end )
end

-- ============================================================
--  PhysicsCollide  – queue a shatter on the next tick
-- ============================================================
function ENT:PhysicsCollide( data, phys )
    if not self.Armed      then return end
    if self._shattered     then return end
    if data.Speed < 40     then return end

    -- Flag immediately to block any re-entrant PhysicsCollide calls
    -- that fire before the timer executes.
    self._shattered = true
    self.Detonated  = true

    -- Snapshot position NOW, inside the callback, before the physics
    -- step moves the entity further.
    local snapPos = self:GetPos()

    -- Defer ALL entity work to the next game tick.
    -- Spawning NPCs or changing collision groups inside a physics
    -- callback is the direct cause of the CTD and the collision-rules
    -- warnings.  timer.Simple(0) exits the callback cleanly first.
    timer.Simple( 0, function()
        if IsValid( self ) then
            self:Shatter( snapPos )
        end
    end )
end

-- ============================================================
--  Shatter
-- ============================================================
-- snapPos: position captured before the tick boundary (PhysicsCollide
--          path).  nil on the hard-fuse path; self:GetPos() is used
--          instead, which is safe because no deferral happened.
function ENT:Shatter( snapPos )
    -- Double-entry guard.  _shattered may already be true on the
    -- PhysicsCollide path (set before the timer); on the fuse path
    -- this function sets it itself.
    if self._shattered and snapPos == nil then
        -- Hard-fuse path: _shattered not yet set by this function.
        -- Fall through and set it now.
    elseif self._shattered and snapPos ~= nil then
        -- PhysicsCollide already set _shattered; this is the deferred
        -- execution we scheduled.  Proceed normally.
    end
    self._shattered = true
    self.Detonated  = true

    local origin = snapPos or self:GetPos()

    -- ── Glass shatter effect ─────────────────────────────────────
    local ed = EffectData()
    ed:SetOrigin( origin )
    ed:SetAngles( self:GetAngles() )
    ed:SetScale( 1.2 )
    ed:SetMagnitude( 80 )
    ed:SetRadius( 12 )
    util.Effect( "GlassImpact", ed )

    -- Use a world-position sound so it is NOT cut short when the
    -- entity is removed immediately after this call.
    local glassSounds = {
        "physics/glass/glass_bottle_break1.wav",
        "physics/glass/glass_bottle_break2.wav",
    }
    sound.Play(
        glassSounds[ math.random( #glassSounds ) ],
        origin,
        90,
        math.random( 95, 110 ),
        1.0
    )

    -- ── Schedule staggered sub-munition spawns ───────────────────
    self:ScheduleGrenades( origin )

    -- Remove the bottle casing now that effects and scheduling are done.
    self:Remove()
end

-- ============================================================
--  ScheduleGrenades
--  Pre-computes ALL grenade positions and velocities in this
--  frame, then spawns each grenade on its own separate game tick
--  (50 ms apart).  Spawning multiple NPCs in a single frame at
--  the same world position causes physics-solver conflicts and
--  is the primary source of crash-to-desktop errors.
-- ============================================================
function ENT:ScheduleGrenades( origin )
    local count = self.GrenadeCount
    if not count or count < 1 then return end

    local thrower = self.ThrowerNPC   -- capture before Remove()

    local hSpeedMin = GetConVar( "npc_cluster_throw_launch_h_min" ):GetFloat()
    local hSpeedMax = GetConVar( "npc_cluster_throw_launch_h_max" ):GetFloat()
    local vSpeedMin = GetConVar( "npc_cluster_throw_launch_v_min" ):GetFloat()
    local vSpeedMax = GetConVar( "npc_cluster_throw_launch_v_max" ):GetFloat()
    local subFuse   = GetConVar( "npc_cluster_throw_sub_fuse" ):GetFloat()

    local yawStep = 360 / count

    -- Pre-build a table of { pos, vel, fuse } for every grenade so
    -- all randomisation happens now (in a safe, non-callback context)
    -- before the staggered timers fire.
    local grenadeJobs = {}
    for i = 1, count do
        local yaw = ( yawStep * ( i - 1 ) ) + math.random( -18, 18 )
        local dir = Vector(
            math.cos( math.rad( yaw ) ),
            math.sin( math.rad( yaw ) ),
            0
        )

        local hSpeed = math.Remap( math.random(), 0, 1, hSpeedMin, hSpeedMax )
        local vSpeed = math.Remap( math.random(), 0, 1, vSpeedMin, vSpeedMax )

        -- Offset each spawn position along its own launch direction so
        -- no two grenades share the exact same world position.  This
        -- prevents the physics solver from seeing overlapping bounding
        -- boxes on multiple NPCs, which is a direct crash trigger.
        local spawnPos = origin + Vector( 0, 0, 32 ) + dir * 8

        grenadeJobs[ i ] = {
            pos  = spawnPos,
            vel  = ( dir * hSpeed ) + Vector( 0, 0, vSpeed ),
            fuse = subFuse + math.random( -5, 5 ) * 0.05,   -- ±0.25 s jitter
            spin = Vector(
                math.random( -220, 220 ),
                math.random( -220, 220 ),
                math.random( -220, 220 )
            ),
        }
    end

    -- Spawn one grenade per tick, 50 ms apart.
    for i, job in ipairs( grenadeJobs ) do
        local delay = ( i - 1 ) * 0.05   -- 0 ms, 50 ms, 100 ms, …

        timer.Simple( delay, function()

            local grenade = ents.Create( "npc_grenade_frag" )
            if not IsValid( grenade ) then return end

            grenade:SetPos( job.pos )
            grenade:SetAngles( Angle( 0, math.random( 0, 360 ), 0 ) )

            if IsValid( thrower ) then
                grenade:SetOwner( thrower )
            end

            grenade:Spawn()
            grenade:Activate()

            -- Set fuse via input.  npc_grenade_frag responds to
            -- "SetTimer" to configure its countdown.
            grenade:Fire( "SetTimer", tostring( job.fuse ) )

            -- Apply velocity and tumble on the next tick after Spawn so
            -- the physics object is guaranteed to be fully initialised.
            timer.Simple( 0, function()
                if not IsValid( grenade ) then return end
                local phys = grenade:GetPhysicsObject()
                if not IsValid( phys ) then return end
                phys:Wake()
                phys:SetVelocity( job.vel )
                phys:SetAngleVelocity( job.spin )
            end )

        end )
    end
end

-- ============================================================
--  OnTakeDamage  – sympathetic shatter if shot
-- ============================================================
function ENT:OnTakeDamage( dmginfo )
    if self._shattered then return end
    self._accDmg = ( self._accDmg or 0 ) + dmginfo:GetDamage()
    if self._accDmg < 20 then return end

    self._shattered = true
    self.Detonated  = true
    local pos = self:GetPos()

    -- Defer for the same reason as PhysicsCollide: damage callbacks
    -- can fire during physics resolution.
    timer.Simple( 0, function()
        if IsValid( self ) then self:Shatter( pos ) end
    end )
end
