-- "CHAT_MSG_LOOT" event

-- GetInventoryItemLink func to read other players currently equipped slot

-- https://wow.gamepedia.com/CHAT_MSG_LOOT

-- https://wowwiki.fandom.com/wiki/API_GetItemInfo

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemID

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemLink

local lastUpdateTimeForPlayer = {}

-- Functions Section
function LootCompare:GetUnitId(GUID)

    if LootCompare.GuidToUnitIdMap[GUID] == nil then
        print("No cached unit ID found for GUID " .. GUID.. ".")
        return nil;
    end

    return LootCompare.GuidToUnitIdMap[GUID];
end

function LootCompare:GetUnitName(GUID)

    local unitId = LootCompare:GetUnitId(GUID)
    if unitId == nil then
        print("Failed to get unit Id to get unit's name for GUID " .. GUID.. ".")
        return nil;
    end
    
    return UnitName(unitId);
end

function LootCompare:CacheInventory(GUID)

    local lastInventoryUpdateTime = lastUpdateTimeForPlayer[GUID];
 
    if lastInventoryUpdateTime == nil or (GetTime() - lastInventoryUpdateTime) > LootCompare.UpdateIntervalSec then

        if LootCompare.CachedInventories[GUID] == nil then
            LootCompare.CachedInventories[GUID] = {}
        end
        
        local UnitID = LootCompare.GetUnitId(GUID);
        if UnitID == nil then
            return;
        end

        for i = 1, 18 do
            LootCompare.CachedInventories[GUID][i] = GetInventoryItemLink(UnitID, i)
        end

        lastUpdateTimeForPlayer[GUID] = GetTime()
        
        print(UnitName(UnitID) .. " (".. UnitID .. ") inventory cached.")
    end
end


function LootCompare:TryCachePartyInventories()
    if not LootCompare:IsInParty() then
        return;
    end

    -- Inspect requests take time so we need to throttle while we wait for one to complete
    if LootCompare.GuidForOutstandingInspectRequest ~= nil and LootCompare.TimeSinceLastInspect < LootCompare.InspectThrottleSec then
        return;
    end
    
    LootCompare:CacheInventory(LootCompare.PlayerGuid)

    for GUID, UnitId in pairs(LootCompare.GuidToUnitIdMap) do
        -- only try inspecting one player at a time
        if LootCompare:TryInspect(GUID, UnitId) then
            LootCompare.TimeSinceLastInspect = 0
            return
        end
    end
end

function LootCompare:TryInspect(GUID, unitId)
    
    if not UnitIsConnected(unitId) then
        print("*LootCompare* Cannot inspect player ".. GUID .. " since they're not connected!")
        return false;
    end

    -- If the last inspect request failed don't try the same guid
    if LootCompare.GuidForOutstandingInspectRequest == GUID then
        return false;
    end
    
    local lastInventoryUpdateTime = lastUpdateTimeForPlayer[GUID];
 
    -- Only try to inspect the player and cache their inventory once the throttle has passed
    if lastInventoryUpdateTime ~= nil and (GetTime() - lastInventoryUpdateTime) < LootCompare.CacheInventoryThrottleSec then
        return false;
    end
    
    -- !!!!! ADD RANGE CHECK - "and CheckInteractDistance(UID, 1)"
    print("*LootCompare* Sending inspect for ".. unitId .. "!")
    LootCompare.GuidForOutstandingInspectRequest = GUID
    NotifyInspect(unitId)

    return true;
end

function LootCompare:MapPartyMemberGuidsToUnitIds()
    local guid = nil
    local unitId = nil
    local members = GetNumGroupMembers() - 1

    for N = 1, members do

        unitId = "party" .. N
        guid = UnitGUID(unitId)

        if guid ~= nil then
            LootCompare.GuidToUnitIdMap[guid] = unitId
        else
            print("*LootCompare* Failed to get GUID for unit " .. unitId.. ".")
        end
    end
end

