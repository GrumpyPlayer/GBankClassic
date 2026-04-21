local addonName, GBCR = ...

GBCR.Guild = {}
local Guild = GBCR.Guild

local Globals = GBCR.Globals
local debugprofilestop = Globals.debugprofilestop
local ipairs = Globals.ipairs
local next = Globals.next
local select = Globals.select
local string_find = Globals.string_find
local string_match = Globals.string_match
local string_sub = Globals.string_sub
local table_remove = Globals.table_remove
local tostring = Globals.tostring
local wipe = Globals.wipe

local After = Globals.After
local CanViewOfficerNote = Globals.CanViewOfficerNote
local GetClassColor = Globals.GetClassColor
local GetGuildInfo = Globals.GetGuildInfo
local GetGuildRosterInfo = Globals.GetGuildRosterInfo
local GetNormalizedRealmName = Globals.GetNormalizedRealmName
local GetNumGuildMembers = Globals.GetNumGuildMembers
local GetServerTime = Globals.GetServerTime
local GuildControlGetNumRanks = Globals.GuildControlGetNumRanks
local GuildControlGetRankFlags = Globals.GuildControlGetRankFlags
local GuildControlGetRankName = Globals.GuildControlGetRankName
local IsInGuild = Globals.IsInGuild
local NewTicker = Globals.NewTicker
local UnitGUID = Globals.UnitGUID
local UnitName = Globals.UnitName
local NewTimer = Globals.NewTimer
local shouldYield = Globals.ShouldYield

local Constants = GBCR.Constants

-- ================================================================================================
-- Helper to cache the normalized realm name
local function getCachedNormalizedRealm(self)
    if not self.cachedNormalizedRealmName then
        self.cachedNormalizedRealmName = GetNormalizedRealmName()
    end

    return self.cachedNormalizedRealmName
end

