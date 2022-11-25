-- "CHAT_MSG_LOOT" event

-- GetInventoryItemLink func to read other players currently equipped slot

-- https://wow.gamepedia.com/CHAT_MSG_LOOT

-- https://wowwiki.fandom.com/wiki/API_GetItemInfo

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemID

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemLink

local cachedInventories = {}
local cachedUnitIDs = {}
local inspectedPlayers = {}

local lastUpdateTimeForPlayer = {}

local PlayerLoginFrame = CreateFrame("Frame")
PlayerLoginFrame:RegisterEvent("PLAYER_LOGIN")

local InspectFrame = CreateFrame("Frame")
InspectFrame:RegisterEvent("INSPECT_READY")

local ChatLootFrame = CreateFrame("Frame")
ChatLootFrame:RegisterEvent("CHAT_MSG_LOOT")

local PartyChangeFrame = CreateFrame("Frame")
PartyChangeFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")

local UpdateFrame = CreateFrame("Frame")


local LootCompare_UpdateInterval = 5.0; -- How often the OnUpdate code will run (in seconds)
local LootCompare_ResetCacheInterval = 180.0; -- How often the OnUpdate code will run (in seconds)
local TimeSinceLastUpdate = 0

local allPlayersInspected = false

cachedUnitIDs[UnitGUID("player")] = "player"

-- Functions Section

function LootCompare:TryCacheInventory(GUID)

    local UnitID = cachedUnitIDs[GUID]

    if UnitID == nil then
        print("No cached unit ID found for GUID " .. GUID.. ".")
        return;
    end

    local lastInventoryUpdateTime = lastUpdateTimeForPlayer[GUID];
 
    if lastInventoryUpdateTime == nil or (GetTime() - lastInventoryUpdateTime) > LootCompare.UpdateIntervalSec then

        if cachedInventories[GUID] == nil then
            cachedInventories[GUID] = {}
        end

        local playerInventory = cachedInventories[GUID]

        for i = 1, 18 do
            playerInventory[i] = GetInventoryItemLink(UnitID, i)
        end

        lastUpdateTimeForPlayer[GUID] = GetTime()
        
        print(UnitName(UnitID) .. " (".. UnitID .. ") inventory cached.")
    end
end

function LootCompare:TryInspect(GUID)
    
    local UnitID = cachedUnitIDs[GUID]

    if UnitID == nil then
        print("No cached unit ID found for GUID " .. GUID.. ".")
        return;
    end

    if ~UnitIsConnected(UnitID) then
        print("*LootCompare* Cannot inspect player ".. GUID .. " since they're not connected!")
        return;
    end

    -- If the last inspect request failed don't try the same guid
    if LootCompare.GuidForOutstandingInspectRequest == GUID then
        return false;
    end
    
    local lastInventoryUpdateTime = lastUpdateTimeForPlayer[GUID];
 
    if lastInventoryUpdateTime ~= nil and (GetTime() - lastInventoryUpdateTime) < LootCompare.CacheInventoryThrottleSec then
        return false;
    end
    
    -- !!!!! ADD RANGE CHECK - "and CheckInteractDistance(UID, 1)"
    print("*LootCompare* Sending inspect for ".. UnitID .. "!")
    LootCompare.GuidForOutstandingInspectRequest = GUID
    NotifyInspect(UnitID)

    return true;
end

UpdateFrame:HookScript("OnUpdate", function(_, elapsed)

    if not LootCompare.IsInParty() then
        return;
    end
    
    LootCompare.TimeSinceLastInspect = LootCompare.TimeSinceLastInspect + elapsed; 	

    -- Inspect requests take time so we need to throttle while we wait for one to complete
    if LootCompare.GuidForOutstandingInspectRequest ~= nil and LootCompare.TimeSinceLastInspect < LootCompare.InspectThrottleSec then
        return;
    end
    
    if inspectedPlayers[UnitGUID("player")] == nil then
        LootCompare:TryCacheInventory(UnitGUID("player"))
    end

    for GUID, _ in cachedUnitIDs do
        if LootCompare.TryInspect(GUID) then
            return
        end
    end
end)

InspectFrame:SetScript("OnEvent", function(_, _, ...)
    
    if LootCompare.IsInParty() then 
        local GUID = ...;

        LootCompare:TryCacheInventory(GUID)
    end

end)

PartyChangeFrame:SetScript("OnEvent", function(_, _, ...)
    
    local members = GetNumGroupMembers() - 1
    local GUID = ""
    local UID = ""

    for N = 1, members do

        UID = "party" .. N
        GUID = UnitGUID(UID)

        if GUID ~= nil then
            cachedUnitIDs[GUID] = UID
        else
            print("*LootCompare* Failed to get GUID for unit " .. UID.. ".")
        end
    end
end)

