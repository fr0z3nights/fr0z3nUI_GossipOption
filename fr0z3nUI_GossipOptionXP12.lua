local _, ns = ...

ns.db = ns.db or {}
ns.db.rules = ns.db.rules or {}

-- XP12 database (Expansion 12)
-- Add rules like:
-- ns.db.rules[123456] = ns.db.rules[123456] or {}
-- ns.db.rules[123456][98765] = { text = [[Option text]], type = "", expansion = "XP12", zoneName = "Zone", npcName = "NPC" }
