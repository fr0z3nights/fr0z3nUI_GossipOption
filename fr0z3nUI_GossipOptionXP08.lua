local _, ns = ...

ns.db = ns.db or {}
ns.db.rules = ns.db.rules or {}

-- XP08 database (Expansion 8)
-- Add rules like:
-- ns.db.rules[123456] = ns.db.rules[123456] or {}
-- ns.db.rules[123456][98765] = { text = [[Option text]], type = "", expansion = "XP08", zoneName = "Zone", npcName = "NPC" }
