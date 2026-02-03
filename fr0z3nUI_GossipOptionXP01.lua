local _, ns = ...

ns.db = ns.db or {}
ns.db.rules = ns.db.rules or {}

-- XP01 database (Expansion 1)
-- Add rules like:
-- ns.db.rules[123456] = ns.db.rules[123456] or {}
-- ns.db.rules[123456][98765] = { text = [[Option text]], type = "", expansion = "XP01", zoneName = "Zone", npcName = "NPC" }

-- Darkshore
   -- Zidormi
        ns.db.rules[141489] = ns.db.rules[141489] or {}
        ns.db.rules[141489][49022] = { npcName = "Zidormi", text = "Can you show me what Darkshore was like before the battle?", type = "", zoneName = "Darnassus", expansion = "XP08" }



