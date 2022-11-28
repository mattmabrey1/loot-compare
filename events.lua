local PlayerLoginFrame = CreateFrame("Frame")
PlayerLoginFrame:RegisterEvent("PLAYER_LOGIN")

local InspectFrame = CreateFrame("Frame")
InspectFrame:RegisterEvent("INSPECT_READY")

local ChatLootFrame = CreateFrame("Frame")
ChatLootFrame:RegisterEvent("CHAT_MSG_LOOT")

local PartyChangeFrame = CreateFrame("Frame")
PartyChangeFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

local UpdateFrame = CreateFrame("Frame")

UpdateFrame:HookScript("OnUpdate", function(_, elapsed)
    LootCompare:TryCachePartyInventories()
end)

InspectFrame:SetScript("OnEvent", function(_, _, ...)
    local GUID = ...;
    LootCompare:TryCacheInventory(GUID)
end)

PartyChangeFrame:SetScript("OnEvent", function(_, _, ...)
    LootCompare:MapPartyMemberGuidsToUnitIds();
end)

-- When an item is looted by a player and it is displayed in chat check if it's an upgrade for them
ChatLootFrame:SetScript("OnEvent", function(self, event, ...)
    local lootedItemLink, looterName = ...;
    LootCompare:CompareLoot(lootedItemLink, looterName);
end)