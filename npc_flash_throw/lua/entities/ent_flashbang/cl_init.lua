-- ============================================================
--  Flashbang Grenade  |  cl_init.lua
--  Client-side: visual post-flash effects.
--
--  Timeline (point-blank, falloff = 1.0):
--    White ScreenFade  : 0 – 6s   (server-driven, unchanged)
--    Screen breathing  : 0 – 10s  (HUDPaint)
--    Blur + audio      : driven entirely by ShellShock mod
--                        via ply.InShock for the falloff duration
--
--  ShellShock compatibility:
--    We set ply.InShock = true for a falloff-scaled duration.
--    ShellShock's RenderScreenspaceEffects hook reads that flag
--    every frame and handles DrawMotionBlur, DrawColorModify,
--    mouse sensitivity reduction, and Shell_Loop.wav audio.
--    If ShellShock is not installed, those effects simply won't
--    play — everything else still works independently.
-- ============================================================

include("shared.lua")

-- ============================================================
--  Effect state
-- ============================================================

local fx = nil  -- active effect table, nil when nothing playing

-- ============================================================
--  Net receive
-- ============================================================

net.Receive("FlashbangDetonate", function()
    local pos   = net.ReadVector()
    local range = net.ReadFloat()

    -- --------------------------------------------------------
    --  DynamicLight — cosmetic world flash, everyone sees it
    -- --------------------------------------------------------
    local dlight = DynamicLight(32768 + math.random(0, 1000))
    if dlight then
        dlight.pos        = pos
        dlight.dieTime    = CurTime() + 0.35
        dlight.decay      = 3000
        dlight.size       = range
        dlight.brightness = 12
        dlight.r          = 255
        dlight.g          = 255
        dlight.b          = 255
    end

    -- --------------------------------------------------------
    --  LOS + distance gate — mirrors server logic exactly
    -- --------------------------------------------------------
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local dist = pos:Distance(ply:GetPos())
    if dist > range then return end

    local tr = util.TraceLine({
        start  = pos,
        endpos = ply:EyePos(),
        filter = ply,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then return end

    -- --------------------------------------------------------
    --  Falloff  (1.0 = point blank, approaches 0 at max range)
    -- --------------------------------------------------------
    local falloff = 1 - (dist / range)

    local shockDuration  = math.max(falloff * 14.0, 2.0)
    local breatheDuration = math.max(falloff * 10.0, 1.5)

    fx = {
        startTime       = CurTime(),
        breatheDuration = breatheDuration,
        falloff         = falloff,
    }

    -- --------------------------------------------------------
    --  ShellShock integration
    --  Setting ply.InShock = true hands control to ShellShock's
    --  hook which drives blur, colour drain, mouse sensitivity
    --  reduction and the shell loop sound automatically.
    --  We clear the flag after shockDuration seconds.
    -- --------------------------------------------------------
    ply.InShock = true
    timer.Create("FlashbangShock_" .. ply:EntIndex(), shockDuration, 1, function()
        if IsValid(ply) then
            ply.InShock = false
        end
    end)
end)

-- ============================================================
--  Screen Breathing
--  A sine-wave white overlay that pulses as the player recovers.
--  Runs in HUDPaint — the correct hook for surface draws.
-- ============================================================

hook.Add("HUDPaint", "FlashbangBreathe", function()
    if not fx then return end

    local elapsed = CurTime() - fx.startTime

    if elapsed >= fx.breatheDuration then
        fx = nil
        return
    end

    local progress  = elapsed / fx.breatheDuration
    local intensity = fx.falloff * (1 - progress)

    -- Sine wave: ~1.5 pulses per second
    local breathe = math.sin(elapsed * 9.5) * 0.5 + 0.5

    -- Peak alpha of 180 at point blank
    local alpha = math.floor(breathe * intensity * 180)

    surface.SetDrawColor(255, 255, 255, alpha)
    surface.DrawRect(0, 0, ScrW(), ScrH())
end)
