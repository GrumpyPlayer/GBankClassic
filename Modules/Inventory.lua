local addonName, GBCR = ...

GBCR.Inventory = {}
local Inventory = GBCR.Inventory

local Globals = GBCR.Globals
local bit_bxor = Globals.bit_bxor
local debugprofilestop = Globals.debugprofilestop
local ipairs = Globals.ipairs
local pairs = Globals.pairs
local select = Globals.select
local string_byte = Globals.string_byte
local string_find = Globals.string_find
local string_format = Globals.string_format
local string_len = Globals.string_len
local string_match = Globals.string_match
local strsplit = Globals.strsplit
local table_sort = Globals.table_sort
local tonumber = Globals.tonumber
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
local GetMoney = Globals.GetMoney
local GetServerTime = Globals.GetServerTime
local shouldYield = Globals.ShouldYield

local attachmentsMaxReceive = Globals.ATTACHMENTS_MAX_RECEIVE
local bankContainer = Globals.BANK_CONTAINER
local itemBindOnAcquire = Globals.ITEM_BIND_ON_ACQUIRE
local numBankGenericSlots = Globals.NUM_BANKGENERIC_SLOTS

local Constants = GBCR.Constants

-- Build an index of item ID and guild bank alt to be able to show a list of sources in the item tooltip
local function buildGlobalItemSourcesIndex(self, dirtyAlts, callback)
    local savedVariables = GBCR.Database.savedVariables
    if not savedVariables or not savedVariables.alts then
        if callback then
            callback()
        end

        return
    end

    if dirtyAlts and next(dirtyAlts) then
        local dirtyCount = 0

        for _ in pairs(dirtyAlts) do
            dirtyCount = dirtyCount + 1
        end

        if dirtyCount <= 8 then
            self.sourcesIndexGeneration = (self.sourcesIndexGeneration or 0) + 1

            GBCR.Output:Debug("INVENTORY", "buildGlobalItemSourcesIndex: partial rebuild (%d dirty)", dirtyCount)

            for altName in pairs(dirtyAlts) do
                local altData = savedVariables.alts[altName]
                local items = altData and altData.items

                if not items and altData and altData.itemsCompressed then
                    items = GBCR.Database.DecompressData(altData.itemsCompressed)
                end

                if items then
                    for i = 1, #items do
                        local item = items[i]
                        local id = item.itemId

                        if not id and item.itemString then
                            id = tonumber(string_match(item.itemString, "^(%d+)")) or 0
                        end

                        if id and id > 0 then
                            local sources = self.cachedSourcesPerItem[id]
                            if sources then
                                sources[altName] = nil
                                if not next(sources) then
                                    self.cachedSourcesPerItem[id] = nil
                                end
                            end
                        end
                    end
                end
            end

            for altName in pairs(dirtyAlts) do
                local altData = savedVariables.alts[altName]
                local items = altData and altData.items

                if not items and altData and altData.itemsCompressed then
                    items = GBCR.Database.DecompressData(altData.itemsCompressed)
                end

                if items then
                    for i = 1, #items do
                        local item = items[i]
                        local id = item.itemId

                        if not id and item.itemString then
                            id = tonumber(string_match(item.itemString, "^(%d+)")) or 0
                        end

                        if id and id > 0 then
                            local sources = self.cachedSourcesPerItem[id]
                            if not sources then
                                sources = {}
                                self.cachedSourcesPerItem[id] = sources
                            end

                            sources[altName] = (sources[altName] or 0) + (item.itemCount or 1)
                        end
                    end
                end
            end

            if callback then
                callback()
            end

            return
        end

        GBCR.Output:Debug("INVENTORY", "buildGlobalItemSourcesIndex: %d dirty alts, promoting to full rebuild", dirtyCount)
    end

    self.sourcesIndexGeneration = (self.sourcesIndexGeneration or 0) + 1
    local myGen = self.sourcesIndexGeneration

    GBCR.Output:Debug("INVENTORY", "buildGlobalItemSourcesIndex: full rebuild (gen %d)", myGen)
    local altsList = {}

    local altsCount = 0
    for altName, altData in pairs(savedVariables.alts) do
        if type(altData) == "table" then
            local items = altData.items
            if not items and altData.itemsCompressed then
                items = GBCR.Database.DecompressData(altData.itemsCompressed)
            end

            if items and #items > 0 then
                altsCount = altsCount + 1
                altsList[altsCount] = {name = altName, items = items}
            end
        end
    end

    wipe(self.cachedSourcesPerItem)

    local altIndex = 1
    local itemIndex = 1

    local function Resume()
        if myGen ~= self.sourcesIndexGeneration then
            return
        end

        local frameStart = debugprofilestop()
        local processedThisFrame = 0

        while altIndex <= altsCount do
            local altEntry = altsList[altIndex]
            local items = altEntry.items
            local itemsCount = #items
            local altName = altEntry.name

            while itemIndex <= itemsCount do
                local item = items[itemIndex]
                local id = item.itemId

                if not id and item.itemString then
                    local m = string_match(item.itemString, "^(%d+)")
                    id = m and tonumber(m) or 0
                end

                if id and id > 0 then
                    local sources = self.cachedSourcesPerItem[id]
                    if not sources then
                        sources = {}
                        self.cachedSourcesPerItem[id] = sources
                    end

                    sources[altName] = (sources[altName] or 0) + (item.itemCount or 1)
                end

                itemIndex = itemIndex + 1
                processedThisFrame = processedThisFrame + 1

                if shouldYield(frameStart, processedThisFrame, 50, 300) then
                    After(0, Resume)

                    return
                end
            end

            altIndex = altIndex + 1
            itemIndex = 1
        end

        if myGen ~= self.sourcesIndexGeneration then
            return
        end

        if callback then
            callback()
        end
    end

    After(0, Resume)
