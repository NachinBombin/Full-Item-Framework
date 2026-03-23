-- ============================================================
--  NPC Electric Wire Missile Throw  |  npc_electric_missile_throw_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu, same as NPC Stun Gas Throw.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

hook.Add("AddToolMenuCategories", "NPCElectricMissileThrow_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

hook.Add("PopulateToolMenu", "NPCElectricMissileThrow_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",
        ADDON_CATEGORY,
        "npc_electric_missile_throw_settings",
        "NPC Electric Missile Throw",
        "",
        "",
        function(panel)

            panel:ClearControls()

            -- ------------------------------------------------
            --  Header
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "NPC Electric Wire Missile Throw Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Electric Missile Throws", "npc_electric_missile_throw_enabled")
            panel:ControlHelp("  Master on/off switch for this addon.")

            panel:CheckBox("Debug Announce in Console", "npc_electric_missile_throw_announce")
            panel:ControlHelp("  Print a console message every time an NPC throws.")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Probability & Timing
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Throw Chance",
                "npc_electric_missile_throw_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 - 1.00) that an eligible NPC throws\n  an electric missile each time it is checked.  Default: 0.20")

            panel:NumSlider("Check Interval (seconds)",
                "npc_electric_missile_throw_interval", 1, 30, 0)
            panel:ControlHelp("  How many seconds between throw-eligibility checks\n  for each individual NPC.  Default: 10")

            panel:NumSlider("Throw Cooldown (seconds)",
                "npc_electric_missile_throw_cooldown", 1, 60, 0)
            panel:ControlHelp("  Minimum seconds that must pass between throws\n  for the same NPC.  Default: 24")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Projectile Behaviour
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Projectile Behaviour",
                Height      = "30",
            })

            panel:NumSlider("Launch Speed (units/s)",
                "npc_electric_missile_throw_speed", 200, 2000, 0)
            panel:ControlHelp("  How fast the electric missile is thrown.\n  Default: 1100 (higher than stun gas for safer distance).")

            panel:NumSlider("Arc Factor",
                "npc_electric_missile_throw_arc", 0, 1, 2)
            panel:ControlHelp("  Upward lob strength.\n  0.00 = nearly flat,  1.00 = very high arc.\n  Default: 0.45 (more arc than stun gas).")

            panel:NumSlider("Spawn Offset (units)",
                "npc_electric_missile_throw_spawn_dist", 20, 150, 0)
            panel:ControlHelp("  Forward distance from the NPC's eye to where the\n  missile spawns.  Increase if you see self-collision.\n  Default: 80")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Engagement Range
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_electric_missile_throw_max_dist", 400, 8000, 0)
            panel:ControlHelp("  NPCs will not throw if the player is farther than\n  this many units away.  Default: 2800")

            panel:NumSlider("Min Distance",
                "npc_electric_missile_throw_min_dist", 0, 800, 0)
            panel:ControlHelp("  NPCs will not throw if the player is closer than\n  this many units (too close to lob).  Default: 200")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp("  Missiles have a 4-second safe rope-only phase\n  before electrifying the cable and spawning orbs.\n  Changes take effect immediately.")

        end
    )
end)
