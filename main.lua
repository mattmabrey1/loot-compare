-- Functions Section
function LootCompare:GetUnitId(GUID)

    if LootCompare.GuidToUnitIdMap[GUID] == nil then
        print("*LootCompare* No cached unit ID found for GUID " .. GUID.. ".")
        return nil;
    end

    return LootCompare.GuidToUnitIdMap[GUID];
end

function LootCompare:GetUnitName(GUID)

    local unitId = LootCompare:GetUnitId(GUID)
    if unitId == nil then
        print("*LootCompare* Failed to get unit Id to get unit's name for GUID " .. GUID.. ".")
        return nil;
    end
    
    return UnitName(unitId);
end

function LootCompare:CacheInventory(GUID)

    if LootCompare.CachedInventories[GUID] == nil then
        LootCompare.CachedInventories[GUID] = {}
    end
    
    local UnitID = LootCompare:GetUnitId(GUID);
    if UnitID == nil then
        print("*LootCompare* Failed to cache inventory because UnitID was nil for " .. GUID .. ".")
        return;
    end

    for i = 1, 18 do
        LootCompare.CachedInventories[GUID][i] = GetInventoryItemLink(UnitID, i)
    end
    
    print(UnitName(UnitID) .. " (".. UnitID .. ") inventory cached.")
end


function LootCompare:TryCachePartyInventories()

    -- Inspect requests take time so we need to wait for one to complete
    if LootCompare.GuidForOutstandingInspectRequest ~= nil and LootCompare.TimeSinceLastInspect < LootCompare.InspectWaitSec then
        return;
    end
    
    LootCompare:CacheInventory(LootCompare.PlayerGuid)

    for GUID, UnitId in pairs(LootCompare.GuidToUnitIdMap) do
        -- only try inspecting one player at a time
        if LootCompare:TryInspectPlayer(GUID, UnitId) then
            LootCompare.GuidForOutstandingInspectRequest = GUID;
            LootCompare.TimeSinceLastInspect = 0;
            return;
        end
    end
end

function LootCompare:TryInspectPlayer(GUID, unitId)
    
    if not UnitIsConnected(unitId) then
        print("*LootCompare* Cannot inspect player ".. GUID .. " since they're not connected!")
        return false;
    end

    local lastInspectTime = LootCompare.LastInspectTimeForPlayer[GUID];
 
    -- Only try to inspect the player and cache their inventory once the throttle has passed
    if lastInspectTime ~= nil and (GetTime() - lastInspectTime) < LootCompare.InspectThrottleSec then
        return false;
    end
    
    -- !!!!! ADD RANGE CHECK - "and CheckInteractDistance(UID, 1)"
    print("*LootCompare* Sending inspect for ".. unitId .. "!")
    NotifyInspect(unitId)

    return true;
end

function LootCompare:MapPartyMemberGuidsToUnitIds()
    local guid = nil
    local unitId = nil
    local members = GetNumGroupMembers() - 1

    LootCompare.GuidToUnitIdMap[guid] = {}

    for N = 1, members do

        unitId = "party" .. N
        guid = UnitGUID(unitId)

        if guid ~= nil then
            LootCompare.GuidToUnitIdMap[guid] = unitId
        else
            print("*LootCompare* Failed to get GUID for unit " .. unitId.. ".")
        end
    end

    -- remove cached inventories for players no longer in the party
    for playerGuid, _ in pairs(LootCompare.CachedInventories) do

        if LootCompare.GuidToUnitIdMap[playerGuid] == nil then
            print("*LootCompare* Removing cached inventory for GUID " .. playerGuid.. ".")
            LootCompare.CachedInventories[playerGuid] = nil
        end
    end
end

function LootCompare:OnItemLooted(lootedItemLink, looterName)

    local s, _ = string.find(looterName, '-', 1, true)
    looterName = strsub(looterName, 1, s - 1)
    local looterGUID = UnitGUID(looterName);

    if looterGUID ~= nil then
        print("*LootCompare* Failed to get the GUID for looter " .. looterName .. "!")
        return;
    end

    LootCompare:CheckForUpgrades(looterGUID, lootedItemLink)
