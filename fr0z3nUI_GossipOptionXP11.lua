local _, ns = ...

ns.db = ns.db or {}
ns.db.rules = ns.db.rules or {}

-- XP11 database (Expansion 11)
-- Add rules like:
-- ns.db.rules[123456] = ns.db.rules[123456] or {}
-- ns.db.rules[123456][98765] = { text = [[Option text]], type = "", expansion = "XP11", zoneName = "Zone", npcName = "NPC" }

-- Dornogal

    -- Brann Bronzebeard
        ns.db.rules[206017] = ns.db.rules[206017] or {}
        ns.db.rules[206017][123770] = { npcName = "Brann Bronzebeard", text = "I'd like to join the reinforcements. \r\n|cFFFF0000 <Skip the level-up campaign.> |r", type = "", zoneName = "Dornogal", expansion = "XP11" }
        ns.db.rules[206017][123771] = { npcName = "Brann Bronzebeard", text = "I'd like to join the reinforcements. \r\n|cFFFF0000 <Skip the level-up campaign.> |r", type = "", zoneName = "Dornogal", expansion = "XP11" }

   -- Delver's Guide
        ns.db.rules[227675] = ns.db.rules[227675] or {}
        ns.db.rules[227675][123493] = { npcName = "Delver's Guide", text = "<Review information on your current delve progress.>", type = "", zoneName = "Dornogal", expansion = "XP11" }




