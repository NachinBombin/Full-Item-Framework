-- ============================================================
--  Flashbang Grenade  |  init.lua
--  Server-side logic: physics, ground detection, detonation,
--  player blinding with LOS and distance falloff.
-- ============================================================

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

util.AddNetworkString("FlashbangDetonate")

function ENT:Initialize()
    self:SetModel("models/weapons/w_eq_flashbang.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(0.3)
    end

    self._HasHitGround = false
    self._HasDetonated = false
    self._FuseTimer    = "FlashbangFuse_" .. self:EntIndex()
end
function ENT:OnTakeDamage(dmginfo)
    if self._HasDetonated then return end
    timer.Simple(0.1, function()
        if IsValid(self) then self:Detonate() end
    end)
end
-- PhysicsCollide fires on every physics contact.
-- We only care about the first contact with world geometry.
function ENT:PhysicsCollide(colData, phys)
    if self._HasHitGround then return end

    local hitEnt = colData.HitEntity

    -- IsValid returns false for the world entity in GMod, so we
    -- must check IsWorld() independently rather than gating on IsValid first.
    local hitWorld = IsValid(hitEnt) and hitEnt:IsWorld()
                  or (hitEnt and hitEnt:IsWorld())

    if not hitWorld then return end

    self._HasHitGround = true

    self:EmitSound("weapons/flashbang/grenade_hit1.wav", 70, 100)

    local vel = phys:GetVelocity()
    phys:SetVelocity(vel * self.BOUNCE_DAMPING)

    timer.Simple(self.FUSE_AFTER_IMPACT, function()
        if IsValid(self) then self:Detonate() end
    end)
end

function ENT:Detonate()
    if self._HasDetonated then return end
    self._HasDetonated = true

    local grenadePos = self:GetPos()
    local range      = self.FLASH_RANGE

    self:EmitSound("weapons/flashbang/flashbang_explode2.wav", 150, 100)

    -- Tell every client to render the visual flash
    net.Start("FlashbangDetonate")
        net.WriteVector(grenadePos)
        net.WriteFloat(range)
    net.Broadcast()

    -- Process players only, no NPCs
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end
        if not ply:Alive() then continue end

        local dist = grenadePos:Distance(ply:GetPos())
        if dist > range then continue end

        -- Line of sight: grenade to player eye, world brushes only.
        -- Props and NPCs between the grenade and player are transparent.
        local tr = util.TraceLine({
            start  = grenadePos,
            endpos = ply:EyePos(),
            filter = { self, ply },
            mask   = MASK_SOLID_BRUSHONLY,
        })

        -- A solid hit means a wall blocked the flash
        if tr.Hit then continue end

        -- Linear falloff: full effect at 0 units, nothing at max range
        local falloff      = 1 - (dist / range)
        local fadeDuration = math.max(falloff * self.FLASH_MAX_FADE, 0.3)
        local holdTime     = falloff * self.FLASH_MAX_HOLD

        ply:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 255), fadeDuration, holdTime)
    end

    -- Short delay before removal so the sound can start cleanly
    timer.Simple(0.1, function()
        if IsValid(self) then self:Remove() end
    end)
end

function ENT:OnRemove()
    timer.Remove(self._FuseTimer)
end
