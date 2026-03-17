-- ============================================================
--  NPC Flare Throw  |  npc_flare_throw_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

-- ============================================================
--  Register the category (safe no-op if it already exists)
-- ============================================================
hook.Add("AddToolMenuCategories", "NPCFlareThrow_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

-- ============================================================
--  Build the panel
-- ============================================================
hook.Add("PopulateToolMenu", "NPCFlareThrow_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",          -- tab  (the Options tab)
        ADDON_CATEGORY,     -- category
        "npc_flare_throw_settings",  -- unique class key
        "NPC Flare Throw",  -- display name
        "",                 -- icon (none needed)
        "",                 -- description tooltip
        function(panel)

            panel:ClearControls()

            -- ------------------------------------------------
            --  Master toggle
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "NPC Flare Throw Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Flare Throws", "npc_flare_throw_enabled")
            panel:ControlHelp("  Master on/off switch for the entire addon.")

            panel:AddControl("Label", { Text = "" })  -- spacer

            -- ------------------------------------------------
            --  Probability & timing
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Throw Chance",
                "npc_flare_throw_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 – 1.00) that an eligible NPC throws\n  a flare each time it is checked.  Default: 0.15")

            panel:NumSlider("Check Interval (seconds)",
                "npc_flare_throw_interval", 1, 30, 0)
            panel:ControlHelp("  How many seconds between throw-eligibility checks\n  for each individual NPC.  Default: 6")

            panel:NumSlider("Throw Cooldown (seconds)",
                "npc_flare_throw_cooldown", 1, 60, 0)
            panel:ControlHelp("  Minimum seconds that must pass between throws\n  for the same NPC.  Default: 12")

            panel:AddControl("Label", { Text = "" })  -- spacer

            -- ------------------------------------------------
            --  Projectile behaviour
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Projectile Behaviour",
                Height      = "30",
            })

            panel:NumSlider("Launch Speed (units/s)",
                "npc_flare_throw_speed", 100, 1500, 0)
            panel:ControlHelp("  How fast the flare is thrown.  Default: 550")

            panel:NumSlider("Arc Factor",
                "npc_flare_throw_arc", 0, 1, 2)
            panel:ControlHelp("  Upward lob strength.\n  0.00 = nearly flat,  1.00 = very high arc.  Default: 0.22")

            panel:NumSlider("Spawn Offset (units)",
                "npc_flare_throw_spawn_dist", 20, 150, 0)
            panel:ControlHelp("  Forward distance from the NPC's eye to where the\n  flare spawns.  Increase if you see self-collision.  Default: 52")

            panel:AddControl("Label", { Text = "" })  -- spacer

            -- ------------------------------------------------
            --  Engagement range
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_flare_throw_max_dist", 200, 6000, 0)
            panel:ControlHelp("  NPCs will not throw if the player is farther than\n  this many units away.  Default: 2500")

            panel:NumSlider("Min Distance",
                "npc_flare_throw_min_dist", 0, 500, 0)
            panel:ControlHelp("  NPCs will not throw if the player is closer than\n  this many units (too close to lob).  Default: 100")

            panel:AddControl("Label", { Text = "" })  -- spacer

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp("  Changes take effect immediately.\n  Requires VJ Base for the flare entity (obj_vj_flareround).")

        end
    )
end)