-- Returns the normalized name (including the realm name) of a given name for database purposes
local function normalizePlayerName(self, name, noRealm)
    if not name then
        return nil
    end

    if not noRealm and self.cachedNormalizedPlayerName[name] then
        return self.cachedNormalizedPlayerName[name]
    end

    local trimmed = string_match(name, "^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    if trimmed:lower() == "unknown" then
        return "Unknown"
    end

    local playerName, playerRealm = string_match(trimmed, "^(.+)%-(.+)$")
    local currentRealm = getCachedNormalizedRealm(self)

    if not playerRealm then
        playerRealm = currentRealm
        playerName = trimmed
    end

    if noRealm then
        local noRealmKey = name .. "|nr"
        local cached = self.cachedNormalizedPlayerName[noRealmKey]
        if cached then
            return cached
        end

        local result
        if playerRealm == currentRealm then
            result = playerName
        else
            result = playerName .. "-" .. playerRealm
        end
        self.cachedNormalizedPlayerName[noRealmKey] = result

        return result
    end

    local result = playerName .. "-" .. playerRealm
    self.cachedNormalizedPlayerName[name] = result

    return result
end

-- Returns the normalized name (including the realm name) of the current player
local function getNormalizedPlayerName(self)
    if self.cachedPlayerName then
        return self.cachedPlayerName
    end

    local name, realm = UnitName("player"), getCachedNormalizedRealm(self)
    if name and realm and name ~= "Unknown" then
        self.cachedPlayerName = name .. "-" .. realm

        return self.cachedPlayerName
    end

    if not self.retryScheduled then
        self.retryScheduled = true

        local retryCount = 0
        local maxRetries = 20
        local timer

        timer = NewTicker(0.1, function()
            local retryName, retryRealm = UnitName("player"), getCachedNormalizedRealm(self)
            retryCount = retryCount + 1

            if retryName and retryRealm and retryName ~= "Unknown" then
                Guild.cachedPlayerName = retryName .. "-" .. retryRealm
                timer:Cancel()
                Guild.retryScheduled = false
            elseif retryCount >= maxRetries then
                timer:Cancel()
                Guild.retryScheduled = false
            end
        end)
    end

    return self.cachedPlayerName or "Unknown-Unknown"
end

-- ================================================================================================
-- Returns the guild info (guildName, guildRankName, guildRankIndex, realm) for the current player if they are in a guild
local function getGuildInfo()
    return IsInGuild("player") and GetGuildInfo("player") or nil
end

-- Find the name of a guild member by their uid which is used in addon communication to minimize the payload
local function findGuildMemberByUid(self, uid)
    if not uid then
        return nil, nil
    end

    local playerName = self.cachedGuildMemberUidToName[uid]
    if playerName then
        return playerName, self.cachedGuildMembers[playerName]
    end

    return nil, nil
end

-- Retrieve the UID for a given name
local function determineUidForGuildMemberName(self, name)
    if not name then
        return ""
    end

    local norm = normalizePlayerName(self, name)
    local info = norm and self.cachedGuildMembers and self.cachedGuildMembers[norm]

    return (info and info.playerUid) or "a player outside the guild"
end

-- Return the player's class, and whether or not they are the are able to view officer notes (consider an authority), based on the cached guild member data
local function getGuildMemberInfo(self, playerName)
    if not playerName then
        return false
    end

    local guildMemberFromCache = self.cachedGuildMembers[normalizePlayerName(self, playerName)]
    local playerClass = guildMemberFromCache and guildMemberFromCache.playerClass or nil
    local isAuthority = guildMemberFromCache and guildMemberFromCache.isAuthority or false

    return playerClass, isAuthority
end

-- Check if a player is currently online in the guild
local function isPlayerOnlineGuildMember(self, playerName)
    if not playerName then
        return false
    end

    return self.cachedOnlineGuildMembers[normalizePlayerName(self, playerName)] == true
end

-- Check if a player is currently online in the guild and a guild bank alt
local function isPlayerOnlineGuildBankAlt(self, playerName)
    if not playerName then
        return false
    end

    return self.cachedOnlineGuildBankAlts[normalizePlayerName(self, playerName)] == true
end

-- Rebuild the local cache of online member from the current guild roster, called whenever the GUILD_ROSTER_UPDATE event fires
local function refreshOnlineMembersCache(self, force)
    local numTotal, numOnline = GetNumGuildMembers()

    if not force and numOnline == self.cachedOnlineGuildMemberCount then
        return
    end

    if self.cachedOnlineGuildMembers then
        wipe(self.cachedOnlineGuildMembers)
        wipe(self.cachedOnlineGuildBankAlts)
    else
        self.cachedOnlineGuildMembers = {}
        self.cachedOnlineGuildBankAlts = {}
    end

    if numOnline == 0 then
        self.cachedOnlineGuildMemberCount = 0

        return
    end

    self.onlineCacheGeneration = (self.onlineCacheGeneration or 0) + 1
    local myGen = self.onlineCacheGeneration
    local scanIndex = 1
    local found = 0
    local function scanBatch()
        if myGen ~= self.onlineCacheGeneration then
            GBCR.Output:Debug("ROSTER", "refreshOnlineMembersCache aborted (stale generation %d)", myGen)

            return
        end

        local startTime = debugprofilestop()
        local iterations = 0

        while scanIndex <= numTotal and found < numOnline do
            local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(scanIndex)
            if name and name ~= "" and isOnline then
                local normName = normalizePlayerName(self, name)
                self.cachedOnlineGuildMembers[normName] = true
                if self.cachedGuildBankAlts and self.cachedGuildBankAlts[normName] then
                    self.cachedOnlineGuildBankAlts[normName] = true
                end
                found = found + 1
            end
            scanIndex = scanIndex + 1
            iterations = iterations + 1

            if shouldYield(startTime, iterations, 50, 200) then
                After(0, scanBatch)

                return
            end
        end

        if myGen ~= self.onlineCacheGeneration then
            return
        end

        self.cachedOnlineGuildMemberCount = numOnline
        GBCR.Output:Debug("ROSTER", "Refreshed online status (%d online, %d bank alts)", numOnline,
                          Globals.Count(self.cachedOnlineGuildBankAlts))
    end

    After(0, scanBatch)
end

-- Helper to determine if a rank can edit officer notes, then it is considered a guild officer (able to wipe everyone's database)
local function isOfficer(self, rankIndex)
    if not rankIndex then
        return false
    end

    return self.cachedGuildRanksThatCanEditOfficerNotes[rankIndex] == true
end

-- Helper to check if we can view and edit officer notes
local function verifyOfficerNotePermissions(self)
    if not self.cachedGuildRanksThatCanEditOfficerNotes then
        self.cachedGuildRanksThatCanEditOfficerNotes = {}
    end

    self.weCanViewOfficerNotes = CanViewOfficerNote()
    self.weCanEditOfficerNotes = isOfficer(self, select(3, getGuildInfo()))
end

-- If this rank can view officer notes, then it is considered the authority on the roster
local function isAuthority(self, rankIndex)
    if not rankIndex then
        return false
    end

    return self.cachedGuildRanksThatCanViewOfficerNotes[rankIndex] == true
end

-- If all ranks can view officer notes, then all players are consider the authority on the roster
-- Also build a local cache of guild members that can edit officer notes (considered guild officer)
local function isAnyoneAuthority(self)
    local result = true

    for i = 1, GuildControlGetNumRanks() do
        local flags = GuildControlGetRankFlags(i)
        local viewOfficerNote = flags[11]
        local editOfficerNote = flags[12]

        self.cachedGuildRanksThatCanViewOfficerNotes[i - 1] = viewOfficerNote
        self.cachedGuildRanksThatCanEditOfficerNotes[i - 1] = editOfficerNote
        self.cachedGuildRankNames[i - 1] = GuildControlGetRankName(i)

        result = result and viewOfficerNote
    end

    self.anyoneIsAuthority = result

    return result
end

-- Helper for fast retrieval of own public and officer notes
local function fetchMyGuildNotes()
    local myGUID = UnitGUID("player")
    if not myGUID then
        return nil, nil
    end

    local numTotal = GetNumGuildMembers()
    if numTotal == 0 then
        return nil, nil
    end

    if GBCR.Events.myGuildRosterIndex and GBCR.Events.myGuildRosterIndex <= numTotal then
        local _, _, _, _, _, _, publicNote, officerNote, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(GBCR.Events
                                                                                                               .myGuildRosterIndex)
        if guid == myGUID then
            return publicNote, officerNote
        end
    end

    for i = 1, numTotal do
        local _, _, _, _, _, _, publicNote, officerNote, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if guid == myGUID then
            GBCR.Events.myGuildRosterIndex = i

            return publicNote, officerNote
        end
    end

    return nil, nil
end

-- Helper to find "gbank" (case insensitive) in a string
local function noteContainsGbank(note)
    return note and note ~= "" and not not string_find(note, "[Gg][Bb][Aa][Nn][Kk]")
end

-- Rebuild guild roster information and request authoritative sources when we're unable to view the officer notes ourselves (as they could be used to define guild banks)
-- Performed after initial login, /reload, guild join, important GUILD_ROSTER_UPDATE events, or when roster is empty (init/wipe)
local function rebuildGuildRosterInfo(self)
    GBCR.Output:Debug("ROSTER", "rebuildGuildRosterInfo called")

    if not GBCR.Database.savedVariables then
        GBCR.Output:Debug("ROSTER", "rebuildGuildRosterInfo: exit because of missing data")

        return
    end

    if self.timerRebuildGuildRosterInfo then
        GBCR.Output:Debug("ROSTER", "rebuildGuildRosterInfo: throttled, rebuild already scheduled")

        return
    end

    self.timerRebuildGuildRosterInfo = NewTimer(Constants.TIMER_INTERVALS.GRM_WAIT, function()
        GBCR.Output:Debug("ROSTER", "Executing throttled rebuildGuildRosterInfo")

        self.isGuildRosterRebuilding = true
        self.guildRosterGeneration = (self.guildRosterGeneration or 0) + 1
        local myGeneration = self.guildRosterGeneration

        self.bufferGuildBankAlts = self.bufferGuildBankAlts or {}
        local guildBankAlts = self.bufferGuildBankAlts
        wipe(guildBankAlts)

        if self.cachedGuildBankAlts then
            wipe(self.cachedGuildBankAlts)
        end
        if self.cachedGuildMembers then
            wipe(self.cachedGuildMembers)
        end
        if self.cachedGuildMemberUidToName then
            wipe(self.cachedGuildMemberUidToName)
        end
        if self.cachedGuildRanksThatCanViewOfficerNotes then
            wipe(self.cachedGuildRanksThatCanViewOfficerNotes)
        end
        if self.cachedOnlineGuildMembers then
            wipe(self.cachedOnlineGuildMembers)
            wipe(self.cachedOnlineGuildBankAlts)
        else
            self.cachedOnlineGuildMembers = {}
            self.cachedOnlineGuildBankAlts = {}
        end

        self.areOfficerNotesUsedToDefineGuildBankAlts = nil

        local anyoneIsAuthority = isAnyoneAuthority(self)
        local weCanViewOfficerNotes = self.weCanViewOfficerNotes
        local player = getNormalizedPlayerName(self)

        local numTotal, numOnline = GetNumGuildMembers()
        local scanIndex = 1
        local position = 1
        local totalScanned = 0

        local overallStart = debugprofilestop()

        local function resumeGuildRosterRebuild()
            self.onlineCacheGeneration = (self.onlineCacheGeneration or 0) + 1

            if self.guildRosterGeneration ~= myGeneration then
                GBCR.Output:Debug("ROSTER", "Aborting stale guild roster rebuild (generation %d vs %d)", myGeneration,
                                  self.guildRosterGeneration)

                return
            end

            local frameStart = debugprofilestop()
            local processedThisFrame = 0

            while scanIndex <= numTotal do
                local name, _, rankIndex, _, _, _, publicNote, officerNote, isOnline, _, class, _, _, _, _, _, guid =
                    GetGuildRosterInfo(scanIndex)

                if name and name ~= "" then
                    local normName = normalizePlayerName(self, name)
                    local playerUid = string_sub(guid, 8)

                    if rankIndex and class then
                        self.cachedGuildMembers[normName] = {
                            isAuthority = isAuthority(self, rankIndex),
                            playerClass = class,
                            playerUid = playerUid,
                            rankIndex = rankIndex
                        }

                        if playerUid then
                            self.cachedGuildMemberUidToName[playerUid] = normName
                        end
                    end

                    if isOnline then
                        self.cachedOnlineGuildMembers[normName] = true
                    end

                    local isGuildBankAlt = false
                    if publicNote and noteContainsGbank(publicNote) then
                        isGuildBankAlt = true
                    elseif weCanViewOfficerNotes and officerNote and noteContainsGbank(officerNote) then
                        isGuildBankAlt = true
                        self.areOfficerNotesUsedToDefineGuildBankAlts = true
                    end

                    if isGuildBankAlt then
                        guildBankAlts[position] = normName
                        position = position + 1
                        self.cachedGuildBankAlts[normName] = true

                        if isOnline then
                            self.cachedOnlineGuildBankAlts[normName] = true
                        end

                        if player == normName then
                            GBCR.Events:RegisterGuildBankAltEvents()
                            GBCR.Options.InitGuildBankAltOptions()
                            verifyOfficerNotePermissions(self)
                        end
                    end
                end

                scanIndex = scanIndex + 1
                processedThisFrame = processedThisFrame + 1
                totalScanned = totalScanned + 1

                if shouldYield(frameStart, processedThisFrame, 50, 200) then
                    After(0, resumeGuildRosterRebuild)

                    return
                end
            end

            self.cachedOnlineGuildMemberCount = numOnline

            if weCanViewOfficerNotes and not self.areOfficerNotesUsedToDefineGuildBankAlts then
                self.areOfficerNotesUsedToDefineGuildBankAlts = false
            end

            GBCR.Output:Debug("ROSTER",
                              "Scanned %d members (%d guild bank alts, %d online, areOfficerNotesUsedToDefineGuildBankAlts=%s) in %.2fms",
                              numTotal, Globals.Count(self.cachedGuildBankAlts), numOnline,
                              tostring(self.areOfficerNotesUsedToDefineGuildBankAlts), debugprofilestop() - overallStart)

            local savedManualAlts = GBCR.Database.savedVariables.roster and GBCR.Database.savedVariables.roster.manualAlts or {}
            if #savedManualAlts > 0 then
                local alreadyInScan = {}
                for i = 1, #guildBankAlts do
                    alreadyInScan[guildBankAlts[i]] = true
                end
                for _, manualName in ipairs(savedManualAlts) do
                    if self.cachedGuildMembers[manualName] and not alreadyInScan[manualName] then
                        guildBankAlts[#guildBankAlts + 1] = manualName
                        self.cachedGuildBankAlts[manualName] = true
                        alreadyInScan[manualName] = true
                        GBCR.Output:Debug("ROSTER", "Manual guild bank alt added to roster: %s", manualName)
                    end
                end
            end

            local selfIsAuthority = self.cachedGuildMembers[player] and self.cachedGuildMembers[player].isAuthority

            if anyoneIsAuthority or selfIsAuthority then
                local newBanksSet = {}
                for i = 1, #guildBankAlts do
                    newBanksSet[guildBankAlts[i]] = true
                end

                local removedAlts = {}
                local existingRosterAlts = GBCR.Database.savedVariables.roster.alts or {}
                local previousRosterCount = #existingRosterAlts
                for _, oldName in ipairs(existingRosterAlts) do
                    if not newBanksSet[oldName] then
                        removedAlts[#removedAlts + 1] = oldName
                    end
                end

                if #removedAlts > 0 and GBCR.Database.savedVariables.alts then
                    for _, name in ipairs(removedAlts) do
                        GBCR.Database.savedVariables.alts[name] = nil
                        GBCR.Output:Info("%s is no longer a guild bank alt. Their local data has been removed.",
                                         Globals.ColorizeText(Constants.COLORS.GOLD, name))
                        GBCR.Output:Debug("ROSTER", "Authority wiped data for removed guild bank alt: %s", name)
                    end
                    GBCR.UI.Inventory:MarkAllDirty()
                end

                GBCR.Database.savedVariables.roster.alts = GBCR.Database.savedVariables.roster.alts or {}

                wipe(GBCR.Database.savedVariables.roster.alts)
                for i = 1, #guildBankAlts do
                    GBCR.Database.savedVariables.roster.alts[i] = guildBankAlts[i]
                end

                GBCR.Database.savedVariables.roster.areOfficerNotesUsed = self.areOfficerNotesUsedToDefineGuildBankAlts == true
                GBCR.Database.savedVariables.roster.manualAlts = GBCR.Database.savedVariables.roster.manualAlts or {}

                if anyoneIsAuthority then
                    -- If all ranks can view officer notes, then everyone is authority and rosters do not need to be synced
                    GBCR.Database.savedVariables.roster.version = nil
                elseif selfIsAuthority then
                    local rosterChanged = (#removedAlts > 0) or (#guildBankAlts > previousRosterCount)

                    -- Only some ranks can view officer notes, and we're an authority
                    -- Only broadcast if something actually changed if officer notes are used to define guild banks
                    if rosterChanged then
                        GBCR.Database.savedVariables.roster.version = GetServerTime()

                        local hasManualAlts = savedManualAlts and #savedManualAlts > 0

                        if self.areOfficerNotesUsedToDefineGuildBankAlts or hasManualAlts then
                            After(0, function()
                                GBCR.Protocol.SendRoster()
                            end)
                            GBCR.Output:Debug("ROSTER", "Authority broadcast: roster changed, pushing to guild immediately")
                        end
                    end
                end

                GBCR.Output:Debug("ROSTER",
                                  "Authority rebuilt roster: %d alts, %d removed (version=%s, areOfficerNotesUsed=%s, anyoneIsAuthority=%s, selfIsAuthority=%s)",
                                  #guildBankAlts, #removedAlts, tostring(GBCR.Database.savedVariables.roster.version),
                                  tostring(GBCR.Database.savedVariables.roster.areOfficerNotesUsed), tostring(anyoneIsAuthority),
                                  tostring(selfIsAuthority))
            else
                -- We're unable to view officer notes and don't know if they're used
                -- Our roster may be incomplete (unless officer notes are irrelevant)
                local officerNotesConfirmedNotUsed = GBCR.Database.savedVariables.roster.areOfficerNotesUsed == false

                local rosterAlts = GBCR.Database.savedVariables.roster.alts or {}
                GBCR.Database.savedVariables.roster.alts = rosterAlts

                -- Verify if there's a change in the roster of guild bank alts
                -- Preserve the existing roster and only add newly detected guild bank alts (preserve existing entries)
                local existingSet = {}
                for i = 1, #rosterAlts do
                    existingSet[rosterAlts[i]] = true
                end

                -- If we identified a new guild bank, add it to our local roster
                local addedCount = 0
                local rosterPos = #rosterAlts + 1
                for i = 1, #guildBankAlts do
                    local normName = guildBankAlts[i]
                    if not existingSet[normName] then
                        rosterAlts[rosterPos] = normName
                        rosterPos = rosterPos + 1
                        existingSet[normName] = true
                        addedCount = addedCount + 1
                    end
                end

                -- Remove guild bank alts whose public notes no longer contain "gbank"
                -- Only do this when we are certain the public scan is complete (no officer notes used)
                if officerNotesConfirmedNotUsed then
                    local scannedSet = {}
                    for i = 1, #guildBankAlts do
                        scannedSet[guildBankAlts[i]] = true
                    end

                    local cleaned = {}
                    local removed = 0
                    for i = 1, #rosterAlts do
                        local name = rosterAlts[i]
                        local inGuild = self.cachedGuildMembers[name] ~= nil
                        local stillBank = scannedSet[name]

                        if stillBank or not inGuild then
                            cleaned[#cleaned + 1] = name
                        else
                            GBCR.Output:Debug("ROSTER",
                                              "Non-authority removing %s from local roster (public notes only, note cleared)",
                                              name)
                            removed = removed + 1
                        end
                    end

                    if removed > 0 then
                        wipe(rosterAlts)
                        for i = 1, #cleaned do
                            rosterAlts[i] = cleaned[i]
                        end
                    end
                end

                -- Ensure our version is set to nil to avoid broadcasting this to others
                -- We do not know if officer notes are used to define guild bank alts
                -- We may have an incomplete roster
                GBCR.Database.savedVariables.roster.version = nil

                GBCR.Output:Debug("ROSTER",
                                  "Non-authority rebuilt local roster: %d alts (added=%d, officerNotesConfirmedNotUsed=%s)",
                                  #rosterAlts, addedCount, tostring(officerNotesConfirmedNotUsed))
            end

            if not GBCR.Database.savedVariables.alts then
                GBCR.Database.savedVariables.alts = {}
            end

            for _, normName in ipairs(GBCR.Database.savedVariables.roster.alts) do
                if normName and not GBCR.Database.savedVariables.alts[normName] then
                    GBCR.Database.savedVariables.alts[normName] = {
                        name = normName,
                        version = 0,
                        money = 0,
                        items = {},
                        ledger = {}
                    }
                    GBCR.Output:Debug("ROSTER", "Added missing stub data for %s", normName)
                end
            end

            wipe(self.cachedAddonUsers)
            for peerName, _ in pairs(GBCR.Protocol.guildMembersFingerprintData) do
                if self.cachedOnlineGuildMembers[peerName] then
                    self.cachedAddonUsers[peerName] = true
                end
            end

            self.guildRosterRefreshNeeded = false
            self.isGuildRosterRebuilding = false

            GBCR.Output:Debug("ROSTER", "Roster operations complete after %.2fms", debugprofilestop() - overallStart)

            GBCR.UI.Inventory.lastKnownOfficerState = nil
            GBCR.UI.Inventory.lastKnownBankAltState = nil
            GBCR.Protocol:PruneStaleProtocolStates()
            GBCR.Protocol:CleanupPendingSync()
            GBCR.Protocol:SendHello()

            self.isGuildRosterReady = true

            self.timerRebuildGuildRosterInfo = NewTimer(GBCR.Constants.TIMER_INTERVALS.REBUILD_ROSTER, function()
                self.timerRebuildGuildRosterInfo = nil
                if self.guildRosterRefreshNeeded then
                    self.guildRosterRefreshNeeded = false
                    rebuildGuildRosterInfo(self)
                end
            end)
        end

        After(0, resumeGuildRosterRebuild)
    end)
end

-- ================================================================================================
-- Fast self-detection of own guild bank status
local function areWeGuildBankAlt(self)
    self.weCanViewOfficerNotes = Globals.CanViewOfficerNote()
    self.weCanEditOfficerNotes = Globals.CanEditOfficerNote()

    local publicNote, officerNote = fetchMyGuildNotes()
    local hasGbank = (publicNote and noteContainsGbank(publicNote)) or
                         (officerNote and self.weCanViewOfficerNotes and noteContainsGbank(officerNote))

    local normName = getNormalizedPlayerName(self)
    local isManuallyDefinedGuildBankAlt = false
    local sv = GBCR.Database.savedVariables
    local savedManualAlts = sv and sv.roster and sv.roster.manualAlts or {}
    if #savedManualAlts > 0 then
        for _, manualName in ipairs(savedManualAlts) do
            if manualName == normName then
                isManuallyDefinedGuildBankAlt = true
            end
        end
    end

    if (hasGbank and hasGbank == self.weAreGuildBankAlt) or
        (isManuallyDefinedGuildBankAlt and isManuallyDefinedGuildBankAlt == self.weAreGuildBankAlt) then
        return
    end

    local weAreGuildBankAlt = hasGbank or isManuallyDefinedGuildBankAlt
    self.weAreGuildBankAlt = weAreGuildBankAlt
    GBCR.Output:Debug("GUILD", "areWeGuildBankAlt: guild bank alt status changed to %s", tostring(weAreGuildBankAlt))

    if weAreGuildBankAlt then
        if self.cachedGuildBankAlts then
            self.cachedGuildBankAlts[normName] = true
        end

        if sv and sv.roster and sv.roster.alts then
            local found = false
            for i = 1, #sv.roster.alts do
                if sv.roster.alts[i] == normName then
                    found = true

                    break
                end
            end

            if not found then
                sv.roster.alts[#sv.roster.alts + 1] = normName
                GBCR.Output:Debug("GUILD", "areWeGuildBankAlt: added %s to roster", normName)
            end
        end

        if sv and sv.alts and not sv.alts[normName] then
            sv.alts[normName] = {name = normName, version = 0, money = 0, items = {}, ledger = {}}
            GBCR.Output:Debug("GUILD", "areWeGuildBankAlt: created stub data for %s", normName)
        end

        GBCR.Events:RegisterGuildBankAltEvents()
        GBCR.Options.InitGuildBankAltOptions()
    elseif self.weCanViewOfficerNotes then
        if self.cachedGuildBankAlts then
            self.cachedGuildBankAlts[normName] = nil
        end

        if sv and sv.roster and sv.roster.alts then
            local alts = sv.roster.alts
            for i = #alts, 1, -1 do
                if alts[i] == normName then
                    table_remove(alts, i)
                    GBCR.Output:Debug("GUILD", "areWeGuildBankAlt: removed %s from roster", normName)

                    break
                end
            end
        end
    else
        GBCR.Output:Debug("GUILD",
                          "areWeGuildBankAlt: weAreGuildBankAlt=false but no officer-note access, deferring to async rebuild")
    end

    GBCR.UI.Inventory.lastKnownOfficerState = nil
    GBCR.UI.Inventory.lastKnownBankAltState = nil
    GBCR.UI:QueueUIRefresh()
end

-- Returns whether or not the provided player exists in the roster of guild bank alts
-- Uses the roster instead of the cache to consider guild bank alts defined in officer notes we may be unable to view
local function isGuildBankAlt(self, playerName)
    if not playerName then
        return false
    end

    local normName = normalizePlayerName(self, playerName)

    if self.cachedGuildBankAlts and next(self.cachedGuildBankAlts) ~= nil then
        return self.cachedGuildBankAlts[normName] == true
    end

    local rosterAlts = GBCR.Database:GetRosterGuildBankAlts()
    if not rosterAlts then
        return false
    end

    GBCR.Output:Debug("ROSTER", "isGuildBankAlt: cache miss for %s, falling back to linear scan (roster rebuild pending?)",
                      normName)

    for i = 1, #rosterAlts do
        if rosterAlts[i] == normName then
            return true
        end
    end

    return false
end

-- ================================================================================================
-- Color player names in messages
local function colorPlayerName(self, name)
    if not name or name == "" then
        return ""
    end

    local cached = self.cachedColoredPlayerName[name]
    if cached then
        return cached
    end

    local normalized = normalizePlayerName(self, name)
    local playerClass = getGuildMemberInfo(self, normalized)
    local result

    if playerClass then
        local classColor = select(4, GetClassColor(playerClass))
        if classColor then
            result = Globals.ColorizeText(classColor, name)
        end
    end

    result = result or Globals.ColorizeText(Constants.COLORS.RED, name)
    self.cachedColoredPlayerName[name] = result

    return result
end

-- ================================================================================================
-- Wipe your guild data via AddOn config "Reset database", /bank reset, /bank wipe, /bank wipeall, GUILD_RANKS_UPDATE event via Guild:Init(guildName)
local function resetGuild(self)
    local guildName = getGuildInfo()
    if not guildName then
        return
    end

    GBCR.UI.Inventory:Close()
    GBCR.Database:ResetGuildDatabase(guildName)
    GBCR.Database.savedVariables = GBCR.Database:Load(guildName)

    self.isGuildRosterReady = nil
    self.lastRosterRebuildTime = nil
    rebuildGuildRosterInfo(self)

    GBCR.UI.Inventory:MarkAllDirty()

    GBCR.UI:QueueUIRefresh()
end

-- Helper to reset tables
local function resetTable(table)
    if table then
        wipe(table)

        return table
    else
        return {}
    end
end

-- Wipe guild-specific data when no longer in a guild
local function clearGuildCaches(self)
    if self.timerRebuildGuildRosterInfo then
        self.timerRebuildGuildRosterInfo:Cancel()
        self.timerRebuildGuildRosterInfo = nil
    end

    self.cachedNormalizedRealmName = nil
    self.cachedPlayerName = nil
    self.retryScheduled = false
    self.cachedOnlineGuildMemberCount = 0
    self.weCanViewOfficerNotes = nil
    self.weCanEditOfficerNotes = nil
    self.anyoneIsAuthority = nil
    self.isGuildRosterRebuilding = nil
    self.guildRosterGeneration = 0
    self.guildRosterRefreshNeeded = nil
    self.isGuildRosterReady = nil

    self.cachedNormalizedPlayerName = resetTable(self.cachedNormalizedPlayerName)
    self.cachedGuildMemberUidToName = resetTable(self.cachedGuildMemberUidToName)
    self.cachedGuildMembers = resetTable(self.cachedGuildMembers)
    self.cachedOnlineGuildMembers = resetTable(self.cachedOnlineGuildMembers)
    self.cachedOnlineGuildBankAlts = resetTable(self.cachedOnlineGuildBankAlts)
    self.cachedGuildBankAlts = resetTable(self.cachedGuildBankAlts)
    self.cachedGuildRanksThatCanViewOfficerNotes = resetTable(self.cachedGuildRanksThatCanViewOfficerNotes)
    self.cachedGuildRanksThatCanEditOfficerNotes = resetTable(self.cachedGuildRanksThatCanEditOfficerNotes)
    self.cachedGuildRankNames = resetTable(self.cachedGuildRankNames)
    self.cachedAddonUsers = resetTable(self.cachedAddonUsers)
    self.cachedColoredPlayerName = resetTable(self.cachedColoredPlayerName)
end

-- Resets if the data does not already exist, only runs on GUILD_RANKS_UPDATE
local function init(self, guildName)
    GBCR.Output:Debug("DATABASE", "Guild:Init called for %s", tostring(guildName))

    clearGuildCaches(self)

    local savedRoster = GBCR.Database.savedVariables and GBCR.Database.savedVariables.roster
    if savedRoster and savedRoster.areOfficerNotesUsed ~= nil then
        self.areOfficerNotesUsedToDefineGuildBankAlts = savedRoster.areOfficerNotesUsed
    end

    if not guildName then
        return false
    end

    if GBCR.Database.savedVariables and GBCR.Database.savedVariables.guildName == guildName then
        return false
    end

    GBCR.Database.savedVariables = GBCR.Database:Load(guildName)
    if GBCR.Database.savedVariables then
        rebuildGuildRosterInfo(self)

        return true
    end

    resetGuild(self)

    return true
end

-- ================================================================================================
-- Export functions for other modules
Guild.NormalizePlayerName = normalizePlayerName
Guild.GetNormalizedPlayerName = getNormalizedPlayerName

Guild.GetGuildInfo = getGuildInfo
Guild.FindGuildMemberByUid = findGuildMemberByUid
Guild.DetermineUidForGuildMemberName = determineUidForGuildMemberName
Guild.GetGuildMemberInfo = getGuildMemberInfo
Guild.IsPlayerOnlineMember = isPlayerOnlineGuildMember
Guild.IsPlayerOnlineGuildBankAlt = isPlayerOnlineGuildBankAlt
Guild.RefreshOnlineMembersCache = refreshOnlineMembersCache
Guild.IsAuthority = isAuthority
Guild.IsAnyoneAuthority = isAnyoneAuthority
Guild.RebuildGuildRosterInfo = rebuildGuildRosterInfo

Guild.AreWeGuildBankAlt = areWeGuildBankAlt
Guild.IsGuildBankAlt = isGuildBankAlt

Guild.ColorPlayerName = colorPlayerName

Guild.ResetGuild = resetGuild
Guild.ClearGuildCaches = clearGuildCaches
Guild.Init = init
