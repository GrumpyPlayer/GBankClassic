local addonName, GBCR = ...

GBCR.Protocol = {}
local Protocol = GBCR.Protocol

local Globals = GBCR.Globals
local debugprofilestop = Globals.debugprofilestop
local ipairs = Globals.ipairs
local math_ceil = Globals.math_ceil
local math_max = Globals.math_max
local math_min = Globals.math_min
local math_random = Globals.math_random
local next = Globals.next
local pairs = Globals.pairs
local select = Globals.select
local string_byte = Globals.string_byte
local string_find = Globals.string_find
local string_format = Globals.string_format
local string_len = Globals.string_len
local string_match = Globals.string_match
local strsplit = Globals.strsplit
local table_concat = Globals.table_concat
local table_sort = Globals.table_sort
local tonumber = Globals.tonumber
local tostring = Globals.tostring
local type = Globals.type
local wipe = Globals.wipe

local After = Globals.After
local Enum = Globals.Enum
local GetClassColor = Globals.GetClassColor
local GetItemInfo = Globals.GetItemInfo
local GetServerTime = Globals.GetServerTime
local GetTime = Globals.GetTime
local InCombatLockdown = Globals.InCombatLockdown
local IsInGuild = Globals.IsInGuild
local IsInInstance = Globals.IsInInstance
local IsInRaid = Globals.IsInRaid
local Item = Globals.Item
local NewTimer = Globals.NewTimer
local shouldYield = Globals.ShouldYield

local Constants = GBCR.Constants
local colorBlue = Constants.COLORS.BLUE
local colorGold = Constants.COLORS.GOLD
local colorYellow = Constants.COLORS.YELLOW
local ledgerConstants = Constants.LEDGER
local prefixDescriptions = Constants.COMM_PREFIX_DESCRIPTIONS

-- ================================================================================================
-- Helper to make payloads smaller and encoded prior to transmission
local function serializePayload(data)
    local serializedData = GBCR.Libs.LibSerialize:Serialize(data)
    local compressedData = GBCR.Libs.LibDeflate:CompressDeflate(serializedData, {level = Constants.LIMITS.COMPRESSION_LEVEL})
    local encodedData = GBCR.Libs.LibDeflate:EncodeForWoWAddonChannel(compressedData)

    return encodedData
end

-- Helper to transform the received payloads into something usuable
local function deSerializePayload(message)
    local decoded = GBCR.Libs.LibDeflate:DecodeForWoWAddonChannel(message)
    local inflated = GBCR.Libs.LibDeflate:DecompressDeflate(decoded)

    return GBCR.Libs.LibSerialize:Deserialize(inflated)
end

