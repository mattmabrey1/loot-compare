--[[
		GLOBAL VARIABLES
		Usable within any LC-NAMEHERE addon, or any addon in general,
		as everything here unless defined local is globally usable outside of this file.
]]--

-- Globals Section
LootCompare = {}

LootCompare.ItemSlotNameToIdsMap = {
    INVTYPE_HEAD = {1},
    INVTYPE_NECK = {2},
    INVTYPE_SHOULDER = {3},
    INVTYPE_CHEST = {5},
    INVTYPE_ROBE = {5},
    INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7},
    INVTYPE_FEET = {8},
    INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10},
    INVTYPE_FINGER = {11, 12},
    INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = {15},
    INVTYPE_WEAPON = {16, 17},
    INVTYPE_SHIELD = {16, 17},
    INVTYPE_2HWEAPON = {16, 17},
    INVTYPE_WEAPONMAINHAND = {16, 17},
    INVTYPE_WEAPONOFFHAND = {16, 17},
    INVTYPE_HOLDABLE = {16, 17},
    INVTYPE_RANGED = {18},
    INVTYPE_THROWN = {18},
    INVTYPE_RANGEDRIGHT = {18},
    INVTYPE_RELIC = {18},
    ['?'] = nil 
}

LootCompare.InspectThrottleSec = 10.0; -- The throttle for inspecting other player's inventories in seconds
LootCompare.CacheInventoryThrottleSec = 180.0; -- The throttle for updating a player's cached inventory in seconds
LootCompare.TimeSinceLastInspect = 0;
LootCompare.GuidForOutstandingInspectRequest = nil; -- The guid for the last player we tried inspecting

local allPlayersInspected = false

LootCompare.PlayerGuid = UnitGUID("player");

LootCompare.CachedInventories = {}
LootCompare.CachedUnitIDs = {}

LootCompare.CachedUnitIDs[LootCompare.PlayerGuid] = "player"

function LootCompare.IsInParty()
    return IsInGroup() and IsInRaid() == false;
end