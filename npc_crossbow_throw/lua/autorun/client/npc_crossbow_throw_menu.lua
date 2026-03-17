-- ============================================================
--  NPC Crossbow Bolt Throw  |  npc_crossbow_throw_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

-- ============================================================
--  Register the category (no-op if already registered)
-- ============================================================
hook.Add("AddToolMenuCategories", "NPCCrossbowThrow_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

-- ============================================================
--  Build the panel
-- ============================================================
hook.Add("PopulateToolMenu", "NPCCrossbowThrow_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",
        ADDON_CATEGORY,
        "npc_crossbow_throw_settings",
        "NPC Crossbow Bolt Throw",
        "",
        "",
        function(panel)

            panel:ClearControls()

            -- ------------------------------------------------
            --  Header
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "NPC Crossbow Bolt Throw Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Crossbow Bolt Throws", "npc_crossbow_throw_enabled")
            panel:ControlHelp("  Master on/off switch for the entire addon.")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Probability & Timing
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Fire Chance",
                "npc_crossbow_throw_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 – 1.00) that an eligible NPC fires\n  a bolt each time it is checked.  Default: 0.20")

            panel:NumSlider("Check Interval (seconds)",
                "npc_crossbow_throw_interval", 1, 30, 0)
            panel:ControlHelp("  How many seconds between fire-eligibility checks\n  for each individual NPC.  Default: 7")

            panel:NumSlider("Fire Cooldown (seconds)",
                "npc_crossbow_throw_cooldown", 1, 60, 0)
            panel:ControlHelp("  Minimum seconds that must pass between bolts\n  for the same NPC.  Default: 14")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Projectile Behaviour
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Projectile Behaviour",
                Height      = "30",
            })

            panel:NumSlider("Launch Speed (units/s)",
                "npc_crossbow_throw_speed", 200, 4000, 0)
            panel:ControlHelp("  How fast the bolt travels.\n  Higher = harder to dodge.  Default: 1800")

            panel:NumSlider("Arc Factor",
                "npc_crossbow_throw_arc", 0, 0.5, 2)
            panel:ControlHelp("  Upward lob strength.  Bolts should stay near 0.00\n  for a flat, realistic trajectory.  Default: 0.05")

            panel:NumSlider("Spawn Offset (units)",
                "npc_crossbow_throw_spawn_dist", 20, 150, 0)
            panel:ControlHelp("  Forward distance from the NPC's eye to the bolt\n  spawn point.  Increase if self-collision occurs.  Default: 56")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Engagement Range
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_crossbow_throw_max_dist", 200, 8000, 0)
            panel:ControlHelp("  NPCs will not fire if the player is farther than\n  this many units away.  Default: 3000")

            panel:NumSlider("Min Distance",
                "npc_crossbow_throw_min_dist", 0, 500, 0)
            panel:ControlHelp("  NPCs will not fire if the player is closer than\n  this many units.  Default: 120")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp("  Changes take effect immediately.\n  Requires VJ Base for the bolt entity (obj_vj_crossbowbolt).\n  The bolt is not guaranteed to hit – aim is intentionally imprecise.")

        end
    )
end)
