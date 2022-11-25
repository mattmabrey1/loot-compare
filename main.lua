-- "CHAT_MSG_LOOT" event

-- GetInventoryItemLink func to read other players currently equipped slot

-- https://wow.gamepedia.com/CHAT_MSG_LOOT

-- https://wowwiki.fandom.com/wiki/API_GetItemInfo

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemID

-- https://wowwiki.fandom.com/wiki/API_GetInventoryItemLink

local cachedInventories = {}
local cachedUnitIDs = {}
local inspectedPlayers = {}

local PlayerLoginFrame = CreateFrame("Frame")
PlayerLoginFrame:RegisterEvent("PLAYER_LOGIN")

local InspectFrame = CreateFrame("Frame")
InspectFrame:RegisterEvent("INSPECT_READY")

local ChatLootFrame = CreateFrame("Frame")
ChatLootFrame:RegisterEvent("CHAT_MSG_LOOT")

local GroupChangeFrame = CreateFrame("Frame")
GroupChangeFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

local UpdateFrame = CreateFrame("Frame")


-- Globals Section
LootCompare = {}

itemIDs = {
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

local LootCompare_UpdateInterval = 5.0; -- How often the OnUpdate code will run (in seconds)
local LootCompare_ResetCacheInterval = 180.0; -- How often the OnUpdate code will run (in seconds)
local TimeSinceLastUpdate = 0

local allPlayersInspected = false

cachedUnitIDs[UnitGUID("player")] = "player"

-- Functions Section

function LootCompare:CacheInventory(GUID)

    local UnitID = cachedUnitIDs[GUID]

    if UnitID ~= nil and inspectedPlayers[GUID] == nil then

        local unitInventory = {}

        print(UnitName(UnitID) .. " (".. UnitID .. ") inventory cached")

        for i = 1, 18 do
            unitInventory[i] = GetInventoryItemLink(UnitID, i)
        end

        cachedInventories[GUID] = unitInventory
        inspectedPlayers[GUID] = true
    end
end

UpdateFrame:HookScript("OnUpdate", function(self, elapsed)

    if IsInGroup() and IsInRaid() == false then

        TimeSinceLastUpdate = TimeSinceLastUpdate + elapsed; 	

        if allPlayersInspected then
            
            if (TimeSinceLastUpdate > LootCompare_ResetCacheInterval) then
                
                print("*LootCompare* Inventory Caches expired, reloading all inventories!")
                TimeSinceLastUpdate = 0

                -- Do garbage collection for any past party members cached inventories
                for GUID, inventory in pairs(cachedInventories) do
            
                    if inspectedPlayers[GUID] == nil then
                        cachedInventories[GUID] = nil
                        cachedUnitIDs[GUID] = nil
                    end
            
                end

                inspectedPlayers = {}

                allPlayersInspected = false
            end

        elseif (TimeSinceLastUpdate > LootCompare_UpdateInterval) then

            TimeSinceLastUpdate = 0
            local inspectsSent = 0

            local members = GetNumGroupMembers() - 1
            local GUID = ""
            local UID = ""
            
            if inspectedPlayers[UnitGUID("player")] == nil then
                LootCompare:CacheInventory(UnitGUID("player"))
            end

            for N = 1, members do 
        
                UID = "party" .. N
                GUID = UnitGUID(UID)

                cachedUnitIDs[GUID] = UID

                -- !!!!! ADD RANGE CHECK - "and CheckInteractDistance(UID, 1)"
                if inspectsSent < 1 and UnitIsConnected(UID) and inspectedPlayers[GUID] == nil then

                    inspectsSent = inspectsSent + 1
                    print("*LootCompare* Inspect sent for ".. UID .. "!")
                    NotifyInspect(UID)

                end
            end
    
            if inspectsSent == 0 then
                allPlayersInspected = true
            end
        end
    end

end)

InspectFrame:SetScript("OnEvent", function(self, event, ...)
    
    if IsInGroup() and IsInRaid() == false then 
        local GUID = ...;

        LootCompare:CacheInventory(GUID)
    end

end)

-- When an item is looted by a player and it is displayed in chat check if it's an upgrade for them
ChatLootFrame:SetScript("OnEvent", function(self, event, ...)

    if IsInGroup() and IsInRaid() == false then 

        local itemLink, playerName = ...
    
        local looterName = playerName;

        local s, e = string.find(looterName, '-', 1, true)
        looterName = strsub(looterName, 1, s - 1)

        local lootedItemName, lootedItemLink, lootedItemRarity, lootedItemLevel, lootedItemMinLevel, lootedItemType,
        lootedItemSubType, lootedItemStackCount, lootedItemEquipLoc, lootedItemTexture, lootedItemSellPrice = GetItemInfo(itemLink)

        -- Translate item equip location name to possible Slot IDs
        local slotIDs = itemIDs[lootedItemEquipLoc]

        looterGUID = UnitGUID(looterName)

        -- Check if the looted item is an upgrade item if it has slotIDs (is an equippable item)
        if slotIDs ~= nil and looterGUID ~= nil then

            if cachedInventories[looterGUID] == nil then 

                print("*LootCompare* No cached inventory for the player that just looted an item!")

            else

                local isUpgrade = true

                for i = 1, table.getn(slotIDs) do
                    local slotID = slotIDs[i]

                    local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType,
                    itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(cachedInventories[looterGUID][slotID])

                    if itemLevel >= lootedItemLevel then
                        isUpgrade = false
                    end
                end
            
                
                if isUpgrade == false then
                    LootCompare:CheckForUpgrades(looterName, looterGUID, lootedItemLink, lootedItemLevel, lootedItemSubType, slotIDs)
                else 
                    print("*LootCompare* " .. lootedItemLink .. " was an upgrade so no comparison will take place.")
                end

            end
        end
    end

end)

function LootCompare:CheckForUpgrades(looterName, looterGUID, lootedItemLink, lootedItemLevel, lootedItemSubType, slotIDs)

    local slotID = 0

    local upgradeExists = false

    local upgradeFor = {}

    local cacheSize = 0

    for GUID, inventory in pairs(cachedInventories) do

        if GUID ~= looterGUID then

            cacheSize = cacheSize + 1

            for s = 1, table.getn(slotIDs) do

                slotID = slotIDs[s]

                local playerName = UnitName(cachedUnitIDs[GUID])

                if inventory[slotID] ~= nil then

                    local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType,
                    itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(inventory[slotID])

                    -- lootedItemLevel > itemLevel 
                    
                    if lootedItemLevel > itemLevel and lootedItemSubType == itemSubType then

                        if upgradeFor[playerName] == nil then
                            upgradeFor[playerName] = {}
                        end
                        
                        tinsert(upgradeFor[playerName], itemLink)
                        upgradeExists = true
                    end
                else
                    print("*LootCompare* Undefined {".. slotID .. "} slot for " .. playerName .. " inventory cache!")
                end

            end
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