end

-- Get normalized item key for deduplication
-- Format: itemId:enchant:suffix (3 parts)
local function getItemKey(self, itemLink)
    if not itemLink or itemLink == "" then
        return ""
    end

    local cached = self.cachedItemKeys[itemLink]
    if cached ~= nil then
        return cached
    end

    local itemId, enchant, _, _, _, _, suffix = string_match(itemLink,
                                                             "|Hitem:([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")

    local key
    if suffix and suffix ~= "" and suffix ~= "0" then
        key = itemId .. ":" .. (enchant or "") .. ":" .. suffix
    elseif enchant and enchant ~= "" and enchant ~= "0" then
        key = itemId .. ":" .. enchant
    else
        key = itemId
    end

    self.cachedItemKeys[itemLink] = key

    return key
end

-- Helper to check if an item needs its itemLink preserved based on item class
local function needsLink(self, itemLink)
    if not itemLink then
        return false
    end

    local classID = select(12, GetItemInfo(itemLink))
    if classID ~= nil then
        return Constants.ITEM_CLASSES_NEEDING_LINK[classID] == true
    end

    local itemId = tonumber(string_match(itemLink, "|Hitem:(%d+):"))
    if itemId and itemId > 0 then
        self.pendingItemInfoLoads = self.pendingItemInfoLoads or {}
        if not self.pendingItemInfoLoads[itemId] then
            self.pendingItemInfoLoads[itemId] = true
            GetItemInfo(itemId)
        end
    end

    return true
end

