-- ============================================================
--  NPC Clawscanner Throw  |  npc_clawscanner_throw_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

hook.Add("AddToolMenuCategories", "NPCClawscannerThrow_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

hook.Add("PopulateToolMenu", "NPCClawscannerThrow_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",
        ADDON_CATEGORY,
        "npc_clawscanner_throw_settings",
        "NPC Clawscanner Throw",
        "",
        "",
        function(panel)

            panel:ClearControls()

            panel:AddControl("Header", {
                Description = "NPC Clawscanner Throw Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Clawscanner Throws", "npc_clawscanner_throw_enabled")
            panel:ControlHelp("  Master on/off switch for the entire addon.")

            panel:CheckBox("Debug Announce in Console", "npc_clawscanner_throw_announce")
            panel:ControlHelp("  Print a console message every time an NPC throws.")

            panel:AddControl("Label", { Text = "" })

            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Throw Chance",
                "npc_clawscanner_throw_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 – 1.00) that an eligible NPC throws\n  a clawscanner each time it is checked.  Default: 0.15")

            panel:NumSlider("Check Interval (seconds)",
                "npc_clawscanner_throw_interval", 1, 30, 0)
            panel:ControlHelp("  How many seconds between throw-eligibility checks\n  for each individual NPC.  Default: 10")

            panel:NumSlider("Throw Cooldown (seconds)",
                "npc_clawscanner_throw_cooldown", 1, 60, 0)
            panel:ControlHelp("  Minimum seconds that must pass between throws\n  for the same NPC.  Default: 25")

            panel:AddControl("Label", { Text = "" })

            panel:AddControl("Header", {
                Description = "Projectile Behaviour",
                Height      = "30",
            })

            panel:NumSlider("Launch Speed (units/s)",
                "npc_clawscanner_throw_speed", 100, 1500, 0)
            panel:ControlHelp("  Initial throw speed before the scanner's own AI takes over.\n  Default: 550")

            panel:NumSlider("Arc Factor",
                "npc_clawscanner_throw_arc", 0, 1, 2)
            panel:ControlHelp("  Upward lob strength.\n  0.00 = nearly flat,  1.00 = very high arc.  Default: 0.28")

            panel:NumSlider("Spawn Offset (units)",
                "npc_clawscanner_throw_spawn_dist", 20, 150, 0)
            panel:ControlHelp("  Forward distance from the NPC's eye to where the\n  clawscanner spawns.  Default: 52")

            panel:CheckBox("Apply Random Spin", "npc_clawscanner_throw_spin")
            panel:ControlHelp("  Adds a random angular impulse so the scanner tumbles\n  briefly before its flight AI stabilises it.")

            panel:AddControl("Label", { Text = "" })

            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_clawscanner_throw_max_dist", 200, 6000, 0)
            panel:ControlHelp("  NPCs will not throw if the player is farther than\n  this many units away.  Default: 2000")

            panel:NumSlider("Min Distance",
                "npc_clawscanner_throw_min_dist", 0, 500, 0)
            panel:ControlHelp("  NPCs will not throw if the player is closer than\n  this many units.  Default: 150")

            panel:AddControl("Label", { Text = "" })

            panel:ControlHelp("  The clawscanner receives an initial launch impulse then\n  its own flight AI takes over to pursue the player.")

        end
    )
end)
