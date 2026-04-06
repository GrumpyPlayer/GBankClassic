local addonName, GBCR = ...

GBCR.Search = {}
local Search = GBCR.Search

local Globals = GBCR.Globals
local next = Globals.next
local pairs = Globals.pairs
local tostring = Globals.tostring
local wipe = Globals.wipe

local Inventory = GBCR.Inventory
local Options = GBCR.Options
local Output = GBCR.Output

-- Mark a guild bank alt as dirty when receiving new data
local function markAltDirty(self, altName)
    self.dirtyAlts[altName] = true
end

-- Mark all data as dirty (e.g., database reset, initial login)
local function markAllDirty(self)
    self.needsFullRebuild = true
end

-- Helper to retrieve the unique item identity
local function getIdentity(self, itemId, itemLink)
    if not itemLink then
        return itemId
    end

    local cached = self.linkKeyCache[itemLink]
    if cached ~= nil then
        return cached or itemId
    end

    if Inventory:NeedsLink(itemLink) then
        local key = Inventory:GetItemKey(itemLink)
        if key and key ~= "" then
            self.linkKeyCache[itemLink] = key

            return key
        end
    end

    self.linkKeyCache[itemLink] = false

    return itemId
end

-- Build the search index with object pooling
local function buildSearchData(self)
    local debugEnabled = Options:IsDebugEnabled() and Options:IsCategoryEnabled("SEARCH")

    if not self.needsFullRebuild and not next(self.dirtyAlts) then
        if debugEnabled then
            Output:Debug("SEARCH", "BuildSearchData: skipped, index is up to date")
        end

        return
    end

    if debugEnabled then
        Output:Debug("SEARCH", "BuildSearchData called, fullRebuild: %s", tostring(self.needsFullRebuild))
    end

    local savedVariables = GBCR.Database.savedVariables
    local rosterGuildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
    if not savedVariables or not rosterGuildBankAlts then
        if debugEnabled then
            Output:Debug("SEARCH", "BuildSearchData: early exit due to missing data")
        end

        return
    end

    local corpus = self.searchData.corpus
    local lookup = self.searchData.lookup

    for _, bucket in pairs(lookup) do
        wipe(bucket)
    end
    wipe(corpus)

    local alts = savedVariables.alts
    local corpusNamesSeen = self.corpusNamesSeen
    local seenPairs = self.seenPairs
    local unresolved = self.unresolvedItems
    local corpusPool = self.corpusPool
    local resultPool = self.resultPool

    wipe(corpusNamesSeen)
    wipe(unresolved)

    for _, v in pairs(seenPairs) do
        wipe(v)
    end

    local unresolvedCount = 0
    local corpusCount = 0
    local resultPoolCount = 0

    for i = 1, #rosterGuildBankAlts do
        local altName = rosterGuildBankAlts[i]
        local alt = alts[altName]

        if alt and alt.items then
            local altItems = alt.items

            for j = 1, #altItems do
                local itemEntry = altItems[j]
                local itemId = itemEntry.itemId
                local itemLink = itemEntry.itemLink

                if not itemEntry.cachedIdentity then
                    itemEntry.cachedIdentity = getIdentity(self, itemId, itemLink)
                end

                if itemEntry.itemInfo and itemEntry.itemInfo.name then
                    local name = itemEntry.itemInfo.name
                    itemEntry.cachedName = name

                    local lowerName = self.lowerNameCache[name]
                    if not lowerName then
                        lowerName = name:lower()
                        self.lowerNameCache[name] = lowerName
                    end

                    if not corpusNamesSeen[name] then
                        corpusNamesSeen[name] = true
                        corpusCount = corpusCount + 1

                        local cachedEntry = corpusPool[corpusCount]
                        if not cachedEntry then
                            cachedEntry = {}
                            corpusPool[corpusCount] = cachedEntry
                        end
                        cachedEntry.name = name
                        cachedEntry.lower = lowerName
                        corpus[corpusCount] = cachedEntry
                    end
                else
                    unresolvedCount = unresolvedCount + 1
                    unresolved[unresolvedCount] = itemEntry
                end
            end
        end
    end

    local function buildLookup()
        for c = 1, #rosterGuildBankAlts do
            local altName = rosterGuildBankAlts[c]
            local alt = alts[altName]

            if alt and alt.items then
                local altSeen = seenPairs[altName]
                if not altSeen then
                    altSeen = {}
                    seenPairs[altName] = altSeen
                end

                local altItems = alt.items

                for i = 1, #altItems do
                    local itemEntry = altItems[i]
                    local name = itemEntry.cachedName

                    if name then
                        local linkHash = itemEntry.itemLink or "nil"
                        local uniqueKey = itemEntry.itemId .. "_" .. linkHash

                        if not altSeen[uniqueKey] then
                            altSeen[uniqueKey] = true

                            local bucket = lookup[name]
                            if not bucket then
                                bucket = {}
                                lookup[name] = bucket
                            end

                            resultPoolCount = resultPoolCount + 1
                            local cachedEntry = resultPool[resultPoolCount]
                            if not cachedEntry then
                                cachedEntry = {}
                                resultPool[resultPoolCount] = cachedEntry
                            end

                            cachedEntry.alt = altName
                            cachedEntry.item = itemEntry
                            bucket[#bucket + 1] = cachedEntry
                        elseif debugEnabled then
                            Output:Debug("SEARCH", "Duplicate skipped: %s (%d) for %s", name, itemEntry.itemId, altName)
                        end
                    end
                end
            end
        end

        wipe(self.dirtyAlts)
        self.needsFullRebuild = false

        if debugEnabled then
            Output:Debug("SEARCH", "BuildSearchData complete. corpus size: %d", #corpus)
        end
    end

    if unresolvedCount > 0 then
        if debugEnabled then
            Output:Debug("SEARCH", "Resolving %d uncached items via GetItems", unresolvedCount)
        end

        Inventory:GetItems(unresolved, function(list)
            for i = 1, #list do
                local item = list[i]
                if item and item.itemId and item.itemInfo and item.itemInfo.name then
                    local name = item.itemInfo.name
                    item.cachedName = name

                    local lowerName = self.lowerNameCache[name]
                    if not lowerName then
                        lowerName = name:lower()
                        self.lowerNameCache[name] = lowerName
                    end

                    if not corpusNamesSeen[name] then
                        corpusNamesSeen[name] = true
                        corpusCount = corpusCount + 1

                        local cachedEntry = corpusPool[corpusCount]
                        if not cachedEntry then
                            cachedEntry = {}
                            corpusPool[corpusCount] = cachedEntry
                        end
                        cachedEntry.name = name
                        cachedEntry.lower = lowerName
                        corpus[corpusCount] = cachedEntry
                    end
                end
            end
            buildLookup()
        end)
    else
        buildLookup()
    end
end

-- Persist search data and state tracking
local function init(self)
    self.searchData = {
        corpus = {},
        lookup = {},
    }
    GBCR.UI.Search.searchData = self.searchData

    self.needsFullRebuild = true

    self.dirtyAlts = {}
    self.linkKeyCache = {}
    self.lowerNameCache = {}
    self.corpusPool = {}
    self.resultPool = {}
    self.seenPairs = {}
    self.corpusNamesSeen = {}
    self.unresolvedItems = {}
end

-- Export functions for other modules
Search.MarkAltDirty = markAltDirty
Search.MarkAllDirty = markAllDirty
Search.BuildSearchData = buildSearchData
Search.Init = init