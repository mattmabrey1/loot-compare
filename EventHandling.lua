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
    
    if LootCompare:IsInParty() == false then
        return;
    end

    LootCompare.TimeSinceLastInspect = LootCompare.TimeSinceLastInspect + elapsed;

    LootCompare:TryCachePartyInventories()
end)

InspectFrame:SetScript("OnEvent", function(_, _, ...)

    if LootCompare:IsInParty() == false then
        return;
    end

    local GUID = ...;
    LootCompare:TryCacheInventory(GUID)
end)

PartyChangeFrame:SetScript("OnEvent", function(_, _, ...)

    if LootCompare:IsInParty() == false then
        return;
    end

    LootCompare:MapPartyMemberGuidsToUnitIds();
end)

-- When an item is looted by a player and it is displayed in chat check if it's an upgrade for them
ChatLootFrame:SetScript("OnEvent", function(self, event, ...)

    if LootCompare:IsInParty() == false then
        return;
    end

    local lootedItemLink, looterName = ...;
    LootCompare:OnItemLooted(lootedItemLink, looterName);
end)