---@diagnostic disable: undefined-global

local _, ns = ...

ns.db = ns.db or {}
ns.db.rules = ns.db.rules or {}

-- XP01KD database pack
-- Add rules like:
-- ns.db.rules[123456] = ns.db.rules[123456] or {}
-- ns.db.rules[123456].__meta = { zone = "Zone, Continent", npc = "NPC Name" }
-- ns.db.rules[123456][98765] = { text = [[Option text]], type = "" }
-- (Per-rule overrides still supported: zoneName/zone, npcName/npc)

-- Helpers so you can set a zone header and avoid repeating zone/npc fields.
local CURRENT_ZONE

local function SetZone(zone)
    CURRENT_ZONE = zone
end

local function NPC(npcID, npcName)
    ns.db.rules[npcID] = ns.db.rules[npcID] or {}
    ns.db.rules[npcID].__meta = { zone = CURRENT_ZONE, npc = npcName }
    return ns.db.rules[npcID]
end

-- Convenience helper: write one set of option rules to multiple NPC IDs.
-- Example:
-- local t = NPCs({111, 222}, "Same NPC")
-- t[12345] = { text = "...", type = "" }
local function NPCs(npcIDs, npcName)
    if type(npcIDs) ~= "table" then
        npcIDs = { npcIDs }
    end

    local targets = {}
    for _, id in ipairs(npcIDs) do
        targets[#targets + 1] = NPC(id, npcName)
    end

    return setmetatable({}, {
        __index = function(_, key)
            local t = targets[1]
            return t and t[key]
        end,
        __newindex = function(_, key, value)
            for _, t in ipairs(targets) do
                t[key] = value
            end
        end,
    })
end

-- KALIMDOR

SetZone("Darkshore, Kalimdor")

    -- Zidormi
    local t = NPC(141489, "Zidormi")
    t[49022] = { text = "Can you show me what Darkshore was like before the battle?", type = "" }

SetZone("Orgrimmar, Kalimdor")

    -- 12.0.0 Prepatch
--    local t = NPC(248174, "Suspicious Citizen")
--    t[134631] = { text = "Are you talking about the Twilight's Blade?", type = "" }

--    local t = NPC(246157, "Suspicious Citizen")
--    t[134634] = { text = "Are you talking about the Twilight's Blade?", type = "" }

    -- 12.0.0 Prepatch
   local t = NPCs({ 246157, 248174 }, "Suspicious Citizen")
   t[134631] = { text = "Are you talking about the Twilight's Blade?", type = "" }
   t[134634] = { text = "Are you talking about the Twilight's Blade?", type = "" }
