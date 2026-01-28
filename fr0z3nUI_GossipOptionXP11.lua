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
        ns.db.rules[206017][123770] = { text = "I'd like to join the reinforcements. \r\n|cFFFF0000 <Skip the level-up campaign.> |r", type = "", expansion = "XP11" }
        ns.db.rules[206017][123771] = { text = "I'd like to join the reinforcements. \r\n|cFFFF0000 <Skip the level-up campaign.> |r", type = "", expansion = "XP11" }