-- Helper to aggregate items from bags, bank, and mail and speed up link parsing across all sources
local function aggregateInto(self, targetState, sourceItems)
    if not sourceItems then
        return
    end

    for i = 1, #sourceItems do
        local item = sourceItems[i]

        if type(item) == "table" then
            local count = item.itemCount or 1
            local key, tempLink, derivedId

            if item.itemString then
                key = item.itemString
                local p1, p2, p3 = strsplit(":", item.itemString)
                derivedId = tonumber(p1) or 0
                local enchant = tonumber(p2) or 0
                local suffix = tonumber(p3) or 0
                local itemStr = string_format("item:%d:%d:0:0:0:0:%d:0:0:0:0:0:0", derivedId, enchant, suffix)
                tempLink = string_format("|cffffffff|H%s|h[item:%d]|h|r", itemStr, derivedId)
            elseif item.itemLink then
                derivedId = item.itemId or 0

                if needsLink(self, item.itemLink) then
                    key = getItemKey(self, item.itemLink)
                    tempLink = item.itemLink
                else
                    key = getItemKey(self, item.itemLink)
                    item.itemLink = nil
                    local itemStr = string_format("item:%d:0:0:0:0:0:0:0:0:0:0:0:0", derivedId)
                    tempLink = string_format("|cffffffff|H%s|h[item:%d]|h|r", itemStr, derivedId)
                end

                if not key or key == "" then
                    key = tostring(derivedId)
                end
            end

            if key then
                local existing = targetState.byKey[key]
                if existing then
                    existing.itemCount = existing.itemCount + count
                    if not existing.itemLink and tempLink then
                        existing.itemLink = tempLink
                    end
                else
                    local newItem = {
                        itemId = derivedId,
                        itemCount = count,
                        itemLink = item.itemLink or tempLink,
                        itemString = item.itemString or (type(key) == "string" and key or tostring(key)),
                        itemInfo = item.itemInfo
                    }

                    targetState.byKey[key] = newItem
                    targetState.items[#targetState.items + 1] = newItem
                end
            end
        end
    end
end

-- Helper to recalculate aggregate alt.items from bank, bags, mail, and money
local function recalculateAggregatedItems(self, bankData, bagData, mailData, alt)
    wipe(self.aggregateStateItems)
    wipe(self.aggregateStateByKey)

    local targetState = {items = self.aggregateStateItems, byKey = self.aggregateStateByKey}

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

    local n = #self.aggregateStateItems
    for i = 1, n do
        local item = self.aggregateStateItems[i]
        item.itemId = nil
        item.itemInfo = nil
        item.lowerName = nil
        item.itemLink = nil

        alt.items[i] = item
    end

    GBCR.Output:Debug("INVENTORY", "Aggregation finished: %d unique items found across bank, bags, and mail", #alt.items)

    alt.itemsCompressed = nil

    After(0, function()
        alt.itemsCompressed = GBCR.Database.CompressData(alt.items)

        GBCR.Output:Debug("INVENTORY", "Async compression finished (%d items)", #alt.items)
    end)
end

-- Helper to sort cached items hashes
local itemsHashSort = function(a, b)
    if a.key == b.key then
        return (a.item.itemCount or 1) < (b.item.itemCount or 1)
    end

    return a.key < b.key
end

-- Helper to compute a hash of money and all items to be able to detect inventory changes
local function computeItemsHash(self, items, money)
    local sum = money
    if not items or type(items) ~= "table" then
        return sum
    end

    local position = 0

    for _, item in ipairs(items) do
        if item and item.itemString then
            position = position + 1

            local entry = self.cachedItemsHashes[position]
            if not entry then
                entry = {}
                self.cachedItemsHashes[position] = entry
            end

            entry.item = item
            entry.key = item.itemString
        end
    end

    for i = position + 1, #self.cachedItemsHashes do
        self.cachedItemsHashes[i] = nil
    end
    table_sort(self.cachedItemsHashes, itemsHashSort)

    for i = 1, position do
        local entry = self.cachedItemsHashes[i]
        local key = entry.key
        local keyLen = string_len(key)

        for j = 1, keyLen do
            sum = bit_bxor(sum * 31, string_byte(key, j))
        end

        sum = bit_bxor(sum * 31, entry.item.itemCount or 1)
    end

    return sum
end

-- Helper to determine if the bank has been opened
local function isBankAvailable()
    local _, bagType = GetContainerNumFreeSlots(bankContainer)

    return bagType ~= nil
end

-- Helper to scan the contents of one bag
local function scanBag(self, bag, slots, targetTable)
    for slot = 1, slots do
        local itemInfo = GetContainerItemInfo(bag, slot)

        if itemInfo then
            local key = itemInfo.hyperlink and getItemKey(self, itemInfo.hyperlink)
            if not key or key == "" then
                key = itemInfo.itemID
            end

            if key then
                local existing = targetTable[key]
                if existing then
                    existing.itemCount = existing.itemCount + itemInfo.stackCount
                else
                    if select(14, GetItemInfo(itemInfo.itemID)) ~= itemBindOnAcquire then
                        local entry = {}
                        entry.itemCount = itemInfo.stackCount

                        if type(key) == "string" and string_find(key, ":", 1, true) then
                            entry.itemString = key
                        else
                            entry.itemString = tostring(key)
                        end

                        targetTable[key] = entry
                    end
                end
            end
        end
    end
end

-- Helper to scan the contents of all bags
local function scanBags(self, bagTable)
    wipe(self.cachedBagItems)

    for bag = 0, 4 do
        scanBag(self, bag, GetContainerNumSlots(bag), self.cachedBagItems)
    end

    local count = 0
    for _, item in pairs(self.cachedBagItems) do
        count = count + 1
        bagTable[count] = item
    end
end

-- Helper to scan all bank contents when at the bank
local function scanBank(self, bankTable)
    if isBankAvailable() then
        wipe(self.cachedBankItems)

        scanBag(self, bankContainer, numBankGenericSlots, self.cachedBankItems)

        for bag = 5, 11 do
            scanBag(self, bag, GetContainerNumSlots(bag), self.cachedBankItems)
        end

        local count = 0
        for _, item in pairs(self.cachedBankItems) do
            count = count + 1
            bankTable[count] = item
        end
    end
end

-- Helper to scan all mail contents when opening the mailbox
local function scanMailInventory(self, mailTable)
    wipe(self.cachedMailItemKeys)
    local numItems = GetInboxNumItems()

    GBCR.Output:Debug("INVENTORY", "Starting mailbox scan: %d mail messages", numItems)

    for i = 1, numItems do
        local _, _, _, _, _, CODAmount, _, hasItem = GetInboxHeaderInfo(i)

        if hasItem and CODAmount == 0 then
            for j = 1, attachmentsMaxReceive do
                local name, itemId, _, count = GetInboxItem(i, j)

                if itemId and name then
                    local itemLink = GetInboxItemLink(i, j)
                    if not itemLink and itemId then
                        itemLink = select(2, GetItemInfo(itemId))
                    end

                    local key = getItemKey(self, itemLink) or tostring(itemId)
                    local existing = self.cachedMailItemKeys[key]

                    if existing then
                        existing.itemCount = existing.itemCount + count

                        GBCR.Output:Debug("INVENTORY", "Item %s: merged (key=%s) added %d, total now %d", name, key, count,
                                          existing.itemCount)
                    else
                        self.cachedMailItemKeys[key] = {itemString = key, itemCount = count}

                        GBCR.Output:Debug("INVENTORY", "New item in mailbox: %s (itemString: %s, itemCount: %d)", name, key, count)
                    end
                end
            end
        end
    end

    local count = 0
    for _, item in pairs(self.cachedMailItemKeys) do
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

    if not GBCR.Guild.weAreGuildBankAlt then
        return
    end

    if not GBCR.Options:GetInventoryTrackingEnabled() then
        return
    end

    local player = GBCR.Guild:GetNormalizedPlayerName()
    local alt = info.alts and info.alts[player] or {}

    if not alt.cache then
        alt.cache = {}
    end
    alt.cache.bank = alt.cache.bank or {}
    alt.cache.bags = alt.cache.bags or {}
    alt.cache.mail = alt.cache.mail or {}

    if isBankAvailable() then
        wipe(alt.cache.bank)
        scanBank(self, alt.cache.bank)
    end

    wipe(alt.cache.bags)
    scanBags(self, alt.cache.bags)

    local money = GetMoney()
    alt.money = money

    if self.mailHasUpdated then
        wipe(alt.cache.mail)
        scanMailInventory(self, alt.cache.mail)
        self.mailHasUpdated = false
    end

    recalculateAggregatedItems(self, alt.cache.bank, alt.cache.bags, alt.cache.mail, alt)

    local previousItemsHash = alt.itemsHash
    local currentItemsHash = computeItemsHash(self, alt.items, money)
    alt.itemsHash = currentItemsHash

    if (not previousItemsHash and currentItemsHash) or currentItemsHash ~= previousItemsHash then
        alt.version = GetServerTime()

        local networkMeta = GBCR.Database.savedVariables and GBCR.Database.savedVariables.networkMeta
        if networkMeta then
            networkMeta.seedCount = 0
            networkMeta.lastSeedTime = nil
            networkMeta.lastSeedTarget = nil
        end

        GBCR.Output:Debug("INVENTORY", "Inventory changed for %s, version updated to %d (itemsHash=%s)", player, alt.version,
                          tostring(currentItemsHash))

        GBCR.Protocol:SendAnnounce(GBCR.Guild:GetNormalizedPlayerName())
        GBCR.UI.Inventory:MarkAltDirty(player)
    else
        GBCR.Output:Debug("INVENTORY", "No inventory changes for %s, version unchanged (itemsHash=%s)", player,
                          tostring(currentItemsHash))
    end

    if not info.alts then
        info.alts = {}
    end
    info.alts[player] = alt
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
    self.cachedSourcesPerItem = {}
    self.sourcesIndexGeneration = 0
    self.cachedItemsHashes = {}
    self.cachedItemKeys = {}
    self.cachedMailItemKeys = {}
    self.pendingItemInfoLoads = {}
    self.aggregateStateItems = {}
    self.aggregateStateByKey = {}
    self.cachedBagItems = {}
    self.cachedBankItems = {}
end

-- Export functions for other modules
Inventory.BuildGlobalItemSourcesIndex = buildGlobalItemSourcesIndex
Inventory.GetItemKey = getItemKey
Inventory.OnUpdateStart = onUpdateStart
Inventory.OnUpdateStop = onUpdateStop
Inventory.Init = init
