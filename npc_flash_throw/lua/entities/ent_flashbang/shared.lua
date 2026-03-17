-- ============================================================
--  Flashbang Grenade  |  shared.lua
--  Shared ENT properties.
-- ============================================================

ENT.Type           = "anim"
ENT.Base           = "base_anim"
ENT.PrintName      = "Flashbang"
ENT.Category       = "Grenades"
ENT.Spawnable      = true
ENT.AdminSpawnable = true

-- Configurable constants (can be overridden before spawning)
ENT.FLASH_RANGE       = 800   -- units
ENT.FLASH_MAX_FADE    = 4.0   -- seconds of screen fade at point blank
ENT.FLASH_MAX_HOLD    = 2.0   -- seconds of solid white at point blank
ENT.FUSE_AFTER_IMPACT = 0.5   -- seconds between ground contact and bang
ENT.BOUNCE_DAMPING    = 0.45  -- velocity kept on bounce (0–1)