-- Helper to AceComm for sending or suppressing outgoing messages
local function sendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
    if not GBCR.Addon.SendCommMessage then
        return
    end

    local prefixDesc = prefixDescriptions[prefix] or "(Unknown)"

    if IsInInstance() or IsInRaid() then
        GBCR.Output:Debug("COMMS", ">", "(suppressing)", prefix, prefixDesc, "to", GBCR.Guild:ColorPlayerName(target),
                          "(in instance or raid)")

        return
    end

    GBCR.Output:Debug("COMMS", ">", prefix, prefixDesc, "via", distribution, "to",
                      target and GBCR.Guild:ColorPlayerName(target) or "guild", "(" .. (#text or 0) .. " bytes)")

    return GBCR.Addon:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
end

-- Helper to send whispers to appropriately formatted online target
local function sendWhisper(prefix, text, target, prio, callbackFn, callbackArg)
    local prefixDesc = prefixDescriptions[prefix] or "(Unknown)"

    target = GBCR.Guild:NormalizePlayerName(target, true)

    local isTargetOnline = GBCR.Guild:IsPlayerOnlineMember(target)

    GBCR.Output:Debug("WHISPER", "SendWhisper called: prefix=%s %s, target=%s, isOnline=%s", prefix, prefixDesc, target,
                      tostring(isTargetOnline))

    if not isTargetOnline then
        GBCR.Output:Debug("WHISPER", "Cannot send %s %s to %s (player is offline)", prefix, prefixDesc, target)

        return false
    end

    sendCommMessage(prefix, text, "WHISPER", target, prio, callbackFn, callbackArg)

    GBCR.Output:Debug("WHISPER", "SendCommMessage completed for %s %s to %s", prefix, prefixDesc, target)

    return true
end

-- ================================================================================================
-- Helper to create a temporary link, required for caching
local function createTemporaryItemLink(encoded)
    if not encoded or encoded == "" then
        return nil
    end

    local itemId, enchant, suffix = string_match(encoded, "([^:]+):?([^:]*):?([^:]*)")

    if not itemId then
        return nil
    end

    enchant = (enchant and enchant ~= "") and enchant or "0"
    suffix = (suffix and suffix ~= "") and suffix or "0"

    return string_format("item:%d:%s:0:0:0:0:%s:0:0:0:0:0:0", itemId, enchant, suffix)
end

-- Helper to cache received data asynchronously
local function processItemQueue(self)
    if self.itemQueueHead >= self.itemQueueTail then
        wipe(self.itemReconstructQueue)
        self.itemQueueHead = 1
        self.itemQueueTail = 1
        self.isProcessingQueue = false

        return
    end

    local startTime = debugprofilestop()
    local iterations = 0
    local needsRefresh = false

    while self.itemQueueHead < self.itemQueueTail do
        if self.pendingAsyncLoads >= Constants.LIMITS.MAX_CONCURRENT_ASYNC then
            self.isProcessingQueue = false

            break
        end

        iterations = iterations + 1
        local item = self.itemReconstructQueue[self.itemQueueHead]
        self.itemReconstructQueue[self.itemQueueHead] = nil
        self.itemQueueHead = self.itemQueueHead + 1

        if item and not item.itemLink then
            local itemId = item.itemId
            if not itemId and item.itemString then
                local match = string_match(item.itemString, "^(%d+)")
                if match then
                    itemId = tonumber(match)
                end
            end
            itemId = itemId or 0

            if itemId > 0 then
                local itemLink = select(2, GetItemInfo(itemId))

                if itemLink and (not item.itemString or not string_find(item.itemString, ":", 1, true)) then
                    item.itemLink = nil
                else
                    self.pendingAsyncLoads = self.pendingAsyncLoads + 1

                    local tempLink = item.itemString and createTemporaryItemLink(item.itemString)
                    local itemObj = tempLink and Item:CreateFromItemLink(tempLink) or Item:CreateFromItemID(itemId)
                    GBCR.Output:Debug("ITEM", "Loading item %d (%s)", itemId or -1, tostring(tempLink) or tostring(itemId))

                    if itemObj then
                        if not itemObj:GetItemID() then
                            GBCR.Output:Debug("ITEM", "Item %s has a nil internal ID, skipping",
                                              tostring(tempLink) or tostring(itemId))
                            self.pendingAsyncLoads = self.pendingAsyncLoads - 1
                            needsRefresh = true
                        else
                            GBCR.Output:Debug("ITEM", "Item %d passed validation, calling ContinueOnItemLoad", itemId)
                            local success, err = pcall(function()
                                itemObj:ContinueOnItemLoad(function()
                                    self.pendingAsyncLoads = self.pendingAsyncLoads - 1
                                    local name, link
                                    if tempLink then
                                        name, link = GetItemInfo(tempLink)
                                    else
                                        name, link = GetItemInfo(itemId)
                                    end

                                    if name and link then
                                        item.itemString = GBCR.Inventory:GetItemKey(link)
                                        item.itemLink = nil
                                    end

                                    GBCR.UI:QueueUIRefresh()

                                    if not Protocol.isProcessingQueue and Protocol.itemQueueHead < Protocol.itemQueueTail then
                                        Protocol.isProcessingQueue = true

                                        After(0, function()
                                            processItemQueue(Protocol)
                                        end)
                                    end
                                end)
                            end)

                            if not success then
                                GBCR.Output:Debug("ITEM", "ContinueOnItemLoad crashed for item %d: %s", itemId, tostring(err))
                                self.pendingAsyncLoads = self.pendingAsyncLoads - 1
                            end
                        end
                    else
                        GBCR.Output:Debug("ITEM", "Item %d failed validation, skipping", itemId or -1)
                        self.pendingAsyncLoads = self.pendingAsyncLoads - 1
                    end
                    needsRefresh = true
                end
            end
        end

        if shouldYield(startTime, iterations, 25, 100) then
            break
        end
    end

    if needsRefresh then
        GBCR.UI:QueueUIRefresh()
    end

    if self.itemQueueHead < self.itemQueueTail and self.isProcessingQueue then
        After(0, function()
            processItemQueue(Protocol)
        end)
    else
        if self.itemQueueHead >= self.itemQueueTail then
            wipe(self.itemReconstructQueue)
            self.itemQueueHead = 1
            self.itemQueueTail = 1
            self.isProcessingQueue = false
        end
    end
end

-- Reconstruct itemLink fields after receiving data, calling GetItemInfo() to recreate links
local function reconstructItemLinks(self, items)
    if not items then
        return
    end

    local tail = self.itemQueueTail

    for i = 1, #items do
        local item = items[i]

        if not item.itemLink then
            local itemId = item.itemId
            if not itemId and item.itemString then
                local match = string_match(item.itemString, "^(%d+)")
                itemId = match and tonumber(match)
            end

            if itemId and itemId > 0 then
                self.itemReconstructQueue[tail] = item
                tail = tail + 1
            end
        end
    end

    self.itemQueueTail = tail

    if not self.isProcessingQueue and self.itemQueueHead < self.itemQueueTail then
        self.isProcessingQueue = true
        processItemQueue(Protocol)
    end
end

-- ================================================================================================
-- Helper for protocol state changes
local function setAltProtocolState(self, altName, newState)
    if not altName then
        return
    end

    if self.protocolStates[altName] == newState then
        return
    end

    self.protocolStates[altName] = newState
    GBCR.Output:Debug("PROTOCOL", "State for %s: %d", altName, newState)

    if self.uiStatePending then
        return
    end

    self.uiStatePending = true

    After(0, function()
        self.uiStatePending = false

        if GBCR.UI and GBCR.UI.Inventory then
            local active = false

            for _, s in pairs(Protocol.protocolStates) do
                if s == Constants.STATE.RECEIVING or s == Constants.STATE.DISCOVERING or s == Constants.STATE.REQUESTING then
                    active = true

                    break
                end
            end

            GBCR.UI.Inventory:SetSyncing(active)
            GBCR.UI.Inventory:NotifyStateChanged()
        end
    end)
end

-- Prune stale protocol states
local function pruneStaleProtocolStates(self)
    local cachedGuildBankAlts = GBCR.Guild.cachedGuildBankAlts
    if not cachedGuildBankAlts then
        return
    end

    for altName in pairs(self.protocolStates) do
        if not cachedGuildBankAlts[altName] then
            self.protocolStates[altName] = nil
            GBCR.Output:Debug("PROTOCOL", "Pruned protocolStates for %s", altName)
        end
    end
end

-- Reset the sync state
local function cleanupPendingSync(self)
    if not self.pendingSync then
        return
    end

    local now = GetServerTime()
    local cutoff = Constants.TIMER_INTERVALS.FINGERPRINT_BROADCAST

    local roster = self.pendingSync.roster
    if roster then
        for sender, timestamp in pairs(roster) do
            if now - timestamp > cutoff then
                roster[sender] = nil
            end
        end
    end

    local alts = self.pendingSync.alts
    if alts then
        for altName, senders in pairs(alts) do
            local empty = true
            for sender, timestamp in pairs(senders) do
                if now - timestamp > cutoff then
                    senders[sender] = nil
                else
                    empty = false
                end
            end

            if empty then
                alts[altName] = nil
            end
        end
    end

    if self.recentDataQueryResponses then
        for key, ts in pairs(self.recentDataQueryResponses) do
            if now - ts > 90 then
                self.recentDataQueryResponses[key] = nil
            end
        end
    end
end

-- Helper to mark a sync as pending
local function markPendingSync(self, syncType, sender, name)
    if not syncType or not sender then
        return
    end

    local now = GetServerTime()
    local normSender = GBCR.Guild:NormalizePlayerName(sender)

    if syncType == "roster" then
        if self.pendingSync.roster and normSender then
            self.pendingSync.roster[normSender] = now
        end
    elseif syncType == "alt" and name then
        local normName = GBCR.Guild:NormalizePlayerName(name)
        if self.pendingSync.alts and normName and not self.pendingSync.alts[normName] then
            self.pendingSync.alts[normName] = {}
        end
        if self.pendingSync.alts and normName and normSender and self.pendingSync.alts[normName] then
            self.pendingSync.alts[normName][normSender] = now
        end
    end
end

-- Helper to track a sync as complete
local function consumePendingSync(self, syncType, sender, name)
    if not syncType or not sender then
        return false
    end

    local now = GetServerTime()
    local normSender = GBCR.Guild:NormalizePlayerName(sender)

    if syncType == "roster" then
        local roster = self.pendingSync.roster
        local versionTimestamp = roster and roster[normSender]
        if versionTimestamp and now - versionTimestamp <= Constants.TIMER_INTERVALS.FINGERPRINT_BROADCAST then
            roster[normSender] = nil

            return true
        end
        if versionTimestamp then
            roster[normSender] = nil
        end

        return false
    end

    if syncType == "alt" and name then
        local normName = GBCR.Guild:NormalizePlayerName(name)
        local alts = self.pendingSync.alts and self.pendingSync.alts[normName]
        local versionTimestamp = alts and alts[normSender]
        if versionTimestamp and now - versionTimestamp <= Constants.TIMER_INTERVALS.FINGERPRINT_BROADCAST then
            alts[normSender] = nil
            if next(alts) == nil then
                self.pendingSync.alts[normName] = nil
            end

            return true
        end
        if versionTimestamp then
            alts[normSender] = nil
            if next(alts) == nil then
                self.pendingSync.alts[normName] = nil
            end
        end
    end

    return false
end

-- Helper to warn user about outdated addon based on incoming data
local function checkAndWarnAddonOutdated(self, incomingVersion)
    if incomingVersion and tonumber(incomingVersion) > GBCR.Core.addonVersionNumber then
        if not self.isAddonOutdated then
            self.isAddonOutdated = true
            GBCR.Output:Response(
                "A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived")
            GBCR.Core:LoadMetadata()
        end
    end
end

-- Helper to track metadata from sender
local function trackSenderMetadata(self, sender, incomingAddonVersionNumber, incomingIsGuildBankAlt,
                                   incomingRosterVersionTimestamp)
    if not incomingAddonVersionNumber then
        return
    end

    local entry = self.guildMembersFingerprintData[sender]
    if not entry then
        entry = {}
        self.guildMembersFingerprintData[sender] = entry
    end

    entry.addonVersionNumber = incomingAddonVersionNumber
    entry.seen = GetServerTime()
    entry.isGuildBankAlt = incomingIsGuildBankAlt or entry.isGuildBankAlt
    entry.rosterVersionTimestamp = incomingRosterVersionTimestamp or entry.rosterVersionTimestamp

    if GBCR.Guild.cachedOnlineGuildMembers and GBCR.Guild.cachedOnlineGuildMembers[sender] then
        GBCR.Guild.cachedAddonUsers = GBCR.Guild.cachedAddonUsers or {}
        GBCR.Guild.cachedAddonUsers[sender] = true
    end

    GBCR.Output:Debug("ROSTER", "Tracking member %s with addon version %s (isGuildBankAlt=%s, rosterVersionTimestamp=%s)",
                      GBCR.Guild:ColorPlayerName(sender), tostring(incomingAddonVersionNumber), tostring(incomingIsGuildBankAlt),
                      tostring(incomingRosterVersionTimestamp))

    checkAndWarnAddonOutdated(self, incomingAddonVersionNumber)
end

-- Helper to determine if we have basic version information for a specific guild bank alt
local function hasAltData(alt)
    if not alt or type(alt) ~= "table" then
        return false
    end

    if alt.version and alt.version > 0 then
        return true
    end

    return false
end

-- Helper to determine if we have actual data for a specific guild bank alt
local function hasAltContent(alt, altName)
    if not hasAltData(alt) then
        return false
    end

    local hasItems = (alt.items ~= nil and next(alt.items) ~= nil) or (alt.items == nil and alt.itemsCompressed ~= nil) or
                         (alt.itemsHash ~= nil and alt.itemsHash > 0)

    if GBCR.Options:IsDebugEnabled() then
        GBCR.Output:Debug("SYNC", "Content check for %s: items=%s (%d) => %s", altName or alt.name or "unknown",
                          tostring(hasItems and "Y" or "N"), alt.items and #alt.items or 0, tostring(hasItems))
    end

    return hasItems
end

-- Helper to determine if it's allowed to send a query right now
local function isQueryAllowed()
    if GBCR.Guild.cachedOnlineGuildMemberCount > 1 then
        return true
    end

    return false
end

-- Detect when the player enters combat or an instance or a raid group and immediately lock the protocol
local function updateSafetyLockout(self)
    if not IsInGuild() then
        GBCR.Guild:ClearGuildCaches()

        return
    end

    local wasLockedOut = self.isLockedOut
    local shouldLock = InCombatLockdown() or IsInInstance() or IsInRaid()
    if shouldLock == wasLockedOut then
        return
    end

    self.isLockedOut = shouldLock
    if shouldLock then
        GBCR.Output:Debug("PROTOCOL", "Safety lockout engaged, synchronization paused")
    else
        GBCR.Output:Debug("PROTOCOL", "Safety lockout lifted, synchronization resumed")
    end

    GBCR.UI:QueueUIRefresh()
end

-- ================================================================================================
-- Helper to encode fingerprint data for sharing (gbc-fp-share)
local function craftFingerprintPayload()
    local db = GBCR.Database.savedVariables
    if not db then
        GBCR.Output:Debug("SYNC", "craftFingerprintPayload: missing database")

        return {}
    end

    local rosterAlts = GBCR.Database:GetRosterGuildBankAlts()
    if not rosterAlts or #rosterAlts == 0 then
        GBCR.Output:Debug("SYNC", "craftFingerprintPayload: empty roster")

        return {}
    end

    local Guild = GBCR.Guild
    local membersCache = Guild.cachedGuildMembers
    local cachedGuildBankAlts = Guild.cachedGuildBankAlts
    local output = GBCR.Output
    local altsData = db.alts

    local alts = {}
    for altName, altData in pairs(altsData) do
        if not cachedGuildBankAlts[altName] then
            output:Debug("SYNC", "craftFingerprintPayload: excluding %s (not in roster)", altName)
        elseif not hasAltContent(altData, altName) and not altData.itemsHash then
            output:Debug("SYNC", "craftFingerprintPayload: excluding %s (no content)", altName)
        elseif type(altData) == "table" and altData.version then
            local member = membersCache[altName]
            if member and member.playerUid then
                local version = tonumber(altData.version) or 0
                output:Debug("SYNC", "craftFingerprintPayload: including %s (version=%d)", altName, version)

                alts[#alts + 1] = {member.playerUid, version}
            end
        end
    end

    table_sort(alts, function(a, b)
        if a[2] ~= b[2] then
            return a[2] < b[2]
        end

        return a[1] < b[1]
    end)

    local baseVersion = (#alts > 0) and alts[1][2] or 0

    local payload = {
        GBCR.Core.addonVersionNumber,
        Guild.areOfficerNotesUsedToDefineGuildBankAlts == true,
        baseVersion,
        Guild.cachedGuildBankAlts[Guild:GetNormalizedPlayerName()] and true or false
    }

    local position = 5
    local previousVersion = baseVersion

    for i = 1, #alts do
        payload[position] = alts[i][1]
        payload[position + 1] = alts[i][2] - previousVersion

        previousVersion = alts[i][2]
        position = position + 2
    end

    payload[position] = (db.roster and db.roster.version) or -1

    return payload
end

-- Helper to parse encoded received fingerprint data (gbc-fp-share)
local function parseFingerprintPayload(payload)
    local Guild = GBCR.Guild

    local addonVersionNumber = payload[1]
    local areOfficerNotesUsedToDefineGuildBankAlts = payload[2]
    local baseVersion = payload[3]
    local isGuildBankAlt = payload[4]

    local alts = {}
    local pos = 5
    local prev = baseVersion

    while pos <= #payload - 1 do
        local uid = payload[pos]
        local delta = payload[pos + 1]

        local version = prev + delta
        local name = Guild:FindGuildMemberByUid(uid)

        if name then
            alts[name] = {version = version}
        end

        prev = version
        pos = pos + 2
    end

    local rosterRaw = payload[pos]
    local rosterVersionTimestamp = (rosterRaw and rosterRaw ~= -1) and rosterRaw or nil

    return {
        addonVersionNumber = addonVersionNumber,
        areOfficerNotesUsedToDefineGuildBankAlts = areOfficerNotesUsedToDefineGuildBankAlts,
        isGuildBankAlt = isGuildBankAlt,
        alts = alts,
        rosterVersionTimestamp = rosterVersionTimestamp
    }
end

-- Send a fingerprint representing our guild bank state
local function sendFingerprint(self, target)
    local guildName = GBCR.Guild:GetGuildInfo()
    if not guildName then
        GBCR.Output:Debug("PROTOCOL", "sendFingerprint early exit because of missing guild information")

        return
    end

    if not target then
        local now = GetServerTime()
        local sinceLastBroadcast = now - (self.lastFingerprintBroadcast or 0)
        if sinceLastBroadcast < Constants.TIMER_INTERVALS.FINGERPRINT_COOLDOWN then
            GBCR.Output:Debug("PROTOCOL", "sendFingerprint broadcast suppressed (last was %ds ago, cooldown %ds)",
                              sinceLastBroadcast, Constants.TIMER_INTERVALS.FINGERPRINT_COOLDOWN)

            return
        end
        self.lastFingerprintBroadcast = now
    end

    local version = craftFingerprintPayload()
    if #version == 0 then
        GBCR.Output:Debug("PROTOCOL", "sendFingerprint early exit because of missing fingerprint data")

        return
    end

    GBCR.UI.Inventory:SetSyncing(true)

    local data = serializePayload(version)
    if target then
        sendWhisper("gbc-fp-share", data, target, "NORMAL")
    else
        sendCommMessage("gbc-fp-share", data, "GUILD", nil, "NORMAL")
    end

    After(1.5, function()
        if Protocol.activeOutboundWhispers == 0 then
            GBCR.UI.Inventory:SetSyncing(false)
        end
    end)
end

-- Helper to only include the most recent SYNC_WINDOW entries in payload
local function craftLedgerPayload(altName)
    local sv = GBCR.Database.savedVariables
    if not sv or not sv.alts or not sv.alts[altName] then
        return {}
    end

    local ledger = sv.alts[altName].ledger or {}
    if #ledger == 0 then
        return {}
    end

    table_sort(ledger, function(a, b)
        return a[GBCR.Ledger.indexTimestamp] > b[GBCR.Ledger.indexTimestamp]
    end)

    local slice = {}
    for i = 1, math_min(ledgerConstants.SYNC_WINDOW, #ledger) do
        slice[i] = ledger[i]
    end

    return slice
end

-- Helper to encode guild bank alt data for sharing (gbc-data-share)
local function craftDataPayload(self, altName, altData)
    if not altData then
        return nil
    end

    if not altData.version or altData.version == 0 then
        return
    end

    local sourceItems = altData.items or {}
    local countOfItems = #sourceItems
    if countOfItems == 0 and (not altData.money or altData.money == 0) then
        return
    end

    local guild = GBCR.Guild
    local addonVersion = GBCR.Core.addonVersionNumber
    local version = altData.version
    local money = altData.money

    local items = self.bufferItems
    wipe(items)
    for i = 1, countOfItems do
        items[i] = sourceItems[i]
    end

    local sortKeys = self.bufferSortKeys
    for i = 1, countOfItems do
        local p1 = strsplit(":", items[i].itemString)
        sortKeys[i] = tonumber(p1) or 0
    end
    for i = countOfItems + 1, #sortKeys do
        sortKeys[i] = nil
    end

    local indices = self.bufferIndices
    for i = 1, countOfItems do
        indices[i] = i
    end
    for i = countOfItems + 1, #indices do
        indices[i] = nil
    end
    table_sort(indices, function(a, b)
        return sortKeys[a] < sortKeys[b]
    end)

    local sortedItems = self.bufferSortedItems
    for i = 1, countOfItems do
        sortedItems[i] = items[indices[i]]
    end
    for i = countOfItems + 1, #sortedItems do
        sortedItems[i] = nil
    end

    local uidDict = self.bufferUid
    wipe(uidDict)

    local uidIndex = self.bufferUidIndex
    wipe(uidIndex)

    local function getUidIndex(uid)
        if not uidIndex[uid] then
            local position = #uidDict + 1
            uidIndex[uid] = position
            uidDict[position] = uid
        end

        return uidIndex[uid]
    end

    local sourceLedger = altData.ledger or {}
    local numLedgerEntries = #sourceLedger
    for i = 1, numLedgerEntries do
        local actorUid = sourceLedger[i][6]
        if actorUid then
            getUidIndex(actorUid)
        end
    end

    local payload = self.bufferPayload
    wipe(payload)

    local selfMember = guild.cachedGuildMembers[altName]
    if not selfMember or not selfMember.playerUid then
        GBCR.Output:Debug("SYNC", "craftDataPayload: %s not in guild cache, aborting", altName)

        return nil
    end

    payload[1] = addonVersion
    payload[2] = selfMember.playerUid
    payload[3] = version
    payload[4] = money
    local position = 5

    payload[position] = #uidDict
    position = position + 1
    for i = 1, #uidDict do
        payload[position] = uidDict[i]
        position = position + 1
    end

    payload[position] = countOfItems
    position = position + 1

    local prevID = 0
    for i = 1, countOfItems do
        local item = sortedItems[i]
        local itemStr = item.itemString or tostring(item.itemId or 0)
        local p1, p2, p3 = strsplit(":", itemStr)
        local itemId = tonumber(p1) or 0
        local enchant = tonumber(p2) or 0
        local suffix = tonumber(p3) or 0
        local itemCount = tonumber(item.itemCount) or 1

        payload[position] = itemId - prevID
        position = position + 1
        prevID = itemId

        if enchant ~= 0 or suffix ~= 0 then
            payload[position] = -itemCount
            position = position + 1
            payload[position] = enchant
            position = position + 1
            payload[position] = suffix
            position = position + 1
        else
            payload[position] = itemCount
            position = position + 1
        end
    end

    local ledger = GBCR.Ledger
    local ledgerSlice = craftLedgerPayload(altName)
    payload[position] = #ledgerSlice
    position = position + 1

    for i = 1, #ledgerSlice do
        local e = ledgerSlice[i]

        local actorUid = 0
        if e[ledger.indexActor] and e[ledger.indexActor] ~= "" then
            actorUid = getUidIndex(e[ledger.indexActor])
        end

        payload[position] = e[ledger.indexTimestamp]
        position = position + 1
        payload[position] = e[ledger.indexItemId]
        position = position + 1
        payload[position] = e[ledger.indexEnchant]
        position = position + 1
        payload[position] = e[ledger.indexSuffix]
        position = position + 1
        payload[position] = e[ledger.indexCount]
        position = position + 1
        payload[position] = actorUid
        position = position + 1
        payload[position] = e[ledger.indexOperation]
        position = position + 1
    end

    return payload
end

-- Helper to parse encoded received guild bank alt data (gbc-data-share)
local function parseDataPayload(self, payload)
    local guild = GBCR.Guild
    local addonVersionNumber = payload[1]
    local altName = guild:FindGuildMemberByUid(payload[2])
    local version = payload[3]
    local money = payload[4]
    local position = 5

    local uidDict = self.bufferParsedUid
    wipe(uidDict)

    local numUids = payload[position]
    position = position + 1
    for i = 1, numUids do
        uidDict[i] = payload[position]
        position = position + 1
    end

    local items = self.bufferParsedItems
    wipe(items)

    local numItems = payload[position]
    position = position + 1

    local currentItemId = 0
    for i = 1, numItems do
        local delta = payload[position]
        position = position + 1
        currentItemId = currentItemId + delta

        local rawCount = payload[position]
        position = position + 1
        local itemCount = rawCount
        local itemString

        if rawCount < 0 then
            itemCount = -rawCount
            local enchant = payload[position]
            position = position + 1
            local suffix = payload[position]
            position = position + 1
            itemString = string_format("%d:%d:%d", currentItemId, enchant, suffix)
        else
            itemString = tostring(currentItemId)
        end

        items[i] = {itemId = currentItemId, itemCount = itemCount, itemString = itemString}
    end

    local ledger = self.bufferParsedLedger
    wipe(ledger)

    local numLedgerEntries = payload[position]
    position = position + 1

    for i = 1, numLedgerEntries do
        local timestamp = payload[position]
        position = position + 1
        local itemId = payload[position]
        position = position + 1
        local enchant = payload[position]
        position = position + 1
        local suffix = payload[position]
        position = position + 1
        local count = payload[position]
        position = position + 1
        local actorUidId = payload[position]
        position = position + 1
        local opCode = payload[position]
        position = position + 1
        local actorUid = (actorUidId > 0 and uidDict[actorUidId]) or ""
        ledger[i] = {timestamp, itemId, enchant, suffix, count, actorUid, opCode}
    end

    local result = self.bufferParsedResult
    wipe(result)

    result.addonVersionNumber = addonVersionNumber
    result.altName = altName
    result.version = version
    result.money = money
    result.numItems = numItems
    result.items = items
    result.ledger = ledger

    return result
end

-- Helper to extract outcome from ChatThrottleLib
local function getSendResultName(result)
    if result == Enum.SendAddonMessageResult.Success or result == true then
        return "Success"
    elseif result == Enum.SendAddonMessageResult.AddonMessageThrottle then
        return "AddonMessageThrottle"
    elseif result == Enum.SendAddonMessageResult.NotInGroup then
        return "NotInGroup"
    elseif result == Enum.SendAddonMessageResult.ChannelThrottle then
        return "ChannelThrottle"
    elseif result == Enum.SendAddonMessageResult.GeneralError then
        return "GeneralError"
    elseif result == false then
        return "Failed"
    else
        return tostring(result)
    end
end

-- Helper to create a per-send callback with its own stats tracking
local function createOnChunkSentCallback(altName, destination)
    local sendStats = {startTime = GetTime(), failures = 0, throttled = 0}

    return function(arg, bytesSent, totalBytes, sendResult)
        if bytesSent > 0 then
            sendStats.abort = false
            sendStats.startTime = GetTime()
            sendStats.failures = 0
            sendStats.throttled = 0
        end

        if sendStats.abort then
            return
        end

        local isSuccess = (sendResult == Enum.SendAddonMessageResult.Success or sendResult == true or sendResult == nil)
        local isThrottled = (sendResult == Enum.SendAddonMessageResult.AddonMessageThrottle or sendResult ==
                                Enum.SendAddonMessageResult.ChannelThrottle)
        if isThrottled then
            sendStats.throttled = sendStats.throttled + 1
        elseif not isSuccess then
            sendStats.failures = sendStats.failures + 1
        end

        local totalChunks = math_ceil(totalBytes / 254)

        if not isSuccess then
            local resultStr = getSendResultName(sendResult)
            GBCR.Output:Debug("CHUNK", "Send failed (%s), aborting", resultStr)
            sendStats.abort = true

            return
        end

        if bytesSent >= totalBytes then
            local elapsed = GetTime() - sendStats.startTime
            local summary = string_format("Send complete: ~%d chunks, %d bytes in %.1fs", totalChunks, totalBytes, elapsed)
            if sendStats.failures > 0 or sendStats.throttled > 0 then
                summary = summary .. string_format(" | failures: %d, throttled: %d", sendStats.failures, sendStats.throttled)
            end

            GBCR.Output:Debug("CHUNK", summary)
            if altName == GBCR.Guild:GetNormalizedPlayerName() then
                GBCR.Output:Response("Finished sending your latest data%s.", destination and
                                         string_format(" to %s", GBCR.Guild:ColorPlayerName(destination)) or " to the guild")
            else
                GBCR.Output:Info("Finished sending data for %s%s.", GBCR.Guild:ColorPlayerName(altName),
                                 destination and string_format(" to %s", GBCR.Guild:ColorPlayerName(destination)))
            end

            if sendStats.failures > 0 then
                GBCR.Output:Debug("CHUNK", "WARNING: %d send failures occurred!", sendStats.failures)
            end

            sendStats.abort = false
            sendStats.startTime = nil
            sendStats.failures = 0
            sendStats.throttled = 0
        end
    end
end

-- Helper to send guild bank alt data (gbc-data-share)
local function sendData(self, name, target)
    if not name then
        return
    end

    if not isQueryAllowed() then
        return
    end

    if not GBCR.Database.savedVariables or not GBCR.Database.savedVariables.guildName then
        GBCR.Output:Debug("SYNC", "sendData: early exit because GBCR.Database.savedVariables was not loaded for %s", name)

        return
    end

    if not GBCR.Database.savedVariables.alts then
        GBCR.Output:Debug("SYNC", "sendData: early exit because GBCR.Database.savedVariables.alts table does not exist for %s",
                          name)

        return
    end

    local norm = GBCR.Guild:NormalizePlayerName(name)
    local currentAlt = GBCR.Database.savedVariables.alts[norm]
    if not currentAlt then
        GBCR.Output:Debug("SYNC", "sendData: early exit because no data exists for guild bank alt %s (norm=%s)", name, norm)

        return
    end

    if not hasAltData(currentAlt) then
        GBCR.Output:Debug("SYNC", "sendData: early exit because no valid data exists for guild bank alt %s", norm)

        return
    end

    GBCR.UI.Inventory:SetSyncing(true)

    local channel = target and "WHISPER" or "GUILD"
    local dest = target or nil

    if channel == "WHISPER" and dest then
        if self.activeOutboundWhispers >= Constants.LIMITS.MAX_CONCURRENT_OUTBOUND then
            GBCR.Output:Debug("SYNC", "sendData: concurrent outbound cap reached, sending busy to %s", dest)

            local payload = {busy = true, name = norm}
            local data = serializePayload(payload)
            sendWhisper("gbc-data-query", data, dest, "NORMAL")

            GBCR.UI.Inventory:SetSyncing(false)

            return
        end

        self.activeOutboundWhispers = self.activeOutboundWhispers + 1
    end

    local onChunkSent = createOnChunkSentCallback(norm, dest)
    local hookedCallback = function(arg, bytesSent, totalBytes, sendResult)
        onChunkSent(arg, bytesSent, totalBytes, sendResult)

        local isComplete = (bytesSent >= totalBytes)
        local isFailed = not (sendResult == Enum.SendAddonMessageResult.Success or sendResult == true or sendResult == nil)

        if (isComplete or isFailed) and channel == "WHISPER" and dest then
            self.activeOutboundWhispers = math_max(0, self.activeOutboundWhispers - 1)

            if isComplete and norm == GBCR.Guild:GetNormalizedPlayerName() then
                GBCR.UI.Network:RecordSuccessfulSeed(dest or "guild")
            else
                GBCR.UI.Inventory:SetSyncing(false)
            end
        else
            GBCR.UI.Inventory:SetSyncing(false)
        end
    end

    local itemsCount = currentAlt.items and #currentAlt.items or 0
    GBCR.Output:Debug("SYNC", "sendData: sending %d items for guild bank alt %s to %s", itemsCount, norm, dest or "guild")

    local tempItems = nil
    local tempLedger = nil
    if currentAlt.itemsCompressed and not currentAlt.items then
        tempItems = GBCR.Database.DecompressData(currentAlt.itemsCompressed)
        currentAlt.items = tempItems
    end
    if currentAlt.ledgerCompressed and not currentAlt.ledger then
        tempLedger = GBCR.Database.DecompressData(currentAlt.ledgerCompressed)
        currentAlt.ledger = tempLedger
    end

    local craftedPayload = craftDataPayload(self, norm, currentAlt)
    if not craftedPayload then
        GBCR.Output:Debug("SYNC", "sendData: skipped sending guild bank alt %s to %s, no valid payload", norm, dest or "guild")

        if tempItems then
            currentAlt.items = nil
        end
        if tempLedger then
            currentAlt.ledger = nil
        end
        if channel == "WHISPER" and dest then
            self.activeOutboundWhispers = math_max(0, self.activeOutboundWhispers - 1)
        end

        GBCR.UI.Inventory:SetSyncing(false)

        return
    end

    if tempItems then
        currentAlt.items = nil
    end
    if tempLedger then
        currentAlt.ledger = nil
    end

    local data = serializePayload(craftedPayload)
    GBCR.Output:Debug("CHUNK", "Sharing data: %d bytes in ~%d chunks...", string_len(data), math_ceil(string_len(data) / 254))

    if channel == "WHISPER" and dest then
        sendWhisper("gbc-data-share", data, dest, "NORMAL", hookedCallback)
    else
        sendCommMessage("gbc-data-share", data, "GUILD", nil, "NORMAL", hookedCallback)
    end

    GBCR.Output:Debug("SYNC", "sendData: sent full data for %s (%d bytes)", norm, string_len(data))
end

-- Helper to receive guild bank alt data (gbc-data-share)
local function receiveData(self, incomingData, sender)
    if not GBCR.Database.savedVariables then
        GBCR.Output:Debug("SYNC", "receiveData: early exit because GBCR.Database.savedVariables was not loaded")

        return Constants.ADOPTION_STATUS.IGNORED
    end

    local parsedPayload = parseDataPayload(self, incomingData)

    local incomingAddonVersionNumber = parsedPayload.addonVersionNumber
    local incomingAltName = parsedPayload.altName
    local incomingVersion = parsedPayload.version
    local incomingMoney = parsedPayload.money
    local incomingNumItems = parsedPayload.numItems
    local incomingItems = parsedPayload.items
    local incomingLedgerlog = parsedPayload.ledger

    trackSenderMetadata(self, sender, incomingAddonVersionNumber or nil, nil, nil)

    GBCR.Output:Debug("SYNC", "receiveData: processing %d items for %s", incomingNumItems, incomingAltName)

    local playerNorm = GBCR.Guild:GetNormalizedPlayerName()
    local isOwnData = playerNorm == incomingAltName
    if isOwnData then
        GBCR.Output:Debug("SYNC", "receiveData: rejected data about ourselves")

        return Constants.ADOPTION_STATUS.UNAUTHORIZED
    end

    local existing = GBCR.Database.savedVariables.alts[incomingAltName]
    local existingVersion = existing and existing.version or nil
    if incomingVersion and existingVersion and incomingVersion <= existingVersion then
        GBCR.Output:Debug("SYNC", "receiveData: rejecting %s (incomingVersion=%d <= existingVersion=%d)", incomingAltName,
                          incomingVersion, existingVersion)

        return Constants.ADOPTION_STATUS.STALE
    end

    setAltProtocolState(self, incomingAltName, Constants.STATE.RECEIVING)

    if not GBCR.Database.savedVariables.alts then
        GBCR.Database.savedVariables.alts = {}
    end

    if not GBCR.Database.savedVariables.alts[incomingAltName] then
        GBCR.Database.savedVariables.alts[incomingAltName] = {}
    end

    local altData = GBCR.Database.savedVariables.alts[incomingAltName]
    altData.version = incomingVersion
    altData.money = incomingMoney

    if not altData.items then
        altData.items = {}
    end
    wipe(altData.items)
    for i = 1, incomingNumItems do
        local item = incomingItems[i]
        item.itemInfo = nil
        item.lowerName = nil
        item.itemId = nil
        item.itemLink = nil
        altData.items[i] = item
    end

    if incomingLedgerlog and #incomingLedgerlog > 0 then
        GBCR.Ledger:MergeLedger(incomingAltName, incomingLedgerlog)
    end

    altData.itemsCompressed = GBCR.Database.CompressData(altData.items)

    GBCR.Output:Debug("SYNC", "receiveData: accepted and saved guild bank alt data for %s", incomingAltName)

    GBCR.UI.Inventory:MarkAltDirty(incomingAltName)

    if self.requestTimeoutTimers[incomingAltName] then
        self.requestTimeoutTimers[incomingAltName]:Cancel()
        self.requestTimeoutTimers[incomingAltName] = nil
    end

    if self.requestRetryTimers[incomingAltName] then
        self.requestRetryTimers[incomingAltName]:Cancel()
        self.requestRetryTimers[incomingAltName] = nil
    end

    if incomingItems then
        reconstructItemLinks(self, incomingItems)
    end

    setAltProtocolState(self, incomingAltName, Constants.STATE.UPDATED)

    After(1, function()
        setAltProtocolState(self, incomingAltName, Constants.STATE.IDLE)
    end)

    GBCR.UI.Network:RecordReceived(incomingAltName, sender)

    return Constants.ADOPTION_STATUS.ADOPTED
end

-- Helper to query for guild bank alt data (gbc-data-query) to specific or best target, fallback to entire guild
local function queryForGuildBankAltData(self, target, altName)
    if not isQueryAllowed() then
        return
    end

    if self.protocolStates[altName] == Constants.STATE.REQUESTING then
        return
    end

    if not target then
        local bestTarget = nil
        local highestVersion = -1
        local ourPlayer = GBCR.Guild:GetNormalizedPlayerName()

        if self.altDataSources and self.altDataSources[altName] then
            for potentialTarget, version in pairs(self.altDataSources[altName]) do
                if potentialTarget ~= ourPlayer and GBCR.Guild:IsPlayerOnlineMember(potentialTarget) then
                    if version > highestVersion then
                        highestVersion = version
                        bestTarget = potentialTarget
                    end
                end
            end
        end

        if not bestTarget and GBCR.Guild:IsPlayerOnlineGuildBankAlt(altName) then
            bestTarget = altName
        end

        target = bestTarget
    end

    setAltProtocolState(self, altName, Constants.STATE.REQUESTING)

    GBCR.Output:Debug("SYNC", "Querying %s for %s", target and GBCR.Guild:ColorPlayerName(target) or "guild",
                      GBCR.Guild:ColorPlayerName(altName))

    if self.requestTimeoutTimers[altName] then
        self.requestTimeoutTimers[altName]:Cancel()
        self.requestTimeoutTimers[altName] = nil
    end

    self.requestTimeoutTimers[altName] = NewTimer(30, function()
        self.requestTimeoutTimers[altName] = nil
        if self.protocolStates[altName] == Constants.STATE.REQUESTING then
            GBCR.Output:Debug("PROTOCOL", "Request timeout for %s, reverting state", altName)
            setAltProtocolState(self, altName, Constants.STATE.OUTDATED)

            local ourAlt = GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts and
                               GBCR.Database.savedVariables.alts[altName]
            if not ourAlt or not ourAlt.version or ourAlt.version == 0 then
                if self.requestRetryTimers[altName] then
                    self.requestRetryTimers[altName]:Cancel()
                end
                self.requestRetryTimers[altName] = NewTimer(math_random(Constants.JITTER.TIMEOUT_RETRY_MIN,
                                                                        Constants.JITTER.TIMEOUT_RETRY_MAX), function()
                    self.requestRetryTimers[altName] = nil
                    queryForGuildBankAltData(Protocol, nil, altName)
                end)
            end
        end
    end)

    local payload = {name = altName, requester = GBCR.Guild:GetNormalizedPlayerName()}
    local data = serializePayload(payload)
    if target and sendWhisper("gbc-data-query", data, target, "NORMAL") then
        markPendingSync(self, "alt", target, altName)

        return
    end

    sendCommMessage("gbc-data-query", data, "GUILD", nil, "NORMAL")
    markPendingSync(self, "alt", "guild", altName)
end

-- Send the roster (gbc-roster-share)
local function sendRoster(target)
    local rosterData = GBCR.Database.savedVariables.roster
    local altCount = rosterData.alts and #rosterData.alts or 0

    GBCR.Output:Debug("ROSTER", "Sending roster (%d alts, areOfficerNotesUsed=%s, target=%s)", altCount,
                      tostring(GBCR.Database.savedVariables.roster.areOfficerNotesUsed),
                      target and GBCR.Guild:ColorPlayerName(target) or "GUILD")

    local payload = {roster = rosterData}
    local data = serializePayload(payload)

    if target and sendWhisper("gbc-roster-share", data, target, "NORMAL") then
        return
    end

    sendCommMessage("gbc-roster-share", data, "GUILD", nil, "NORMAL")
end

-- Determine if player may author the roster after enabling a new guild bank alt or executing /bank roster
local function sendRosterIfAuthority()
    local rosterAlts = GBCR.Database:GetRosterGuildBankAlts()
    if not rosterAlts then
        GBCR.Output:Debug("ROSTER", "sendRosterIfAuthority: skipped, no roster data")

        return
    end

    if not GBCR.Guild.isGuildRosterReady then
        GBCR.Output:Debug("ROSTER", "sendRosterIfAuthority: deferred, initial scan not yet complete")

        return
    end

    local savedManualAlts = GBCR.Database.savedVariables.roster and GBCR.Database.savedVariables.roster.manualAlts or {}
    local hasManualAlts = savedManualAlts and #savedManualAlts > 0
    if GBCR.Guild.anyoneIsAuthority and not hasManualAlts then
        GBCR.Output:Response("All guild members can view officer notes and have an accurate roster of guild bank alts.")

        return
    end

    if not GBCR.Guild.weCanViewOfficerNotes then
        GBCR.Output:Response("You lack permissions to share the roster. Only players that can view officer notes are permitted.")

        return
    end

    GBCR.Output:Response("Broadcasting the guild bank roster (%d guild bank alts) to online members.", #rosterAlts)

    sendRoster()
end

-- Helper to query for roster data (gbc-roster-query)
local function queryForRosterData(self, target, incomingRosterVersion)
    if not isQueryAllowed() then
        return
    end

    local function isAuthority(name)
        local entry = name and GBCR.Guild.cachedGuildMembers and GBCR.Guild.cachedGuildMembers[name]

        return entry and entry.isAuthority or false
    end

    if target and not isAuthority(target) then
        GBCR.Output:Debug("ROSTER", "queryForRosterData: suggested target %s is not an authority, seeking another",
                          GBCR.Guild:ColorPlayerName(target))
        target = nil
    end

    if not target then
        for name, info in pairs(GBCR.Guild.cachedGuildMembers) do
            if info.isAuthority and GBCR.Guild:IsPlayerOnlineMember(name) and name ~= GBCR.Guild:GetNormalizedPlayerName() then
                target = name

                break
            end
        end
    end

    GBCR.Output:Debug("ROSTER", "Querying %s for roster (incomingRosterVersion=%s)",
                      target and GBCR.Guild:ColorPlayerName(target) or "GUILD", tostring(incomingRosterVersion))

    local payload = {version = incomingRosterVersion}
    local data = serializePayload(payload)

    if target and sendWhisper("gbc-roster-query", data, target, "NORMAL") then
        markPendingSync(self, "roster", target)

        return
    end

    sendCommMessage("gbc-roster-query", data, "GUILD", nil, "NORMAL")
    markPendingSync(self, "roster", "guild")
end

-- Send a hello (gbc-h) upon /bank hello, or a reply (gbc-hr, type = "reply") upon receipt, and print output to ourselves
local function sendHello(self, messageType, target)
    local currentData = GBCR.Database.savedVariables
    if not currentData then
        return
    end

    local currentPlayer = GBCR.Guild:GetNormalizedPlayerName()
    local playerClass = GBCR.Guild:GetGuildMemberInfo(currentPlayer)
    local classColor = select(4, GetClassColor(playerClass))

    local helloParts = {
        "Hi! ",
        Globals.ColorizeText(classColor, currentPlayer),
        " is using version ",
        tostring(GBCR.Core.addonVersionNumber),
        "."
    }

    local rosterList = {}
    local guildBankList = {}

    if currentData.roster and currentData.roster.alts then
        for _, v in ipairs(currentData.roster.alts) do
            rosterList[#rosterList + 1] = v
        end
    end

    if currentData.alts then
        for k, v in pairs(currentData.alts) do
            if v and v.items and #v.items > 0 then
                guildBankList[#guildBankList + 1] = k
            end
        end
    end

    local rosterCount = #rosterList
    local guildBankCount = #guildBankList

    if rosterCount > 0 or guildBankCount > 0 then
        local pluralRoster = rosterCount ~= 1 and "s" or ""
        local pluralBanks = guildBankCount ~= 1 and "s" or ""
        local rosterAlts = rosterCount > 0 and " (" .. table_concat(rosterList, ", ") .. ")" or ""
        local bankAlts = guildBankCount > 0 and " (" .. table_concat(guildBankList, ", ") .. ")" or ""

        helloParts[#helloParts + 1] = "\n"
        helloParts[#helloParts + 1] = "I know about " .. Globals.ColorizeText(colorGold, rosterCount) .. " guild bank alt" ..
                                          pluralRoster .. rosterAlts .. " on the roster."
        helloParts[#helloParts + 1] = "\n"
        helloParts[#helloParts + 1] =
            "I have guild bank data from " .. Globals.ColorizeText(colorGold, guildBankCount) .. " alt" .. pluralBanks .. bankAlts ..
                "."
    else
        helloParts[#helloParts + 1] = " I know about " .. Globals.ColorizeText(colorGold, 0) ..
                                          " guild bank alts on the roster, and have guild bank data from " ..
                                          Globals.ColorizeText(colorGold, 0) .. " alts."
    end

    local hello = table_concat(helloParts)
    local data = serializePayload(hello)

    if messageType ~= "reply" then
        local now = GetServerTime()
        local last = self.lastHelloTime or 0
        if now - last < 300 then
            GBCR.Output:Debug("PROTOCOL", "sendHello suppressed (last was %ds ago)", now - last)

            return
        end
        self.lastHelloTime = now

        GBCR.Output:Info(hello)
        sendCommMessage("gbc-h", data, "GUILD", nil, "NORMAL")
    else
        if target then
            sendWhisper("gbc-hr", data, target, "NORMAL")
        end
    end
end

-- Send a wipeall (gbc-w) so every online member wipes their data (and confirms with gbc-wr) upon /bank wipeall (only officers)
local function sendWipeAll()
    local guildName = GBCR.Guild:GetGuildInfo()
    if not guildName or not GBCR.Guild.weCanEditOfficerNotes then
        GBCR.Output:Error("Access denied. Only guild members with permission to edit officer notes are permitted to do this.")
        GBCR.Output:Debug("PROTOCOL", "sendWipeAll blocked: guildName=%s, weCanEditOfficerNotes=%s", tostring(guildName),
                          tostring(GBCR.Guild.weCanEditOfficerNotes))

        return
    end

    local wipeMessage = "I wiped all addon data from " .. guildName .. "."
    GBCR.Guild:ResetGuild()

    local data = serializePayload(wipeMessage)
    sendCommMessage("gbc-w", data, "GUILD", nil, "NORMAL")
end

-- Helper to generate a tiny, 1-chunk representation of the entire guild bank state (gbc-hash) to broadcast upon logging in
local function getStateHash()
    local fp = craftFingerprintPayload()
    local hash = 5381

    for i = 1, #fp do
        local v = fp[i]
        local t = type(v)

        if t == "number" then
            hash = ((hash * 33) + v) % 4294967296
        elseif t == "boolean" then
            hash = ((hash * 33) + (v and 1 or 0)) % 4294967296
        elseif t == "string" then
            for j = 1, string_len(v) do
                hash = ((hash * 33) + string_byte(v, j)) % 4294967296
            end
        end
    end

    return tostring(hash)
end

-- Helper to broadcast our guild bank state (gbc-hash)
local function gossipLoop()
    if not Protocol.gossipLoopRunning then
        return
    end

    if not GBCR.Guild or not GBCR.Guild:GetGuildInfo() then
        Protocol.gossipLoopRunning = false

        return
    end

    if not Protocol.isLockedOut then
        sendCommMessage("gbc-hash", GBCR.Core.addonVersionNumber .. ":" .. getStateHash(), "GUILD", nil, "NORMAL")
    end

    After(Constants.TIMER_INTERVALS.GOSSIP_CYCLE or 900, gossipLoop)
end

-- Helper to determine what the login broadcast (gbc-hash) jitter should be based on online member count
local function getAdaptiveLoginJitter()
    local online = GBCR.Guild.cachedOnlineGuildMemberCount or 0
    if online <= 5 then
        return math_random(3, 8)
    elseif online <= 20 then
        return math_random(5, 20)
    elseif online <= 100 then
        return math_random(10, 35)
    else
        return math_random(Constants.JITTER.LOGIN_MIN, Constants.JITTER.LOGIN_MAX)
    end
end

-- Send our guild bank state (gbc-hash) upon logging in, and on a continuous 15-minute cycle
local function sendStateHash(self)
    self.gossipLoopRunning = false

    if self.timerLoginHashBroadcast then
        self.timerLoginHashBroadcast:Cancel()
        self.timerLoginHashBroadcast = nil
    end

    local jitter = getAdaptiveLoginJitter()

    GBCR.Output:Debug("PROTOCOL", "Login detected, scheduled hash broadcast in %d seconds", jitter)

    self.timerLoginHashBroadcast = NewTimer(jitter, function()
        if not self.isLockedOut then
            sendCommMessage("gbc-hash", GBCR.Core.addonVersionNumber .. ":" .. getStateHash(), "GUILD", nil, "NORMAL")
        end
        self.timerLoginHashBroadcast = nil

        self.gossipLoopRunning = true
        After(Constants.TIMER_INTERVALS.GOSSIP_CYCLE or 900, gossipLoop)
    end)
end

-- Send a small alert (gbc-announce) that our guild bank data (inventory and ledger) just got updated
local function sendAnnounce(self, altName)
    if self.isLockedOut then
        return
    end

    sendCommMessage("gbc-announce", altName, "GUILD", nil, "NORMAL")
end

-- ================================================================================================
-- Helper for the sync status
local function formatSyncStatus(status)
    if status == Constants.ADOPTION_STATUS.ADOPTED then
        return "(newer, integrating)"
    end
    if status == Constants.ADOPTION_STATUS.STALE then
        return "(older, discarding)"
    end
    if status == Constants.ADOPTION_STATUS.INVALID then
        return "(invalid, ignoring)"
    end
    if status == Constants.ADOPTION_STATUS.UNAUTHORIZED then
        return "(unauthorized, ignoring)"
    end
    if status == Constants.ADOPTION_STATUS.IGNORED then
        return "(ignored)"
    end

    return ""
end

-- Helper to determine whether to accept data or not
local function isAltDataAllowed(sender, claimedNorm)
    if not GBCR.Guild:GetGuildMemberInfo(sender) then
        GBCR.Output:Debug("PROTOCOL", "Rejecting data from %s (not a guild member)", claimedNorm)

        return false
    end

    if not GBCR.Guild:IsGuildBankAlt(claimedNorm) then
        GBCR.Output:Debug("PROTOCOL", "Rejecting data for %s (not a guild bank alt)", claimedNorm)

        return false
    end

    return true
end

-- Debounce timer cleanup
local function cancelAllDebounceTimers(self)
    if self.fingerprintResponseTimer then
        self.fingerprintResponseTimer:Cancel()
        self.fingerprintResponseTimer = nil
    end
    self.pendingFingerprintResponses = nil

    if self.debounceHardDeadlineTimer then
        self.debounceHardDeadlineTimer:Cancel()
        self.debounceHardDeadlineTimer = nil
    end
    if self.debounceTimers then
        if self.debounceTimers.multipleAlts then
            self.debounceTimers.multipleAlts:Cancel()
            self.debounceTimers.multipleAlts = nil
        end
        if self.debounceTimers.singularAlt then
            for _, timer in pairs(self.debounceTimers.singularAlt) do
                timer:Cancel()
            end
            wipe(self.debounceTimers.singularAlt)
        end
    end

    if self.debounceQueues then
        wipe(self.debounceQueues.multipleAlts)
        wipe(self.debounceQueues.singularAlt)
    end

    if self.requestTimeoutTimers then
        for _, timer in pairs(self.requestTimeoutTimers) do
            timer:Cancel()
        end
        wipe(self.requestTimeoutTimers)
    end

    if self.requestRetryTimers then
        for _, timer in pairs(self.requestRetryTimers) do
            timer:Cancel()
        end
        wipe(self.requestRetryTimers)
    end
end

-- Helper to generate debounce key for messages with a singular guild bank alt
local function getDebounceKey(prefix, data)
    if prefix == "gbc-data-share" and data[2] then
        local name = GBCR.Guild:FindGuildMemberByUid(data[2])
        return "gbc-data-share:" .. (name or data[2])
    elseif prefix == "gbc-roster-share" then
        return "gbc-roster-share"
    end

    return prefix
end

-- Helper to extract version from the payload of messages with a singular guild bank alt
local function extractVersionFromSingularGuildBankAltPayload(prefix, data)
    if prefix == "gbc-fp-share" then
        return nil
    elseif prefix == "gbc-data-share" then
        return data[3]
    elseif prefix == "gbc-roster-share" and data.roster then
        return data.roster.version
    end

    return nil, nil
end

-- Helper to check if incoming is better than existing
local function shouldReplaceQueuedData(existing, newVersion)
    if not existing then
        return true
    end

    if newVersion == 0 then
        return false
    end

    if newVersion and existing.version then
        return newVersion > existing.version
    elseif newVersion and not existing.version then
        return true
    end

    return true
end

-- Helper to process guild bank alt data (gbc-data-share)
local function processGuildBankAltData(self, data, sender)
    local altName = GBCR.Guild:FindGuildMemberByUid(data[2])

    local allowed = isAltDataAllowed(sender, altName)
    if consumePendingSync(self, "alt", sender, altName) then
        allowed = true
    end

    local status = allowed and receiveData(self, data, sender) or Constants.ADOPTION_STATUS.UNAUTHORIZED
    GBCR.Output:Debug("PROTOCOL", GBCR.Guild:ColorPlayerName(sender), Globals.ColorizeText(colorBlue, "shares"),
                      "bank data about", GBCR.Guild:ColorPlayerName(altName) .. ": we",
                      allowed and "accept it" or "do not accept it", formatSyncStatus(status))

    if allowed and status == Constants.ADOPTION_STATUS.ADOPTED then
        GBCR.Output:Info("Received data for %s from %s.", GBCR.Guild:ColorPlayerName(altName), GBCR.Guild:ColorPlayerName(sender))
        GBCR.UI:QueueUIRefresh()
    elseif allowed then
        GBCR.Output:Debug("PROTOCOL", "Ignoring data for %s from %s (reason: %s)", GBCR.Guild:ColorPlayerName(altName),
                          GBCR.Guild:ColorPlayerName(sender), status)
    else
        return
    end
end

-- Helper to process the alt version from a fingerprint broadcast (gbc-fp-share)
local function processFingerprintAltData(self, fingerprintAltData, sender)
    local queryCount = 0
    local ourPlayer = GBCR.Guild:GetNormalizedPlayerName()

    self.altDataSources = self.altDataSources or {}

    for altName, altData in pairs(fingerprintAltData) do
        if altName ~= ourPlayer then
            local incomingVersion = type(altData) == "table" and altData.version or 0
            local actualSender = sender or altData.sender

            self.altDataSources[altName] = self.altDataSources[altName] or {}
            if actualSender then
                self.altDataSources[altName][actualSender] = incomingVersion
            end

            local shouldQuery = false
            local ourAlt = GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts and
                               GBCR.Database.savedVariables.alts[altName]
            local ourVersion = type(ourAlt) == "table" and ourAlt.version

            GBCR.Output:Debug("PROTOCOL", "Evaluating fingerprint from %s for %s (incomingVersion=%d, ourVersion=%s)",
                              GBCR.Guild:ColorPlayerName(sender or altData.sender), GBCR.Guild:ColorPlayerName(altName),
                              tostring(incomingVersion), tostring(ourVersion))

            if not ourVersion or incomingVersion > ourVersion then
                shouldQuery = true
                GBCR.Output:Debug("PROTOCOL", "Query decision for %s: incoming version is newer, query",
                                  GBCR.Guild:ColorPlayerName(altName))
            else
                GBCR.Output:Debug("PROTOCOL", "Query decision for %s: incoming version is same or older, don't query",
                                  GBCR.Guild:ColorPlayerName(altName))
            end

            if shouldQuery then
                setAltProtocolState(self, altName, Constants.STATE.OUTDATED)

                After(math_random(Constants.JITTER.QUERY_MIN, Constants.JITTER.QUERY_MAX), function()
                    queryForGuildBankAltData(Protocol, sender or altData.sender, altName)
                end)

                queryCount = queryCount + 1
            end
        end
    end

    return queryCount
end

-- Helper to process roster data (gbc-roster-share)
local function processRosterData(self, data, sender)
    local isSenderAuthority = GBCR.Guild.cachedGuildMembers and GBCR.Guild.cachedGuildMembers[sender] and
                                  GBCR.Guild.cachedGuildMembers[sender].isAuthority

    if not isSenderAuthority then
        GBCR.Output:Debug("PROTOCOL", "%s sent roster data but is not an authority: rejected", GBCR.Guild:ColorPlayerName(sender))

        return
    end

    if not (data and data.roster) then
        return
    end

    local sv = GBCR.Database.savedVariables
    if not sv then
        return
    end

    local newVersion = data.roster.version or 0
    local currentVersion = sv.roster and sv.roster.version or 0
    if newVersion <= currentVersion and currentVersion ~= 0 then
        GBCR.Output:Debug("PROTOCOL", "Ignored roster from %s: stale version", sender)

        return
    end

    GBCR.Output:Debug("PROTOCOL", "%s %s roster (v%d): accepted", GBCR.Guild:ColorPlayerName(sender),
                      Globals.ColorizeText(colorBlue, "shares"), newVersion)
    consumePendingSync(self, "roster", sender)

    local oldAlts = sv.roster and sv.roster.alts or {}
    local newAlts = data.roster.alts or {}

    local newSet = {}
    for _, name in ipairs(newAlts) do
        newSet[name] = true
    end

    local removedAny = false
    for _, name in ipairs(oldAlts) do
        if not newSet[name] and sv.alts and sv.alts[name] then
            sv.alts[name] = nil
            removedAny = true
            GBCR.Output:Info("%s is no longer a guild bank alt. Their data has been removed.", GBCR.Guild:ColorPlayerName(name))
            GBCR.Output:Debug("PROTOCOL", "Wiped guild bank alt data on roster-share for %s", name)
        end
    end

    if removedAny then
        GBCR.UI.Inventory:MarkAllDirty()
    end

    sv.roster = sv.roster or {}

    sv.roster.alts = sv.roster.alts or {}
    wipe(sv.roster.alts)
    for i = 1, #newAlts do
        sv.roster.alts[i] = newAlts[i]
    end

    sv.roster.version = newVersion

    sv.roster.manualAlts = sv.roster.manualAlts or {}
    wipe(sv.roster.manualAlts)
    if data.roster.manualAlts then
        for i = 1, #data.roster.manualAlts do
            sv.roster.manualAlts[i] = data.roster.manualAlts[i]
        end
    end

    if data.roster.areOfficerNotesUsed ~= nil then
        sv.roster.areOfficerNotesUsed = data.roster.areOfficerNotesUsed
        GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts = data.roster.areOfficerNotesUsed
        GBCR.Output:Debug("PROTOCOL", "areOfficerNotesUsedToDefineGuildBankAlts set to %s by authority %s",
                          tostring(data.roster.areOfficerNotesUsed), GBCR.Guild:ColorPlayerName(sender))
    end

    sv.alts = sv.alts or {}
    for _, normName in ipairs(newAlts) do
        if not sv.alts[normName] then
            sv.alts[normName] = {name = normName, version = 0, money = 0, items = {}, ledger = {}}
        end
    end

    GBCR.UI:QueueUIRefresh()
end

-- Helper to process debounced message containing data for multiple guild bank alts
local function processDebouncedMessageWithMultipleGuildBankAlts(self)
    self.debounceTimers.multipleAlts = nil
    if self.debounceHardDeadlineTimer then
        self.debounceHardDeadlineTimer:Cancel()
        self.debounceHardDeadlineTimer = nil
    end

    GBCR.Output:Debug("PROTOCOL", "Processing debounced guild bank alt data (alts=%d)",
                      Globals.Count(self.debounceQueues.multipleAlts))

    local queryCount = processFingerprintAltData(self, self.debounceQueues.multipleAlts)
    local pluralQueries = (queryCount ~= 1 and "s" or "")
    GBCR.Output:Debug("PROTOCOL", "Queried data for %d guild bank alt%s from best sources", queryCount, pluralQueries)

    wipe(self.debounceQueues.multipleAlts)
end

-- Helper to process fingerprint broadcast (gbc-fp-share)
local function processFingerprint(self, payload, sender)
    local incomingData = parseFingerprintPayload(payload)

    local incomingAddonVersionNumber = incomingData.addonVersionNumber
    local incomingAreOfficerNotesUsedToDefineGuildBankAlts = incomingData.areOfficerNotesUsedToDefineGuildBankAlts
    local incomingIsGuildBankAlt = incomingData.isGuildBankAlt
    local incomingAlts = incomingData.alts
    local incomingRosterVersionTimestamp = incomingData.rosterVersionTimestamp

    trackSenderMetadata(self, sender, incomingAddonVersionNumber or 0, incomingIsGuildBankAlt or false,
                        incomingRosterVersionTimestamp or 0)

    if incomingAreOfficerNotesUsedToDefineGuildBankAlts and incomingAreOfficerNotesUsedToDefineGuildBankAlts ~=
        GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts then
        GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts = incomingAreOfficerNotesUsedToDefineGuildBankAlts
    end

    local altCount = incomingAlts and Globals.Count(incomingAlts)
    GBCR.Output:Debug("PROTOCOL", GBCR.Guild:ColorPlayerName(sender), Globals.ColorizeText(colorBlue, "shares"), "fingerprint",
                      string_format("(%d guild bank alts)", altCount))

    local guildName = GBCR.Guild:GetGuildInfo()
    if guildName then
        local localRosterVersion = GBCR.Database.savedVariables and GBCR.Database.savedVariables.roster and
                                       GBCR.Database.savedVariables.roster.version

        local shouldQueryRoster = incomingRosterVersionTimestamp and
                                      (localRosterVersion == nil or incomingRosterVersionTimestamp > localRosterVersion)

        if shouldQueryRoster then
            GBCR.Output:Debug("PROTOCOL", "Roster query triggered by %s (local=%s, incoming=%s)",
                              GBCR.Guild:ColorPlayerName(sender), tostring(localRosterVersion),
                              tostring(incomingRosterVersionTimestamp))
            queryForRosterData(self, sender, incomingRosterVersionTimestamp)
        end

        local senderCacheEntry = GBCR.Guild.cachedGuildMembers and GBCR.Guild.cachedGuildMembers[sender]
        local isSenderAuthority = senderCacheEntry and senderCacheEntry.isAuthority

        if isSenderAuthority and incomingAreOfficerNotesUsedToDefineGuildBankAlts ~= nil then
            if incomingAreOfficerNotesUsedToDefineGuildBankAlts ~= GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts then
                GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts = incomingAreOfficerNotesUsedToDefineGuildBankAlts

                if GBCR.Database.savedVariables and GBCR.Database.savedVariables.roster then
                    GBCR.Database.savedVariables.roster.areOfficerNotesUsed = incomingAreOfficerNotesUsedToDefineGuildBankAlts
                end

                GBCR.Output:Debug("PROTOCOL", "areOfficerNotesUsed updated to %s by authority %s",
                                  tostring(incomingAreOfficerNotesUsedToDefineGuildBankAlts), GBCR.Guild:ColorPlayerName(sender))
            end
        end

        if incomingAlts then
            local queryCount = processFingerprintAltData(self, incomingAlts, sender)
            local pluralQueries = (queryCount ~= 1 and "s" or "")
            GBCR.Output:Debug("PROTOCOL", "Queried data for %d guild bank alt%s", queryCount, pluralQueries)
        end
    end
end

-- Helper to queue debounced message containing data for multiple guild bank alts (gbc-fp-share)
local function queueDebouncedMessageWithMultipleGuildBankAlts(self, sender, payload)
    if not self.debounceConfig.enabled then
        processFingerprint(self, payload, sender)

        return true
    end

    if self.debounceTimers.multipleAlts then
        self.debounceTimers.multipleAlts:Cancel()
        self.debounceTimers.multipleAlts = nil
    end

    local incomingData = parseFingerprintPayload(payload)

    local incomingAddonVersionNumber = incomingData.addonVersionNumber
    local incomingIsGuildBankAlt = incomingData.isGuildBankAlt
    local incomingAlts = incomingData.alts
    local incomingRosterVersionTimestamp = incomingData.rosterVersionTimestamp

    trackSenderMetadata(self, sender, incomingAddonVersionNumber, incomingIsGuildBankAlt, incomingRosterVersionTimestamp)

    local queued = false
    local now = GetServerTime()

    for altName, altInfo in pairs(incomingAlts) do
        local altNorm = GBCR.Guild:NormalizePlayerName(altName)
        local isSelf = altName == GBCR.Guild:GetNormalizedPlayerName()
        if not isSelf then
            local incomingVersion = type(altInfo) == "table" and altInfo.version or altInfo
            local existing = self.debounceQueues.multipleAlts[altNorm]

            if shouldReplaceQueuedData(existing, incomingVersion) then
                self.debounceQueues.multipleAlts[altNorm] = {version = incomingVersion, sender = sender, queuedAt = now}
                GBCR.Output:Debug("PROTOCOL", "Best sender for %s is now %s (incomingVersion=%s)",
                                  GBCR.Guild:ColorPlayerName(altNorm), GBCR.Guild:ColorPlayerName(sender),
                                  tostring(incomingVersion))
                queued = true
            end
        end
    end

    if queued then
        local interval = self.debounceConfig.intervals["gbc-fp-share"] or 3.0

        if self.debounceTimers.multipleAlts then
            self.debounceTimers.multipleAlts:Cancel()
            self.debounceTimers.multipleAlts = nil
        end
        self.debounceTimers.multipleAlts = NewTimer(interval, function()
            processDebouncedMessageWithMultipleGuildBankAlts(self)
        end)

        if not self.debounceHardDeadlineTimer then
            self.debounceHardDeadlineTimer = NewTimer(Constants.TIMER_INTERVALS.DEBOUNCE_HARD_DEADLINE, function()
                self.debounceHardDeadlineTimer = nil
                if self.debounceTimers.multipleAlts then
                    self.debounceTimers.multipleAlts:Cancel()
                    self.debounceTimers.multipleAlts = nil
                end
                processDebouncedMessageWithMultipleGuildBankAlts(self)
            end)
        end

        GBCR.Output:Debug("PROTOCOL",
                          "Queued processing of guild bank alt data from %s for %d guild bank alts (processing in %.1fs)",
                          GBCR.Guild:ColorPlayerName(sender), Globals.Count(incomingAlts or {}), interval)
    end

    return true
end

-- Helper to process debounced message containing data for a singular guild bank alt
local function processDebouncedMessageWithSingularGuildBankAlt(self, key)
    local queued = self.debounceQueues.singularAlt[key]
    if not queued then
        return
    end

    self.debounceQueues.singularAlt[key] = nil
    self.debounceTimers.singularAlt[key] = nil

    GBCR.Output:Debug("PROTOCOL", "Processing debounced queue for %s (version=%s)", key, tostring(queued.version))

    if queued.prefix == "gbc-data-share" then
        processGuildBankAltData(self, queued.data, queued.sender)
    elseif queued.prefix == "gbc-roster-share" then
        processRosterData(self, queued.data, queued.sender)
    end
end

-- Helper to queue debounced message containing data for a singular guild bank alt (gbc-data-share or gbc-roster-share)
local function queueDebouncedMessageWithSingularGuildBankAlt(self, prefix, message, distribution, sender, data)
    if not self.debounceConfig.enabled then
        return false
    end

    local key = getDebounceKey(prefix, data)
    local version = extractVersionFromSingularGuildBankAltPayload(prefix, data)
    local interval = self.debounceConfig.intervals[key] or self.debounceConfig.intervals[prefix] or 2.0
    local existing = self.debounceQueues.singularAlt[key]
    local now = GetServerTime()

    if not shouldReplaceQueuedData(existing, version) then
        GBCR.Output:Debug("PROTOCOL", "Discarded older %s for key `%s` (queued version=%d vs incoming version=%d)", prefix, key,
                          existing and existing.version or 0, version or 0)

        return true
    end

    if self.debounceTimers.singularAlt[key] then
        self.debounceTimers.singularAlt[key]:Cancel()
        self.debounceTimers.singularAlt[key] = nil
    end

    self.debounceQueues.singularAlt[key] = {
        prefix = prefix,
        message = message,
        distribution = distribution,
        sender = sender,
        data = data,
        version = version,
        queuedAt = now
    }

    self.debounceTimers.singularAlt[key] = NewTimer(interval, function()
        processDebouncedMessageWithSingularGuildBankAlt(self, key)
    end)

    GBCR.Output:Debug("PROTOCOL", "Queued processing of %s (version=%s, processing in %.1fs)", key, tostring(version), interval)

    return true
end

-- Helper to request missing guild bank alt data
local function requestMissingGuildBankAltData()
    local rosterAlts = GBCR.Database:GetRosterGuildBankAlts()
    if not rosterAlts or #rosterAlts == 0 then
        return
    end

    local missing = {}
    local missingPosition = 1

    GBCR.Output:Debug("SYNC", "requestMissingGuildBankAltData: starting check of %d guild bank alts on the roster", #rosterAlts)

    local altsSavedVars = GBCR.Database.savedVariables.alts
    local output = GBCR.Output

    for i = 1, #rosterAlts do
        local guildBankAltName = rosterAlts[i]
        local norm = GBCR.Guild:NormalizePlayerName(guildBankAltName)
        local localAlt = altsSavedVars and norm and altsSavedVars[norm]
        local hasEntry = localAlt ~= nil
        local hasContent = hasEntry and hasAltContent(localAlt, norm)
        local isSelf = norm == GBCR.Guild:GetNormalizedPlayerName()

        output:Debug("SYNC", "requestMissingGuildBankAltData: checking %s (hasEntry=%s, hasContent=%s, self=%s)", tostring(norm),
                     tostring(hasEntry), tostring(hasContent), tostring(isSelf))

        if (not hasEntry or not hasContent) and not isSelf then
            missing[missingPosition] = norm
            missingPosition = missingPosition + 1
        end
    end

    if #missing == 0 then
        GBCR.Output:Debug("SYNC", "requestMissingGuildBankAltData: no missing data")

        return
    end

    GBCR.Output:Info("Requesting missing data for %d guild bank alts (have data for %d/%d).", #missing, #rosterAlts - #missing,
                     #rosterAlts)

    for _, norm in ipairs(missing) do
        queryForGuildBankAltData(Protocol, nil, norm)
    end
end

-- Centralized sync function for both /sync command and UI opening
local function performSync(self)
    local now = GetServerTime()
    local last = self.lastSync or 0
    if now - last > Constants.TIMER_INTERVALS.MANUAL_SYNC_COOLDOWN then
        self.lastSync = now
        sendFingerprint(self)
        requestMissingGuildBankAltData()
    end
end

-- ================================================================================================
-- Helper to queue incoming heavy payloads that need deserialization
local function processNextIncomingPayload(self)
    if self.queueHead >= self.queueTail then
        self.queueHead = 1
        self.queueTail = 1
        self.isProcessingIncoming = false

        return
    end

    if not self.isAcceptingIncoming then
        self.queueHead = 1
        self.queueTail = 1
        wipe(self.incomingPayloadQueue)
        self.isProcessingIncoming = false

        return
    end

    self.isProcessingIncoming = true

    local payloadData = self.incomingPayloadQueue[self.queueHead]
    self.incomingPayloadQueue[self.queueHead] = nil
    self.queueHead = self.queueHead + 1

    local success, data = deSerializePayload(payloadData.message)

    if not success then
        GBCR.Output:Debug("COMMS", "<", "(error)", payloadData.prefix, prefixDescriptions[payloadData.prefix] or "(Unknown)",
                          "from", GBCR.Guild:ColorPlayerName(payloadData.sender),
                          "(failed to deserialize, error=" .. tostring(data) .. ")")
    else
        GBCR.Output:Debug("COMMS", "<", payloadData.prefix, prefixDescriptions[payloadData.prefix] or "(Unknown)", "via",
                          payloadData.distribution, "from", GBCR.Guild:ColorPlayerName(payloadData.sender),
                          "(" .. (#payloadData.message or 0) .. " bytes)")

        local prefix = payloadData.prefix
        local sender = payloadData.sender
        local distribution = payloadData.distribution
        local message = payloadData.message

        if prefix == "gbc-fp-share" then
            if not queueDebouncedMessageWithMultipleGuildBankAlts(self, sender, data) then
                processFingerprint(self, data, sender)
            end
        elseif prefix == "gbc-data-share" then
            if not queueDebouncedMessageWithSingularGuildBankAlt(self, prefix, message, distribution, sender, data) then
                processGuildBankAltData(self, data, sender)
            end
        elseif prefix == "gbc-roster-share" then
            if not queueDebouncedMessageWithSingularGuildBankAlt(self, prefix, message, distribution, sender, data) then
                processRosterData(self, data, sender)
            end
        end
    end

    local queueDepth = self.queueTail - self.queueHead
    local delay = 0
    if queueDepth >= 4 then
        delay = 0.3
    elseif queueDepth >= 1 then
        delay = 0.1
    end

    if #payloadData.message > 5000 then
        delay = math_max(delay, 0.2)
    end

    After(delay, function()
        processNextIncomingPayload(Protocol)
    end)
end

-- Main handler for processing incomming addon communications
local function onCommReceived(self, prefix, message, distribution, sender)
    local prefixDesc = prefixDescriptions[prefix] or "(Unknown)"
    local player = GBCR.Guild:GetNormalizedPlayerName()
    sender = GBCR.Guild:NormalizePlayerName(sender)

    if not GBCR.Guild.cachedPlayerName and not GBCR.Core.addonVersionNumber then
        GBCR.Output:Debug("COMMS", "<", "(ignoring)", prefix, prefixDesc, "(not ready yet)")

        return
    end

    if IsInInstance() or IsInRaid() then
        GBCR.Output:Debug("COMMS", "<", "(suppressing)", prefix, prefixDesc, "from", GBCR.Guild:ColorPlayerName(sender),
                          "(in instance or raid)")

        return
    end

    if player == sender then
        GBCR.Output:Debug("COMMS", "<", "(ignoring)", prefix, prefixDesc, "(our own)")

        return
    end

    if prefix == "gbc-hash" then
        local incomingAddonVersionNumber, incomingStateHash = string_match(message, "([^:]+):([^:]+)")
        trackSenderMetadata(self, sender, incomingAddonVersionNumber or nil, nil, nil)

        local myStateHash = getStateHash()
        if incomingStateHash == myStateHash then
            if self.timerLoginHashBroadcast then
                self.timerLoginHashBroadcast:Cancel()
                self.timerLoginHashBroadcast = nil
                GBCR.Output:Debug("PROTOCOL", "Login hash boadcast suppressed given that %s has the same state hash", sender)
                self.gossipLoopRunning = true
                After(Constants.TIMER_INTERVALS.GOSSIP_CYCLE or 900, gossipLoop)
            end
        else
            if not self.isLockedOut then
                for altName, sources in pairs(self.altDataSources or {}) do
                    if sources[sender] then
                        setAltProtocolState(self, altName, Constants.STATE.DISCOVERING)
                    end
                end

                After(math_random(Constants.JITTER.HASH_MISMATCH_MIN, Constants.JITTER.HASH_MISMATCH_MAX), function()
                    local payload = {requester = player}
                    local data = serializePayload(payload)
                    sendWhisper("gbc-fp-query", data, sender, "NORMAL")
                end)
            end
        end

        return
    end

    if prefix == "gbc-announce" then
        local altName = message

        if self.protocolStates[altName] ~= Constants.STATE.REQUESTING then
            setAltProtocolState(self, altName, Constants.STATE.OUTDATED)
        end

        After(math_random(Constants.JITTER.ANNOUNCE_MIN, Constants.JITTER.ANNOUNCE_MAX), function()
            queryForGuildBankAltData(Protocol, sender, altName)
        end)

        return
    end

    local isHeavyPayload = (prefix == "gbc-fp-share" or prefix == "gbc-data-share" or prefix == "gbc-roster-share")
    if isHeavyPayload then
        self.incomingPayloadQueue[self.queueTail] = {
            prefix = prefix,
            message = message,
            distribution = distribution,
            sender = sender
        }
        self.queueTail = self.queueTail + 1

        if not self.isProcessingIncoming then
            processNextIncomingPayload(self)
        end

        return
    end

    local success, data = deSerializePayload(message)
    if not success then
        GBCR.Output:Debug("COMMS", "<", "(error)", prefix, prefixDesc, "from", GBCR.Guild:ColorPlayerName(sender),
                          "(failed to deserialize, error=" .. tostring(data) .. ")")

        return
    end

    if GBCR.Options:IsDebugEnabled() then
        local tablePayload = {}
        local payload
        if type(data) == "table" then
            for k, v in pairs(data) do
                tablePayload[#tablePayload + 1] = k .. "=" .. tostring(v)
            end
            payload = table_concat(tablePayload, ",")
        else
            payload = data
        end
        GBCR.Output:Debug("COMMS", "<", prefix, prefixDesc, "via", distribution, "from", sender, "(" .. (#message or 0) ..
                              " bytes" .. (type(data) == "table" and data.type and ", type=" .. tostring(data.type) or "") .. ")",
                          "payload:", payload)
    else
        GBCR.Output:Debug("COMMS", "<", prefix, prefixDesc, "via", distribution, "from", GBCR.Guild:ColorPlayerName(sender),
                          "(" .. (#message or 0) .. " bytes" ..
                              (type(data) == "table" and data.type and ", type=" .. tostring(data.type) or "") .. ")")
    end

    if prefix == "gbc-fp-query" then
        local requester = data and data.requester
        if requester then
            if not self.pendingFingerprintResponses then
                self.pendingFingerprintResponses = {}
            end
            self.pendingFingerprintResponses[requester] = true

            if not self.fingerprintResponseTimer then
                self.fingerprintResponseTimer = NewTimer(Constants.TIMER_INTERVALS.FINGERPRINT_RESPONSE_BATCH, function()
                    self.fingerprintResponseTimer = nil
                    local targets = self.pendingFingerprintResponses
                    self.pendingFingerprintResponses = nil

                    local count = 0
                    for _ in pairs(targets) do
                        count = count + 1
                    end

                    if count >= 5 then
                        GBCR.Output:Debug("PROTOCOL", "Broadcasting fp-share to guild for %d requesters", count)
                        sendFingerprint(self)
                    else
                        for target in pairs(targets) do
                            sendFingerprint(self, target)
                        end
                    end
                end)
            end
        end

        return
    end

    if prefix == "gbc-data-query" then
        if data.busy then
            GBCR.Output:Debug("PROTOCOL", GBCR.Guild:ColorPlayerName(sender), "is busy, queuing retry for", data.name)

            setAltProtocolState(self, data.name, Constants.STATE.OUTDATED)

            After(math_random(Constants.JITTER.RETRY_MIN, Constants.JITTER.RETRY_MAX), function()
                queryForGuildBankAltData(Protocol, sender, data.name)
            end)

            return
        end

        local altName = data.name
        local hasData = GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts and
                            GBCR.Database.savedVariables.alts[altName] ~= nil
        local isStillAGuildBankAlt = GBCR.Guild:IsGuildBankAlt(altName) or false

        if sender == altName then
            GBCR.Output:Debug("PROTOCOL", GBCR.Guild:ColorPlayerName(sender), Globals.ColorizeText(colorYellow, "queries"),
                              "guild bank alt data for themselves: ignored")

            return
        end

        GBCR.Output:Debug("PROTOCOL", GBCR.Guild:ColorPlayerName(sender), Globals.ColorizeText(colorYellow, "queries"),
                          "guild bank alt data for", GBCR.Guild:ColorPlayerName(altName), "")

        if hasData and isStillAGuildBankAlt then
            local responseKey = (altName or "?") .. "|" .. (sender or "?")
            self.recentDataQueryResponses = self.recentDataQueryResponses or {}
            local lastResponse = self.recentDataQueryResponses[responseKey] or 0
            local now = GetServerTime()
            if now - lastResponse < 60 then
                GBCR.Output:Debug("PROTOCOL", "Query from %s for %s: rate-limited (last response %ds ago)", sender, altName,
                                  now - lastResponse)
            else
                self.recentDataQueryResponses[responseKey] = now
                sendData(self, altName, sender)
            end
        end

        return
    end

    if prefix == "gbc-roster-query" then
        local myPlayer = GBCR.Guild:GetNormalizedPlayerName()

        local selfEntry = GBCR.Guild.cachedGuildMembers and GBCR.Guild.cachedGuildMembers[myPlayer]
        if not (selfEntry and selfEntry.isAuthority) then
            GBCR.Output:Debug("PROTOCOL", "Roster query from %s: ignored (we are not an authority)",
                              GBCR.Guild:ColorPlayerName(sender))
            return
        end

        self.rosterQueryResponded = self.rosterQueryResponded or {}
        local lastResponse = self.rosterQueryResponded[sender] or 0
        local now = GetServerTime()
        if now - lastResponse < 60 then
            GBCR.Output:Debug("PROTOCOL", "Roster query from %s: rate-limited (%ds cooldown remaining)",
                              GBCR.Guild:ColorPlayerName(sender), 60 - (now - lastResponse))
            return
        end
        self.rosterQueryResponded[sender] = now

        GBCR.Output:Debug("PROTOCOL", "%s %s roster data", GBCR.Guild:ColorPlayerName(sender),
                          Globals.ColorizeText(colorYellow, "queries"))
        sendRoster(sender)

        return
    end

    if prefix == "gbc-h" then
        sendHello(self, "reply", sender)

        return
    end

    if prefix == "gbc-hr" then
        local message = tostring(data)
        local versionStr = string_match(message, "version (%d+)")
        if versionStr then
            local incomingAddonVersionNumber = tonumber(versionStr)
            self.guildMembersFingerprintData[sender] = {addonVersionNumber = incomingAddonVersionNumber, seen = GetServerTime()}
            GBCR.Output:Debug("ROSTER", "Parsed version %s for %s from hello reply", incomingAddonVersionNumber,
                              GBCR.Guild:ColorPlayerName(sender))

            checkAndWarnAddonOutdated(self, incomingAddonVersionNumber)
        end

        if GBCR.Options:IsDebugEnabled() then
            if self.printVersionsTimer then
                self.printVersionsTimer:Cancel()
                self.printVersionsTimer = nil
            end
            self.printVersionsTimer = NewTimer(15, function()
                self.printVersionsTimer = nil
                GBCR.Chat.PrintVersions()
            end)
        end

        return
    end

    if prefix == "gbc-w" then
        local guildName = GBCR.Guild:GetGuildInfo()
        if guildName then
            GBCR.Guild:ResetGuild()
            GBCR.Output:Info("Guild bank database has been reset by %s.", GBCR.Guild:ColorPlayerName(sender))

            local ackData = serializePayload("wiped")
            sendCommMessage("gbc-wr", ackData, "GUILD", nil, "NORMAL")
        end

        return
    end
end

-- Intialization
local function init(self)
    self.itemReconstructQueue = {}
    self.itemQueueHead = 1
    self.itemQueueTail = 1
    self.pendingAsyncLoads = 0
    self.isProcessingQueue = false

    self.incomingPayloadQueue = {}
    self.queueHead = 1
    self.queueTail = 1
    self.isProcessingIncoming = false

    self.requestTimeoutTimers = {}
    self.requestRetryTimers = {}
    self.isAcceptingIncoming = true

    self.pendingSync = {roster = {}, alts = {}}

    self.isAddonOutdated = false
    self.guildMembersFingerprintData = {}

    self.isLockedOut = false
    self.protocolStates = {}
    self.activeOutboundWhispers = 0

    self.bufferPayload = {}
    self.bufferUidIndex = {}
    self.bufferUid = {}
    self.bufferItems = {}
    self.bufferSortKeys = {}
    self.bufferIndices = {}
    self.bufferSortedItems = {}
    self.bufferParsedResult = {}
    self.bufferParsedUid = {}
    self.bufferParsedLedger = {}
    self.bufferParsedItems = {}

    self.recentDataQueryResponses = {}
    self.uiStatePending = false

    self.gossipLoopRunning = false

    self.debounceHardDeadlineTimer = nil
    self.fingerprintResponseTimer = nil
    self.pendingFingerprintResponses = nil

    self.lastFingerprintBroadcast = 0
    self.rosterQueryResponded = {}

    self.debounceConfig = {
        enabled = true,
        intervals = {["gbc-fp-share"] = 3.0, ["gbc-data-share"] = 2.5, ["gbc-roster-share"] = 2.0}
    }
    self.debounceQueues = {multipleAlts = {}, singularAlt = {}}
    self.debounceTimers = {multipleAlts = nil, singularAlt = {}}

    local commPrefixes = {
        "gbc-hash",
        "gbc-announce",
        "gbc-fp-share",
        "gbc-fp-query",
        "gbc-data-share",
        "gbc-data-query",
        "gbc-roster-share",
        "gbc-roster-query",
        "gbc-h",
        "gbc-hr",
        "gbc-w",
        "gbc-wr"
    }
    for _, prefix in ipairs(commPrefixes) do
        local p = prefix
        GBCR.Addon:RegisterComm(p, function(prefix, message, distribution, sender)
            onCommReceived(self, prefix, message, distribution, sender)
        end)
    end
end

-- ================================================================================================
-- Export functions for other modules
Protocol.ReconstructItemLinks = reconstructItemLinks

Protocol.PruneStaleProtocolStates = pruneStaleProtocolStates
Protocol.CleanupPendingSync = cleanupPendingSync
Protocol.UpdateSafetyLockout = updateSafetyLockout

Protocol.SendFingerprint = sendFingerprint
Protocol.SendRoster = sendRoster
Protocol.SendRosterIfAuthority = sendRosterIfAuthority
Protocol.SendHello = sendHello
Protocol.SendWipeAll = sendWipeAll
Protocol.SendStateHash = sendStateHash
Protocol.SendAnnounce = sendAnnounce

Protocol.CancelAllDebounceTimers = cancelAllDebounceTimers

Protocol.PerformSync = performSync

Protocol.OnCommReceived = onCommReceived
Protocol.Init = init