end

function LootCompare:GetItemInSlot(playerGuid, itemSlotId)

    local playerInventory = LootCompare.CachedInventories[playerGuid];

    if playerInventory == nil then
        local playerName = LootCompare:GetUnitName(playerGuid)
        print("*LootCompare* Cannot get item slot {".. itemSlotId .. "} for " .. playerName .. " since their inventory wasn't cached!")
        return nil
    end

    local item = playerInventory[itemSlotId];

    if item == nil then
        local playerName = LootCompare:GetUnitName(playerGuid)
        print("*LootCompare* Undefined item slot {".. itemSlotId .. "} for " .. playerName .. " inventory cache!")
        return nil
    end

    return item;
end

function LootCompare:CheckForUpgrades(looterName, looterGUID, lootedItemLink)

    local playerGuidToEquippedItemMap = {}
    local cacheSize = table.getn(LootCompare.CachedInventories)
    local _, _, _, lootedItemLevel, _, _, lootedItemSubType, _, lootedItemSlotName = GetItemInfo(lootedItemLink)

    if cacheSize < GetNumGroupMembers() - 1 then
        print("*LootCompare* Inventory cache size != party size when trying to compare items! Cache size: " .. cacheSize .. "   Party Size: " .. GetNumGroupMembers())
    end

    for playerGuid, _ in pairs(LootCompare.CachedInventories) do

        local equippedItem = LootCompare:IsUpgrade(playerGuid, lootedItemSlotName, lootedItemLevel, lootedItemSubType);

        if equippedItem ~= nil then

            if playerGuid == looterGUID then
                print("*LootCompare* " .. lootedItemLink .. " was an upgrade for looter's equipped " .. equippedItem .. " so no comparison will take place.")
                return;
            else
                tinsert(playerGuidToEquippedItemMap, playerGuid, equippedItem)
            end
        end
    end

    if table.getn(playerGuidToEquippedItemMap) == 0 then
        return;
    end

    -- SendChatMessage(looterName .. " looted " .. lootedItemLink .. ". It's an upgrade for:", "PARTY", nil, nil)
    print(looterName .. " looted " .. lootedItemLink .. ". It's an upgrade for:")
    
    for playerGuid, equippedItem in pairs(playerGuidToEquippedItemMap) do

        local playerName = LootCompare:GetUnitName(playerGuid)
        local _, _, _, equippedItemLevel = GetItemInfo(lootedItemLink)
        local itemLevelDifference = lootedItemLevel - equippedItemLevel
        print(playerName .. " - " .. equippedItem .. ". +" .. itemLevelDifference .. " ILVL")
    
        -- SendChatMessage(playerName .. " - Equipped = " .. equippedItem .. ".", "PARTY", nil, nil)
    end    
end

-- Determines whether the lootedItemLink item is an upgrade and returns the lowest equipped ILVL for the item slot
function LootCompare:IsUpgrade(playerGuid, lootedItemSlotName, lootedItemLevel, lootedItemSubType)

    -- Translate item slot name to the item slot IDs
    local possibleItemSlots = LootCompare.ItemSlotNameToIdsMap[lootedItemSlotName]

    if possibleItemSlots == nil then
        print("*LootCompare* Couldn't find item slots for item slot name " .. lootedItemSlotName .. ".")
        return nil;
    end

    local lowestIlvlItem = nil;
    local lowestItemLevel = 0;

    for _, itemSlot in pairs(possibleItemSlots) do
        local equippedItem = LootCompare:GetItemInSlot(playerGuid, itemSlot)

        if equippedItem ~= nil then
            local _, _, _, equippedItemLevel, _, _, equippedItemSubType = GetItemInfo(equippedItem);

            if lootedItemLevel > equippedItemLevel and lootedItemSubType == equippedItemSubType and (lowestIlvlItem == nil or equippedItemLevel < lowestItemLevel) then
    
                lowestIlvlItem = equippedItem;
                lowestItemLevel = equippedItemLevel;
            end
        end
    end

    return lowestIlvlItem;
end