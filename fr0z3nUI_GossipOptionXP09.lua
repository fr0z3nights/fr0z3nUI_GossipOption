local _, ns = ...

ns.db = ns.db or {}
ns.db.rules = ns.db.rules or {}

-- XP09 database (Expansion 9)
-- Add rules like:
-- ns.db.rules[123456] = ns.db.rules[123456] or {}
-- ns.db.rules[123456][98765] = { text = [[Option text]], type = "", expansion = "XP09", zoneName = "Zone", npcName = "NPC" }
