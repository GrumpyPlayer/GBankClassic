local addonName, GBCR = ...

GBCR.Inventory = {}
local Inventory = GBCR.Inventory

local Globals = GBCR.Globals
local ipairs = Globals.ipairs
local math_min = Globals.math_min
local pairs = Globals.pairs
local select = Globals.select
local string_byte = Globals.string_byte
local string_len = Globals.string_len
local table_sort = Globals.table_sort
local tostring = Globals.tostring
local type = Globals.type
local wipe = Globals.wipe

local After = Globals.After
local GetContainerItemInfo = Globals.GetContainerItemInfo
local GetContainerNumFreeSlots = Globals.GetContainerNumFreeSlots
local GetContainerNumSlots = Globals.GetContainerNumSlots
local GetInboxHeaderInfo = Globals.GetInboxHeaderInfo
local GetInboxItem = Globals.GetInboxItem
local GetInboxItemLink = Globals.GetInboxItemLink
local GetInboxNumItems = Globals.GetInboxNumItems
local GetItemInfo = Globals.GetItemInfo
local GetItemInventoryTypeByID = Globals.GetItemInventoryTypeByID
local GetMoney = Globals.GetMoney
local GetServerTime = Globals.GetServerTime
local attachementsMaxReceive = Globals.ATTACHMENTS_MAX_RECEIVE
local bankContainer = Globals.BANK_CONTAINER
local numBankGenericSlots = Globals.NUM_BANKGENERIC_SLOTS

local Constants = GBCR.Constants

-- Sort items displayed in the UI based on the selected sort mode
local function sort(self, items, mode)
    if not items then
        return
    end

    table_sort(items, Constants.SORT_COMPARATORS[mode] or Constants.SORT_COMPARATORS.default)
end