function LootCompare:OnItemLooted(lootedItemLink, looterName)

    if LootCompare:IsInParty() == false then
        return;
    end

    local s, _ = string.find(looterName, '-', 1, true)
    looterName = strsub(looterName, 1, s - 1)
    local looterGUID = UnitGUID(looterName);

    if looterGUID ~= nil then
        print("*LootCompare* Failed to get the GUID for looter " .. looterName .. "!")
        return;
    end

    if LootCompare:IsUpgrade(looterGUID, lootedItemLink) then
        print("*LootCompare* " .. lootedItemLink .. " was an upgrade for the looter so no comparison will take place.")
    else
        LootCompare:CheckForPartyMemberUpgrade(looterGUID, lootedItemLink)
    end
end

function LootCompare:GetItemInSlot(playerGuid, itemSlotId)

    local playerInventory = LootCompare.CachedInventories[playerGuid];

    if playerInventory == nil then
        local playerName = UnitName(LootCompare.GuidToUnitIdMap[playerGuid])
        print("*LootCompare* Cannot get item slot {".. itemSlotId .. "} for " .. playerName .. " since their inventory wasn't cached!")
        return nil
    end

    local item = playerInventory[itemSlotId];

    if item == nil then
        local playerName = UnitName(LootCompare.GuidToUnitIdMap[playerGuid])
        print("*LootCompare* Undefined {".. itemSlotId .. "} slot for " .. playerName .. " inventory cache!")
        return nil
    end

    return item;
end

function LootCompare:IsUpgrade(playerGuid, lootedItemLink)
    local _, _, _, lootedItemLevel, _, _, lootedItemSubType, _, lootedItemSlotName = GetItemInfo(lootedItemLink)

    -- Translate item slot name to the item slot IDs
    local possibleItemSlots = LootCompare.ItemSlotNameToIdsMap[lootedItemSlotName]

    if possibleItemSlots == nil then
        print("*LootCompare* couldn't find item slots for item slot name " .. lootedItemSlotName .. ".")
        return nil;
    end

    local lowestIlvlItem = nil;
    local lowestItemLevel = 0;

    for _, itemSlot in pairs(possibleItemSlots) do
        local equippedItem = LootCompare:GetItemInSlot(playerGuid, itemSlot)
        local _, _, _, equippedItemLevel, _, _, equippedItemSubType = GetItemInfo(equippedItem);

        if lootedItemLevel > equippedItemLevel
            and lootedItemSubType == equippedItemSubType
            and (lowestIlvlItem == nil or equippedItemLevel < lowestItemLevel) then

            lowestIlvlItem = equippedItem;
            lowestItemLevel = equippedItemLevel;
        end
    end

    return lowestIlvlItem;
end

function LootCompare:CheckForPartyMemberUpgrade(looterName, looterGUID, lootedItemLink)

    local playerGuidToEquippedItemMap = {}
    local cacheSize = table.getn(LootCompare.CachedInventories)
    
    if cacheSize < GetNumGroupMembers() - 1 then
        print("*LootCompare* Inventory cache size != party size when trying to compare items! Cache size: " .. cacheSize .. "   Party Size: " .. GetNumGroupMembers())
    end

    for playerGuid, _ in pairs(LootCompare.CachedInventories) do

        if playerGuid ~= looterGUID then
            local equippedItem = LootCompare:IsUpgrade(playerGuid, lootedItemLink);

            if equippedItem ~= nil then
                tinsert(playerGuidToEquippedItemMap, playerGuid, equippedItem)
            end
        end
    end

    if table.getn(playerGuidToEquippedItemMap) == 0 then
        return;
    end

    SendChatMessage(looterName .. " looted " .. lootedItemLink .. ". It's an upgrade for:", "PARTY", nil, nil)
    
    for playerGuid, equippedItem in pairs(playerGuidToEquippedItemMap) do

        local playerName = LootCompare:GetUnitName(playerGuid)
        SendChatMessage(playerName .. " - Equipped = " .. equippedItem .. ".", "PARTY", nil, nil)
    end    
end