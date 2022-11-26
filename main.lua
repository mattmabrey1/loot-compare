-- "CHAT_MSG_LOOT" event

-- GetInventoryItemLink func to read other players currently equipped slot

-- https://wow.gamepedia.com/CHAT_MSG_LOOT

-- https://wowwiki.fandom.com/wiki/API_GetItemInfo

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemID

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemLink

local lastUpdateTimeForPlayer = {}

-- Functions Section
function LootCompare.GetUnitId(GUID)

    if LootCompare.CachedUnitIDs[GUID] == nil then
        print("No cached unit ID found for GUID " .. GUID.. ".")
        return nil;
    end

    return LootCompare.CachedUnitIDs[GUID];
end

function LootCompare:TryCacheInventory(GUID)

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
    if not LootCompare.IsInParty() then
        return;
    end
    
    LootCompare.TimeSinceLastInspect = LootCompare.TimeSinceLastInspect + elapsed; 	

    -- Inspect requests take time so we need to throttle while we wait for one to complete
    if LootCompare.GuidForOutstandingInspectRequest ~= nil and LootCompare.TimeSinceLastInspect < LootCompare.InspectThrottleSec then
        return;
    end
    
    LootCompare.TryCacheInventory(LootCompare.PlayerGuid)

    for GUID, _ in LootCompare.CachedUnitIDs do

        -- only try inspecting one player at a time
        if LootCompare.TryInspect(GUID) then
            LootCompare.TimeSinceLastInspect = 0
            return
        end
    end
end

function LootCompare:TryInspect(GUID)
    
    local UnitID = LootCompare.CachedUnitIDs[GUID]

    if UnitID == nil then
        print("No cached unit ID found for GUID " .. GUID.. ".")
        return;
    end

    if not UnitIsConnected(UnitID) then
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

function LootCompare:CachePartyGuids()
    local members = GetNumGroupMembers() - 1
    local GUID = nil
    local UID = nil

    for N = 1, members do

        UID = "party" .. N
        GUID = UnitGUID(UID)

        if GUID ~= nil then
            LootCompare.CachedUnitIDs[GUID] = UID
        else
            print("*LootCompare* Failed to get GUID for unit " .. UID.. ".")
        end
    end
end

function LootCompare:CompareLoot(lootedItemLink, looterName)

    if LootCompare.IsInParty() == false then
        return;
    end

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
end

function LootCompare:GetItemSlotForPlayer(playerGuid, itemSlotId)

    local playerInventory = LootCompare.CachedInventories[playerGuid];

    if playerInventory == nil then
        local playerName = UnitName(LootCompare.CachedUnitIDs[playerGuid])
        print("*LootCompare* Cannot get item slot {".. itemSlotId .. "} for " .. playerName .. " since their inventory wasn't cached!")
        return nil
    end

    local item = playerInventory[itemSlotId];

    if item == nil then
        local playerName = UnitName(LootCompare.CachedUnitIDs[playerGuid])
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
        return false;
    end

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

    local upgradeExists = false

    local upgradeFor = {}

    local cacheSize = 0

    for playerGuid, inventory in pairs(LootCompare.CachedInventories) do

        if playerGuid == looterGUID then
            continue;
        end

        cacheSize = cacheSize + 1

        if LootCompare.IsUpgrade(playerGuid, lootedItemLink) then
            tinsert(upgradeFor[playerName], itemLink)
        end
    end

    if table.getn(LootCompare.CachedInventories) < GetNumGroupMembers() - 1 then
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