-- Retrieve uncached item information for the UI as fast as possible
local function getItems(self, items, callback)
    if not items or type(items) ~= "table" then
        callback({})

        return
    end

    local list = {}
    local keys = {}
    for k in pairs(items) do
        keys[#keys + 1] = k
    end

    local totalKeys = #keys
    local currentIndex = 1
    local batchSize = Constants.LIMITS.BATCH_SIZE
    local callbackFired = false

    if totalKeys == 0 then
        callback(list)

        return
    end

	local options = GBCR.Options
    local debugEnabled = options:IsDebugEnabled() and options:IsCategoryEnabled("ITEM")

    local function processBatch()
        local limit = math_min(currentIndex + batchSize - 1, totalKeys)

        for i = currentIndex, limit do
            local key = keys[i]
            local item = items[key]

            if item and type(item) == "table" and item.itemId and item.itemId > 0 then
                local itemId = item.itemId
                local itemLink = item.itemLink

				if debugEnabled then
					GBCR.Output:Debug("ITEM", "Processing wrapper: itemId=%s, itemLink=%s, originalItemId=%s", tostring(itemId), tostring(itemLink), tostring(item.itemId))

					if itemLink then
						GBCR.Output:Debug("ITEM", "Item %d has itemLink, using directly", itemId)
					end
				end

                local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(itemLink or itemId)

                if name then
					if debugEnabled then
						GBCR.Output:Debug("ITEM", "Item %d already cached", itemId)
					end

                    if not item.itemInfo then
                        item.itemInfo = { class = itemClassId or 0, subClass = itemSubClassId or 0, equipId = GetItemInventoryTypeByID(itemId) or 0, rarity = rarity or 1, name = name, level = level or 1, price = price or 0, icon = icon or 134400 }
                    end
                    list[#list + 1] = item
                else
                    if not item.itemInfo then
                        item.itemInfo = { class = 0, subClass = 0, equipId = 0, rarity = 1, name = "Item " .. tostring(itemId), level = 1, price = 0, icon = 134400 }
                    end
                    list[#list + 1] = item
                end
            end
        end

        currentIndex = limit + 1

        if currentIndex > totalKeys then
            if not callbackFired then
                callbackFired = true
                callback(list)
            end
        else
            After(0, processBatch)
        end
    end

    processBatch()
end

-- Retrieve itemInfo if we're still lacking it for a given search result
local function getInfo(self, itemId, itemLink)
    self.infoCache = self.infoCache or {}

    local key = itemLink or itemId
    local cached = self.infoCache[key]
    if cached then
        return cached
    end

	local name, rarity, level, icon, price, itemClassId, itemSubClassId

	-- Try itemLink first if available
	if itemLink and itemLink ~= "" then
		name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(itemLink)
	end

	-- Fallback to itemId if itemLink didn't work
	if not name and itemId and itemId > 0 then
		name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(itemId)
	end

    local result

	-- If still no data, return basic info with itemId only and the default grey question mark icon
    if not name then
        result = { class = 0, subClass = 0, equipId = 0, rarity = 1, name = "Item " .. tostring(itemId or "?"), level = 1, price = 0, icon = 134400 }
    else
        local equip = GetItemInventoryTypeByID(itemId)
        result = { class = itemClassId or 0, subClass = itemSubClassId or 0, equipId = equip or 0, rarity = rarity or 1, name = name, level = level or 1, price = price or 0, icon = icon or 134400 }
    end

    self.infoCache[key] = result

    return result
end

---

-- Get normalized item key for deduplication
-- Format: itemId:enchant:suffix (3 parts)
local function getItemKey(self, itemLink)
    if not itemLink or itemLink == "" then
        return ""
    end

    local cached = self.globalLinkKeyCache[itemLink]
    if cached ~= nil then
        return cached
    end

    local itemId, enchant, _, _, _, _, suffix = itemLink:match("|Hitem:([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")

	-- Return itemId, itemId:enchant, itemId::suffix, or itemId:enchant:suffix
	-- While unique (the 8th part) contains content, just the itemId + enchant + suffix are sufficient to recreate the corect item link
    local key
    if suffix and suffix ~= "" and suffix ~= "0" then
        key = itemId .. ":" .. (enchant or "") .. ":" .. suffix
    elseif enchant and enchant ~= "" and enchant ~= "0" then
        key = itemId .. ":" .. enchant
    else
        key = itemId
    end

    self.globalLinkKeyCache[itemLink] = key

    return key
end

-- Check if an item needs its itemLink preserved based on item class
local function needsLink(self, itemLink)
	if not itemLink then
        return false
    end

   	local classID = select(12, GetItemInfo(itemLink))

	-- If item isn't cached, preserve the itemLink to avoid losing suffix data
	if classID == nil then
		return true
	end

	-- Gear (weapons/armor) can have random suffixes, so itemLink is required
    return Constants.ITEM_CLASSES_NEEDING_LINK[classID] == true
end

-- Aggregate items from bags, bank, and mail and speed up link parsing across all sources
local function aggregateInto(self, targetState, sourceItems)
    if not sourceItems then
        return
    end

    local function getKey(item)
        local itemLink = item.itemLink
        if not itemLink then
            return item.itemId
        end

        if needsLink(self, itemLink) then
            local key = getItemKey(self, itemLink)
            if key and key ~= "" then
                return key
            end
        else
            item.itemLink = nil
        end

        return item.itemId
    end

    for i = 1, #sourceItems do
        local item = sourceItems[i]

        if type(item) == "table" and item.itemId then
            local count = item.itemCount or 1
            local key = getKey(item)

            local existing = targetState.byKey[key]
            if existing then
                existing.itemCount = existing.itemCount + count
                if not existing.itemLink and item.itemLink then
                    existing.itemLink = item.itemLink
                end
            else
                local newItem = { itemId = item.itemId, itemCount = count, itemLink = item.itemLink, itemInfo = item.itemInfo }
                targetState.byKey[key] = newItem
                targetState.items[#targetState.items + 1] = newItem
            end
        end
    end
end

-- Helper to recalculate aggregate alt.items from bank, bags, mail, and money
local function recalculateAggregatedItems(self, bankData, bagData, mailData, alt)
    wipe(self.aggregateStateItems)
    wipe(self.aggregateStateByKey)

    local targetState = {
        items = self.aggregateStateItems,
        byKey = self.aggregateStateByKey
    }

    if bankData then
        aggregateInto(self, targetState, bankData)
    end

    if bagData then
        aggregateInto(self, targetState, bagData)
    end

    if mailData then
        aggregateInto(self, targetState, mailData)
    end

    if not alt.items then
        alt.items = {}
    else
        wipe(alt.items)
    end

    for i = 1, #self.aggregateStateItems do
        alt.items[i] = self.aggregateStateItems[i]
    end

    GBCR.Output:Debug("INVENTORY", "Aggregation finished: %d unique items found across bank, bags, and mail.", #alt.items)
end

-- Compute a hash of money and all items to be able to detect inventory changes
local function computeItemsHash(self, items, money)
    local sum = money % 2147483647

    if not items or type(items) ~= "table" then
        return sum
    end

    wipe(self.hashItemsPool)
    local position = 0

    for _, item in ipairs(items) do
        if item and item.itemId and item.itemId > 0 then
            position = position + 1
            self.hashItemsPool[position] = item
        end
    end

    table_sort(self.hashItemsPool, function(a, b)
        local aKey = (a.itemLink and needsLink(self, a.itemLink)) and getItemKey(self, a.itemLink) or tostring(a.itemId)
        local bKey = (b.itemLink and needsLink(self, b.itemLink)) and getItemKey(self, b.itemLink) or tostring(b.itemId)

        if aKey == bKey then
            return (a.itemCount or 1) < (b.itemCount or 1)
        end

        return aKey < bKey
    end)

    for i = 1, position do
        local item = self.hashItemsPool[i]
        local itemCount = item.itemCount or 1
        local itemIdentity = (item.itemLink and needsLink(self, item.itemLink)) and getItemKey(self, item.itemLink) or tostring(item.itemId)

        for j = 1, string_len(itemIdentity) do
            sum = (sum * 31 + string_byte(itemIdentity, j)) % 2147483647
        end

        sum = (sum * 31 + itemCount) % 2147483647
    end

    return sum
end

-- Helper to determine if the bank has been opened
local function isBankAvailable(self)
    local _, bagType = GetContainerNumFreeSlots(bankContainer)

    return bagType ~= nil
end

-- Helper to scan the contents of one bag
local function scanBag(self, bag, slots, targetTable)
    for slot = 1, slots do
        local itemInfo = GetContainerItemInfo(bag, slot)

        if itemInfo then
            local key = itemInfo.hyperlink and getItemKey(self, itemInfo.hyperlink) or itemInfo.itemID
            local existing = targetTable[key]

            if existing then
                existing.itemCount = existing.itemCount + itemInfo.stackCount
            else
                targetTable[key] = { itemId = itemInfo.itemID, itemCount = itemInfo.stackCount, itemLink = itemInfo.hyperlink }
            end
        end
    end
end

-- Helper to scan the contents of all bags
local function scanBags(self, bagTable)
    wipe(self.bagScanCache)

    for bag = 0, 4 do
        scanBag(self, bag, GetContainerNumSlots(bag), self.bagScanCache)
    end

    local count = 0
    for _, item in pairs(self.bagScanCache) do
        count = count + 1
        bagTable[count] = item
    end
end

-- Helper to scan all bank contents when at the bank
local function scanBank(self, bankTable)
    if isBankAvailable(self) then
        wipe(self.bankScanCache)

        scanBag(self, bankContainer, numBankGenericSlots, self.bankScanCache)

        for bag = 5, 11 do
            scanBag(self, bag, GetContainerNumSlots(bag), self.bankScanCache)
        end

        local count = 0
        for _, item in pairs(self.bankScanCache) do
            count = count + 1
            bankTable[count] = item
        end
    end
end

-- Helper to scan all mail contents when opening the mailbox
local function scanMailInventory(self, mailTable)
	if not Inventory.mailHasUpdated then
		GBCR.Output:Debug("INVENTORY", "scanMailInventory called but mailHasUpdated=false, returning nil")

		return nil
	end

    wipe(self.mailScanCache)
    local numItems = GetInboxNumItems()

	GBCR.Output:Debug("INVENTORY", "Starting mailbox scan: %d mail messages", numItems)

    for i = 1, numItems do
        local _, _, _, _, _, CODAmount, _, hasItem = GetInboxHeaderInfo(i)

        if hasItem and CODAmount == 0 then
            for j = 1, attachementsMaxReceive do
                local name, itemId, _, count = GetInboxItem(i, j)

                if itemId and name then
                    local itemLink = GetInboxItemLink(i, j)

                    if not itemLink and itemId then
                        itemLink = select(2, GetItemInfo(itemId))
                    end

                    local storageLink = nil
                    if itemLink and needsLink(self, itemLink) then
                        storageLink = itemLink
                    end

                    local key = getItemKey(self, itemLink) or itemId
                    local existing = self.mailScanCache[key]

                    if existing then
                        existing.itemCount = existing.itemCount + count

						GBCR.Output:Debug("INVENTORY", "Item %s: merged (key=%s) added %d, total now %d", name, key, count, existing.itemCount)
                    else
                        self.mailScanCache[key] = { itemId = itemId, itemCount = count, itemLink = storageLink }

						GBCR.Output:Debug("INVENTORY", "New item in mailbox: %s (itemId: %d, itemCount: %d, itemLink: %s, Key: %s)", name, itemId, count, storageLink and "preserved" or "stripped", key)
                    end
                end
            end
        end
    end

    local count = 0
    for _, item in pairs(self.mailScanCache) do
        count = count + 1
        mailTable[count] = item
    end

	GBCR.Output:Debug("INVENTORY", "Mail scan complete: %d unique items across %d mail messages", count, numItems)

    return true
end

-- Helper total scan all items in bags, bank, and mail
local function scanInventory(self)
    if self.eventsRegistered and not self.hasUpdated then
        return
    end

    local info = GBCR.Database.savedVariables
    if not info then
        return
    end

    local guildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
	if not guildBankAlts or #guildBankAlts == 0 then
		return
	end

    local player = GBCR.Guild:GetNormalizedPlayer()
    local isBank = false
    for i = 1, #guildBankAlts do
        local normV = GBCR.Guild:NormalizeName(guildBankAlts[i]) or guildBankAlts[i]
        if normV == player then
            isBank = true

            break
        end
    end

    if not isBank or not GBCR.Options:GetInventoryTrackingEnabled() then
		return
	end

    local alt = info.alts and info.alts[player] or {}

    if not alt.cache then alt.cache = {} end
    if not alt.cache.bank then alt.cache.bank = { items = {} } end
    if not alt.cache.bags then alt.cache.bags = { items = {} } end
    if not alt.cache.mail then alt.cache.mail = { items = {} } end

    if isBankAvailable(self) then
        wipe(alt.cache.bank.items)
        scanBank(self, alt.cache.bank.items)
    end

    wipe(alt.cache.bags.items)
    scanBags(self, alt.cache.bags.items)

    local money = GetMoney()
    alt.money = money

    if self.mailHasUpdated then
        wipe(alt.cache.mail.items)
        scanMailInventory(self, alt.cache.mail.items)
        self.mailHasUpdated = false
    end

    recalculateAggregatedItems(self, alt.cache.bank.items, alt.cache.bags.items, alt.cache.mail.items, alt)

    local previousItemsHash = alt.itemsHash
    local currentItemsHash = computeItemsHash(self, alt.items, money)
    alt.itemsHash = currentItemsHash

    if (not previousItemsHash and currentItemsHash) or currentItemsHash ~= previousItemsHash then
        alt.version = GetServerTime()

		GBCR.Output:Debug("INVENTORY", "Inventory changed for %s, version updated to %d (itemsHash=%s)", player, alt.version, tostring(currentItemsHash))
	else
		GBCR.Output:Debug("INVENTORY", "No inventory changes for %s, version unchanged (itemsHash=%s)", player, tostring(currentItemsHash))
    end

	if not info.alts then
		info.alts = {}
	end
    info.alts[player] = alt

    GBCR.Protocol:Share()
end

-- Keep track that any event impacting the inventory (bags, bank, mail) has been triggered
local function onUpdateStart(self)
    self.hasUpdated = true
end

-- Start scanning inventory (bags, bank, mail) when updates (certain event triggers) have completed
local function onUpdateStop(self)
	GBCR.Output:Debug("INVENTORY", "OnUpdateStop called, hasUpdated=%s", tostring(self.hasUpdated))

    if self.hasUpdated then
		GBCR.Output:Debug("INVENTORY", "Calling scan")
        scanInventory(self)
		GBCR.Output:Debug("INVENTORY", "Scan completed")

		GBCR.UI:QueueUIRefresh()
	else
		GBCR.Output:Debug("INVENTORY", "Skipping scan because hasUpdated is false")
    end

    self.hasUpdated = false
end

-- Initialize caches
local function init(self)
    self.globalLinkKeyCache = {}
    self.aggregateStateItems = {}
    self.aggregateStateByKey = {}
    self.bagScanCache = {}
    self.bankScanCache = {}
    self.mailScanCache = {}
    self.hashItemsPool = {}
end

-- Export functions for other modules
Inventory.Sort = sort
Inventory.GetItems = getItems
Inventory.GetInfo = getInfo

Inventory.GetItemKey = getItemKey
Inventory.NeedsLink = needsLink
Inventory.AggregateInto = aggregateInto
Inventory.ComputeItemsHash = computeItemsHash
Inventory.OnUpdateStart = onUpdateStart
Inventory.OnUpdateStop = onUpdateStop
Inventory.Init = init