-- When an item is looted by a player and it is displayed in chat check if it's an upgrade for them
ChatLootFrame:SetScript("OnEvent", function(self, event, ...)

    if LootCompare.IsInParty() == false then
        return;
    end

    local lootedItemLink, looterName = ...;

    local s, _ = string.find(looterName, '-', 1, true)
    looterName = strsub(looterName, 1, s - 1)
    local looterGUID = UnitGUID(looterName);

    if looterGUID ~= nil then
        print("*LootCompare* Failed to get the GUID for looter " .. looterName .. "!")
        return;
    end

    if LootCompare.IsUpgrade(looterGUID, lootedItemLink) then
        print("*LootCompare* " .. lootedItemLink .. " was an upgrade for the looter so no comparison will take place.")
    else
        LootCompare:CheckForUpgrades(looterGUID, lootedItemLink)
    end

end)

function LootCompare:GetItemSlotForPlayer(playerGuid, itemSlotId)

    local playerInventory = cachedInventories[playerGuid];

    if playerInventory == nil then
        local playerName = UnitName(cachedUnitIDs[playerGuid])
        print("*LootCompare* Cannot get item slot {".. itemSlotId .. "} for " .. playerName .. " since their inventory wasn't cached!")
        return nil
    end

    local item = playerInventory[itemSlotId];

    if item == nil then
        local playerName = UnitName(cachedUnitIDs[playerGuid])
        print("*LootCompare* Undefined {".. itemSlotId .. "} slot for " .. playerName .. " inventory cache!")
        return nil
    end

    return item;
end

function LootCompare:IsUpgrade(playerGuid, lootedItemLink)
    local _, _, _, lootedItemLevel, _, _, lootedItemSubType, _, lootedItemSlotName = GetItemInfo(lootedItemLink)

    -- Translate item slot name to the item slot IDs
    local possibleItemSlots = LootCompare.ItemSlotNameToIdsMap[lootedItemSlotName]

    for index, itemSlot in pairs(possibleItemSlots) do
        local equippedItem = LootCompare.GetItemSlotForPlayer(playerGuid, itemSlot)
        local _, _, _, equippedItemLevel, _, _, equippedItemSubType = GetItemInfo(equippedItem);

        if lootedItemLevel > equippedItemLevel and lootedItemSubType == equippedItemSubType then
            return true;
        end
    end

    return false;
end

function LootCompare:CheckForUpgrades(looterName, looterGUID, lootedItemLink)

    local slotID = 0

    local upgradeExists = false

    local upgradeFor = {}

    local cacheSize = 0

    for playerGuid, inventory in pairs(cachedInventories) do

        if playerGuid == looterGUID then
            continue;
        end

        cacheSize = cacheSize + 1

        if LootCompare.IsUpgrade(playerGuid, lootedItemLink) then
            tinsert(upgradeFor[playerName], itemLink)
        end
    end

    if cacheSize < GetNumGroupMembers() - 1 then
        print("*LootCompare* A party members inventory was not found in cache when trying to compare items! Cache size: " .. cacheSize .. "   Party Size: " .. GetNumGroupMembers())
    end

    local playersItems = ""

    if upgradeExists == true then 
        SendChatMessage(looterName .. " looted " .. lootedItemLink .. ". Upgrade for:", "PARTY", nil, nil)
    end 
    
    for playerName, itemLinks in pairs(upgradeFor) do

        playersItems = playerName .. " - Equipped = "

        for i = 1, table.getn(itemLinks) do
            playersItems = playersItems .. itemLinks[i]
        end

        SendChatMessage(playersItems, "PARTY", nil, nil)
    end

    
end


--local lootFrame = CreateFrame("Frame", "DragFrame2", UIParent)
--lootFrame:SetMovable(true)
--lootFrame:EnableMouse(true)
--lootFrame:RegisterForDrag("LeftButton")
--lootFrame:SetScript("OnDragStart", lootFrame.StartMoving)
--lootFrame:SetScript("OnDragStop", lootFrame.StopMovingOrSizing)

-- The code below makes the frame visible, and is not necessary to enable dragging.
--lootFrame:SetPoint("CENTER")
--lootFrame:SetWidth(256)
--lootFrame:SetHeight(76)

--local tex = lootFrame:CreateTexture(nil,"BACKGROUND")
--tex:SetTexture("BlizzardInterfaceArt\\Interface\\LootFrame\\LootToast.BLP")
--tex:SetTexCoord(0, 0.5, 0, 1);
--tex:SetTexCoord(0.28975, 0.54341, 0.607, 0.91828);
--tex:SetAllPoints(lootFrame)
--lootFrame.texture = tex
--lootFrame:SetPoint("CENTER",0,0)
--lootFrame:Show()
