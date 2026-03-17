-- ============================================================
--  NPC Cluster Throw  |  npc_cluster_throw_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu, alongside NPC Smoke Throw
--  and NPC Molotov Throw.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

-- ============================================================
--  Register the category (safe no-op if it already exists)
-- ============================================================
hook.Add("AddToolMenuCategories", "NPCClusterThrow_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

-- ============================================================
--  Build the panel
-- ============================================================
hook.Add("PopulateToolMenu", "NPCClusterThrow_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",                      -- tab  (the Options tab)
        ADDON_CATEGORY,                 -- category
        "npc_cluster_throw_settings",   -- unique class key
        "NPC Cluster Throw",            -- display name
        "",                             -- icon (none needed)
        "",                             -- description tooltip
        function(panel)

            panel:ClearControls()

            -- ------------------------------------------------
            --  Header
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "NPC Cluster Throw Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Cluster Bomb Throws", "npc_cluster_throw_enabled")
            panel:ControlHelp("  Master on/off switch for the entire addon.")

            panel:CheckBox("Debug Announce in Console", "npc_cluster_throw_announce")
            panel:ControlHelp("  Print a console message every time an NPC throws,\n  including the sub-munition count rolled for that throw.")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Probability & timing
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Throw Chance",
                "npc_cluster_throw_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 – 1.00) that an eligible NPC throws\n  a cluster bomb each time it is checked.  Default: 0.15")

            panel:NumSlider("Check Interval (seconds)",
                "npc_cluster_throw_interval", 1, 30, 0)
            panel:ControlHelp("  How many seconds between throw-eligibility checks\n  for each individual NPC.  Default: 10")

            panel:NumSlider("Throw Cooldown (seconds)",
                "npc_cluster_throw_cooldown", 1, 90, 0)
            panel:ControlHelp("  Minimum seconds that must pass between throws\n  for the same NPC.  Default: 25")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Projectile behaviour
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Projectile Behaviour",
                Height      = "30",
            })

            panel:NumSlider("Launch Speed (units/s)",
                "npc_cluster_throw_speed", 100, 2500, 0)
            panel:ControlHelp("  How fast the cluster bottle is thrown.  Default: 1200")

            panel:NumSlider("Arc Factor",
                "npc_cluster_throw_arc", 0, 1, 2)
            panel:ControlHelp("  Upward lob strength.\n  0.00 = nearly flat,  1.00 = very high arc.  Default: 0.30")

            panel:NumSlider("Spawn Offset (units)",
                "npc_cluster_throw_spawn_dist", 20, 150, 0)
            panel:ControlHelp("  Forward distance from the NPC's eye to where the\n  casing spawns.  Increase if you see self-collision.  Default: 58")

            panel:CheckBox("Apply Random Spin to Casing", "npc_cluster_throw_spin")
            panel:ControlHelp("  Adds a random angular impulse to the casing in flight,\n  making it tumble naturally before impact.")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Fuse timers
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Fuse Timers",
                Height      = "30",
            })

            panel:NumSlider("Casing Fuse (seconds)",
                "npc_cluster_throw_fuse", 0.5, 10, 1)
            panel:ControlHelp("  Hard fuse on the cluster casing.  Detonates this many\n  seconds after being thrown, even if it hasn't landed.\n  It also detonates immediately on solid impact.  Default: 3.5")

            panel:NumSlider("Sub-Munition Fuse (seconds)",
                "npc_cluster_throw_sub_fuse", 0.5, 8, 1)
            panel:ControlHelp("  How long each scattered frag grenade lives before\n  exploding.  A ±0.25 s jitter is always applied so\n  sub-munitions don't all burst in one frame.  Default: 2.0")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Sub-munition count
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Sub-Munition Count",
                Height      = "30",
            })

            panel:NumSlider("Minimum Grenades",
                "npc_cluster_throw_grenade_min", 1, 9, 0)
            panel:ControlHelp("  Fewest npc_grenade_frag entities released per\n  detonation.  Cannot exceed Maximum Grenades.  Default: 3")

            panel:NumSlider("Maximum Grenades",
                "npc_cluster_throw_grenade_max", 1, 9, 0)
            panel:ControlHelp("  Most npc_grenade_frag entities released per\n  detonation.  The actual count is rolled randomly\n  between Min and Max at throw time.  Default: 9")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Sub-munition spread
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Sub-Munition Spread",
                Height      = "30",
            })

            panel:NumSlider("Horizontal Speed Min (units/s)",
                "npc_cluster_throw_launch_h_min", 50, 1000, 0)
            panel:ControlHelp("  Minimum outward (horizontal) scatter speed\n  for each released grenade.  Default: 250")

            panel:NumSlider("Horizontal Speed Max (units/s)",
                "npc_cluster_throw_launch_h_max", 50, 1000, 0)
            panel:ControlHelp("  Maximum outward (horizontal) scatter speed\n  for each released grenade.  Default: 550")

            panel:NumSlider("Vertical Speed Min (units/s)",
                "npc_cluster_throw_launch_v_min", 0, 800, 0)
            panel:ControlHelp("  Minimum upward launch speed for each released\n  grenade.  Default: 200")

            panel:NumSlider("Vertical Speed Max (units/s)",
                "npc_cluster_throw_launch_v_max", 0, 800, 0)
            panel:ControlHelp("  Maximum upward launch speed for each released\n  grenade.  Default: 400")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Engagement range
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_cluster_throw_max_dist", 200, 6000, 0)
            panel:ControlHelp("  NPCs will not throw if the player is farther than\n  this many units away.  Default: 2000")

            panel:NumSlider("Min Distance",
                "npc_cluster_throw_min_dist", 0, 500, 0)
            panel:ControlHelp("  NPCs will not throw if the player is closer than\n  this many units (too close to lob).  Default: 150")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp(
                "  Changes take effect immediately.\n" ..
                "  The cluster casing uses the Magnusson Device model.\n" ..
                "  Sub-munitions are live npc_grenade_frag entities.\n" ..
                "  Kill credit is assigned to the throwing NPC."
            )

        end
    )
end)
