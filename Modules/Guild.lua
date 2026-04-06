local addonName, GBCR = ...

GBCR.Guild = {}
local Guild = GBCR.Guild

local Globals = GBCR.Globals
local debugprofilestop = Globals.debugprofilestop
local ipairs = Globals.ipairs
local select = Globals.select
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
local IsInGuild = Globals.IsInGuild
local NewTicker = Globals.NewTicker
local UnitName = Globals.UnitName

-- Returns the guild info (guildName, guildRankName, guildRankIndex, realm) for the current player if they are in a guild
-- Returns guildName, guildRankName, guildRankIndex, realm from GetGuildInfo("player")
local function getGuildInfo(self)
    return IsInGuild("player") and GetGuildInfo("player") or nil
end

-- Helper to cache the normalized realm name
local function getCachedNormalizedRealm(self)
    if not self.cachedNormalizedRealm then
        self.cachedNormalizedRealm = GetNormalizedRealmName()
    end

    return self.cachedNormalizedRealm
end

-- Returns the normalized name (including the realm name) of a given name for database purposes
-- Removes the realm name for players on the same realm if the purpose is to whisper or mail that player (noRealm=true)
local function normalizeName(self, name, noRealm)
	if not name then
        return nil
    end

	-- Check cache first (only for standard requests without noRealm flag)
    if not noRealm and self.normalizedNameCache[name] then
        return self.normalizedNameCache[name]
    end

    -- Trim whitespace
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    -- Handle "Unknown" edge case
    if trimmed:lower() == "unknown" then
        return "Unknown"
    end

    -- Split name from realm
    local playerName, playerRealm = trimmed:match("^(.+)%-(.+)$")
    local currentRealm = getCachedNormalizedRealm(self)

    -- If no realm provided, assume current realm
    if not playerRealm then
        playerRealm = currentRealm
        playerName = trimmed
    end

    -- For communication (whisper/mail), strip realm only if same exact realm
    if noRealm then
        if playerRealm == currentRealm then
            return playerName
        else
            -- Connected realm or different realm, keep suffix
            return playerName .. "-" .. playerRealm
        end
    end

    -- For database storage, always return with realm suffix and save to cache
	local result = playerName .. "-" .. playerRealm
    self.normalizedNameCache[name] = result

    return result
end

-- Returns the normalized name (including the realm name) of the current player
local function getNormalizedPlayer(self)
    -- Return cached player if available
    if self.player then
        return self.player
    end

    -- Try to get player info immediately
    local name, realm = UnitName("player"), getCachedNormalizedRealm(self)
    if name and realm and name ~= "Unknown" then
        self.player = name .. "-" .. realm

        return self.player
    end

    -- If player info not yet available, set up background retry (happens once)
    if not self._playerRetryScheduled then
        self._playerRetryScheduled = true

        local retryCount = 0
        local maxRetries = 20
        local timer

        timer = NewTicker(0, function()
            local retryName, retryRealm = UnitName("player"), getCachedNormalizedRealm(self)
            retryCount = retryCount + 1

            if retryName and retryRealm and retryName ~= "Unknown" then
                Guild.player = retryName .. "-" .. retryRealm
                timer:Cancel()
                Guild._playerRetryScheduled = false
            elseif retryCount >= maxRetries then
                timer:Cancel()
                Guild._playerRetryScheduled = false
            end
        end)
    end

    -- Always return a value (cached or fallback)
    return self.player or "Unknown-Unknown"
end

---

-- Retrieve the list of guild bank alts from GBCR.Database.savedVariables.roster.alts
-- This returns an array (ordered iteration)
-- for i = 1, #list do print(list[i]) end
local function getRosterGuildBankAlts(self)
	if not GBCR.Database.savedVariables then
		return nil
	end

	local roster = GBCR.Database.savedVariables.roster
    if roster and roster.alts and #roster.alts > 0 then
        return roster.alts
    end

	return nil
end

-- Request online members to share their guild bank alt data if we're missing it
local function requestMissingGuildBankAltData(self)
	local rosterAlts = getRosterGuildBankAlts(self)
	if not rosterAlts or #rosterAlts == 0 then
		return
	end

	local missing = {}
	local missingPosition = 1

	GBCR.Output:Debug("SYNC", "RequestMissingGuildBankAltData: starting check of %d guild bank alts on the roster", #rosterAlts)

	local altsSavedVars = GBCR.Database.savedVariables.alts
	local protocol = GBCR.Protocol
	local output = GBCR.Output

	for i = 1, #rosterAlts do
        local guildBankAltName = rosterAlts[i]
		local norm = normalizeName(self, guildBankAltName) or guildBankAltName
		local localAlt = altsSavedVars and norm and altsSavedVars[norm]
		local hasEntry = localAlt ~= nil
		local hasContent = hasEntry and protocol:HasAltContent(localAlt, norm)
		local isSelf = norm == getNormalizedPlayer(self)

		output:Debug("SYNC", "RequestMissingGuildBankAltData: checking %s (hasEntry=%s, hasContent=%s, self=%s)", tostring(norm), tostring(hasEntry), tostring(hasContent), tostring(isSelf))

		if (not hasEntry or not hasContent) and not isSelf then
			missing[missingPosition] = norm
            missingPosition = missingPosition + 1
		end
	end

    if #missing == 0 then
        GBCR.Output:Debug("SYNC", "RequestMissingGuildBankAltData: no missing data")
        return
    end

	GBCR.Output:Info("Requesting missing data for %d guild bank alts (have data for %d/%d).", #missing, #rosterAlts - #missing, #rosterAlts)

	for _, norm in ipairs(missing) do
		protocol:QueryForGuildBankAltData(nil, norm)
	end
end

-- Returns whether or not the provided player exists in the roster of guild bank alts
-- Uses the roster instead of the cache to consider guild bank alts defined in officer notes we may be unable to view
local function isGuildBankAlt(self, playerName)
	if not playerName then
		return false
	end

    local rosterAlts = getRosterGuildBankAlts(self)
	if not rosterAlts then
		return false
	end

	local normName = normalizeName(self, playerName) or playerName

    for i = 1, #rosterAlts do
        if rosterAlts[i] == normName then
            return true
        end
    end

    return false
end

---

-- Find the name of a guild member by their uid which is used in addon communication to minimize the payload
local function findGuildMemberByUid(self, uid)
    if not uid then
        return nil, nil
    end

    local playerName = self.uidToNameCache[uid]
    if playerName then
        return playerName, self.guildMembersCache[playerName]
    end

    return nil, nil
end

-- Return the player's class, and whether or not they are the are able to view officer notes (consider an authority), based on the cached guild member data
local function getGuildMemberInfo(self, playerName)
	if not playerName then
		return false
	end

	local guildMemberFromCache = self.guildMembersCache[normalizeName(self, playerName) or playerName]
	local playerClass = guildMemberFromCache and guildMemberFromCache.playerClass or nil
	local isAuthority = guildMemberFromCache and guildMemberFromCache.isAuthority or false

	return playerClass, isAuthority
end

-- Check if a player is currently online in the guild
local function isPlayerOnlineMember(self, playerName)
	if not playerName then
		return false
	end

	return self.onlineMembers[normalizeName(self, playerName) or playerName] == true
end

-- TODO: CURRENTLY UNUSED ** 
-- Get list of all online members (for broadcasts)
local function getOnlineMemberList(self)
    return self.onlineMembers
end

-- TODO: CURRENTLY UNUSED ** 
-- Check if a player is currently online in the guild and a guild bank alt
local function isPlayerOnlineGuildBankAlt(self, playerName)
	if not playerName then
		return false
	end

	return self.onlineMembersThatAreGuildBankAlts[normalizeName(self, playerName) or playerName] == true
end

-- Get list of all online guild bank alts
local function getOnlineGuildBankAlts(self)
    return self.onlineMembersThatAreGuildBankAlts
end

local function getOnlineMembersCount(self)
	return self.onlineMembersCount
end

-- Called whenever the GUILD_ROSTER_UPDATE event fires (server pushes updates)
-- This rebuild the local cache of online member from the current guild roster
local function refreshOnlineMembersCache(self, force)
    local numTotal, numOnline = GetNumGuildMembers()
	local startTime = debugprofilestop()

    -- Skip if online count unchanged
    if not force and numOnline == getOnlineMembersCount(self) then
        return
    end

	-- Empty roster edge case (briefly during loading)
    if numOnline == 0 then
        if getOnlineMembersCount(self) ~= 0 then
			if self.onlineMembers then
				wipe(self.onlineMembers)
				wipe(self.onlineMembersThatAreGuildBankAlts)
			else
				self.onlineMembers = {}
				self.onlineMembersThatAreGuildBankAlts = {}
			end
            self.onlineMembersCount = 0
        end

        return
    end

    -- Rebuild cache of online members and online guild bank alts
	-- We only need to scan until we've found all online members (they always appear first)
    if self.onlineMembers then
		wipe(self.onlineMembers)
		wipe(self.onlineMembersThatAreGuildBankAlts)
	else
		self.onlineMembers = {}
		self.onlineMembersThatAreGuildBankAlts = {}
	end

    for i = 1, math.min(numTotal, numOnline) do
        local name = GetGuildRosterInfo(i)

        if name and name ~= "" then
			local normName = normalizeName(self, name) or name

            self.onlineMembers[normName] = true
			if self.banksCache and self.banksCache[normName] then
				self.onlineMembersThatAreGuildBankAlts[normName] = true
			end
        end
    end

	self.onlineMembersCount = numOnline

    GBCR.Output:Debug("ROSTER", "Refreshed online status (%d online, %d bank alts) in %.2fms", numOnline, Globals:Count(self.onlineMembersThatAreGuildBankAlts), debugprofilestop() - startTime)
end

-- Helper to determine if a rank can edit officer notes, then it is considered a guild officer (able to wipe everyone's database)
local function isOfficer(self, rankIndex)
	if not rankIndex then
		return false
	end

	return self.guildRankOfficerCache[rankIndex] == true
end

-- Helper to check if we can view officer notes
local function verifyOfficerNotePermissions(self)
	if not self.guildRankOfficerCache then
		self.guildRankOfficerCache = {}
	end

	self.canWeViewOfficerNotes = CanViewOfficerNote()
	self.canWeEditOfficerNotes = isOfficer(self, select(3, getGuildInfo(self)))
end

-- If we can view officer notes, we are certain of the guild bank alt roster
local function canWeViewOfficerNotes(self)
	return self.canWeViewOfficerNotes
end

-- If this rank can view officer notes, then it is considered the authority on the roster
local function isAuthority(self, rankIndex)
	if not rankIndex then
		return false
	end

	return self.guildRankAuthorityCache[rankIndex] == true
end

-- If all ranks can view officer notes, then all players are consider the authority on the roster
-- Also build a local cache of guild members that can edit officer notes (considered guild officer)
local function isAnyoneAuthority(self)
    local isAnyoneAuthority = true

    for i = 1, GuildControlGetNumRanks() do
        local flags = GuildControlGetRankFlags(i)
        local viewOfficerNote = flags[11]
        local editOfficerNote = flags[12]

        self.guildRankAuthorityCache[i - 1] = viewOfficerNote
        self.guildRankOfficerCache[i - 1] = editOfficerNote

        isAnyoneAuthority = isAnyoneAuthority and viewOfficerNote
    end

    self.isAnyoneAuthority = isAnyoneAuthority

    return isAnyoneAuthority
end

-- Rebuild roster of guild bank alts based on guild notes we can view
-- Officer notes may be used for this purpose and we may be unable to view those
-- Request authoritative sources when unable to view the officer notes ourselves
-- Performed after initial login, /reload, guild join, important GUILD_ROSTER_UPDATE events, or when roster is empty (init/wipe)
local function rebuildGuildBankAltsRoster(self)
    GBCR.Output:Debug("ROSTER", "rebuildGuildBankAltsRoster called")

	if not GBCR.Database.savedVariables then
		return
	end

	if self.rebuildTimer then
        self.rebuildTimer:Cancel()
    end

    self.rebuildTimer = After(GBCR.Constants.TIMER_INTERVALS.REBUILD_ROSTER, function()
        GBCR.Output:Debug("ROSTER", "Executing throttled rebuildGuildBankAltsRoster")

		self.guildBankAltsBuffer = self.guildBankAltsBuffer or {}
        local guildBankAlts = self.guildBankAltsBuffer
        wipe(guildBankAlts)
        local position = 1

        local startTime = debugprofilestop()

        if self.banksCache then
			wipe(self.banksCache)
		end
        if self.guildMembersCache then
			wipe(self.guildMembersCache)
		end
        if self.uidToNameCache then
			wipe(self.uidToNameCache)
		end
        if self.guildRankAuthorityCache then
			wipe(self.guildRankAuthorityCache)
		end

        self.areOfficerNotesUsedToDefineGuildBankAlts = nil

        local isAnyoneAuthority = isAnyoneAuthority(self)
        local canWeViewOfficerNotes = canWeViewOfficerNotes(self)
        local player = getNormalizedPlayer(self)

		local function noteContainsGbank(note)
			return note and note ~= "" and note:find("[Gg][Bb][Aa][Nn][Kk]")
		end

		-- Scan the guild roster
		local numTotal = GetNumGuildMembers()

		for i = 1, numTotal do
			local name, _, rankIndex, _, _, _, publicNote, officerNote, _, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)

            if name and name ~= "" then
                local normName = self:NormalizeName(name) or name
                local playerUid = guid:sub(8)

                if rankIndex and class then
                    self.guildMembersCache[normName] = { isAuthority = self:IsAuthority(rankIndex), playerClass = class, playerUid = playerUid }
                    if playerUid then
                        self.uidToNameCache[playerUid] = normName
                    end
                end

                local isGuildBankAlt = false
                if publicNote and noteContainsGbank(publicNote) then
                    isGuildBankAlt = true
                elseif canWeViewOfficerNotes and officerNote and noteContainsGbank(officerNote) then
                    isGuildBankAlt = true
                    self.areOfficerNotesUsedToDefineGuildBankAlts = true
                end

				if isGuildBankAlt then
					guildBankAlts[position] = normName
                    position = position + 1
					self.banksCache[normName] = true

					-- Register additional events and enable additional configuration options if we're a guild bank alt
					if player == normName then
						GBCR.Events:RegisterGuildBankAltEvents()
						GBCR.Options:InitGuildBankAltOptions()
						verifyOfficerNotePermissions(self)
					end
				end
			end
		end

		if canWeViewOfficerNotes and not self.areOfficerNotesUsedToDefineGuildBankAlts then
			self.areOfficerNotesUsedToDefineGuildBankAlts = false
		end

		GBCR.Output:Debug("ROSTER", "Scanned %d members (%d guild bank alts, areOfficerNotesUsedToDefineGuildBankAlts=%s) in %.2fms", numTotal, Globals:Count(self.banksCache), tostring(self.areOfficerNotesUsedToDefineGuildBankAlts), debugprofilestop() - startTime)

		-- Determine what to do with the roster (copy/merge/broadcast)
		local selfIsAuthority = self.guildMembersCache[player] and self.guildMembersCache[player].isAuthority
		if isAnyoneAuthority or selfIsAuthority then
			-- Our local roster is always complete
			GBCR.Database.savedVariables.roster.alts = GBCR.Database.savedVariables.roster.alts or {}
            wipe(GBCR.Database.savedVariables.roster.alts)
            for i = 1, #guildBankAlts do
                GBCR.Database.savedVariables.roster.alts[i] = guildBankAlts[i]
            end
			-- Determine if we need to broadcast our roster
			if isAnyoneAuthority then
				-- If all ranks can view officer notes, then everyone is authority and rosters do not need to be synced
				GBCR.Database.savedVariables.roster.version = nil
			elseif selfIsAuthority then
				-- Only some ranks can view officer notes, and we're an authority
				GBCR.Database.savedVariables.roster.version = GetServerTime()
				-- Determine if officer notes are relevant (does at least one officer note contain 'gbank'?)
				if self.areOfficerNotesUsedToDefineGuildBankAlts then
					-- Officer notes are used to define guild bank alts
					-- Broadcast our roster fingerprint as an authority to the guild to allow pull requests via whisper for non-authorities
					-- The hash is to identify if content changed

					-- TODO:
					-- GBCR.Output:Debug("ROSTER", "Broadcasting fingerprint of our roster as authority")
					-- gbc-roster-share-heartbeat to GUILD: 
					--   senderIsAuthority: true, 
					--   self.areOfficerNotesUsedToDefineGuildBankAlts: true,
					--   version: unix timestamp

					-- when player receives the heartbeat, and if they are not an authority:
					--   gbc-roster-share-request WHISPER to sender that is an authority: send me your roster
					-- 
					-- when an authority receives gbc-roster-share-request WHISPER:
					--   gbc-roster-share WHISPER to requester
					--     roster alts: table
					--     version:
				end
			end
			GBCR.Output:Debug("ROSTER", "Rebuilt guild bank alt roster from guild notes with %d guild bank alts (version=%s, isAnyoneAuthority=%s, selfIsAuthority=%s)", #guildBankAlts, tostring(GBCR.Database.savedVariables.roster.version), tostring(isAnyoneAuthority), tostring(selfIsAuthority))
		else
			-- We're unable to view officer notes
			-- Our roster may be incomplete (it is complete if officer notes are irrelevant)
			-- A possible incoming roster broadcast will make it clear if they are relevant
			-- We whisper the sender to request their roster when we see the gbc-roster-share-heartbeat
			-- If we never see gbc-roster-share-heartbeat then the officer notes are irrelevant

			-- Verify if there's a change in the roster of guild bank alts
			-- Preserve the existing roster and only add newly detected guild bank alts (preserve existing entries)
			local rosterAlts = GBCR.Database.savedVariables.roster.alts or {}
			local existingSet = {}
			local addedCount = 0
			local rosterPosition = #rosterAlts + 1

			for i = 1, #rosterAlts do
				existingSet[rosterAlts[i]] = true
			end

			for i = 1, #guildBankAlts do
				local normName = guildBankAlts[i]

				if not existingSet[normName] then
					rosterAlts[rosterPosition] = normName
                    rosterPosition = rosterPosition + 1
					existingSet[normName] = true
					addedCount = addedCount + 1
				end
			end

			-- If we identified a new guild bank, add it to our local roster
			local hasNewEntries = addedCount > 0
			GBCR.Database.savedVariables.roster.alts = rosterAlts

			if hasNewEntries then
				-- Ensure our version is set to nil to avoid broadcasting this to others
				-- We do not know if officer notes are used to define guild bank alts
				-- We may have an incomplete roster
				GBCR.Database.savedVariables.roster.version = nil

				-- -- Ask the guild bank alt sync leader for their roster
				-- local _, leader = self:CheckIfWeAreGuildBankAltSyncLeader()
				-- -- TODO:
				-- GBCR.Output:Debug("ROSTER", "Rebuilt (possibly incomplete) guild bank alt roster from guild notes with %d guild bank alts - requesting latest roster from authority", #GBCR.Database.savedVariables.roster.alts)
				-- --   gbc-roster-share-request WHISPER to leader: send me your roster
				-- GBCR.Output:Debug("ROSTER", "Requested %s for an updated roster", leader)
			end
		end

		-- Ensure local alt data exists for all roster guild bank alts
		if not GBCR.Database.savedVariables.alts then
			GBCR.Database.savedVariables.alts = {}
		end

		for _, normName in ipairs(GBCR.Database.savedVariables.roster.alts) do
			if normName and not GBCR.Database.savedVariables.alts[normName] then
				GBCR.Database.savedVariables.alts[normName] = { name = normName, version = 0, money = 0, items = {}, ledger = {} }
				GBCR.Output:Debug("ROSTER", "Added missing guild bank alt stub data for %s", normName)
			end
		end

		-- Update lookup tables and variables after the roster rebuild
		self.rosterRefreshNeeded = false
		self.rebuildTimer = nil
		GBCR.Output:Debug("ROSTER", "Done with roster operations after %.2fms", debugprofilestop() - startTime)

		-- Update online status
		refreshOnlineMembersCache(self, true)

		-- Notify others that we're ready
		GBCR.Protocol:Hello()
    end)
end

---

-- Color player names in messages
local function colorPlayerName(self, name)
	if not name or name == "" then
		return ""
	end

	local normalized = normalizeName(self, name) or name
	local playerClass = getGuildMemberInfo(self, normalized)

	if playerClass then
		local classColor = select(4, GetClassColor(playerClass))

		if classColor then
			return Globals:Colorize(classColor, name)
		end
	end

	return Globals:Colorize(GBCR.Constants.COLORS.RED, name)
end

-- Wipe your guild data via AddOn config "Reset database", /bank reset, /bank wipe, /bank wipeall, GUILD_RANKS_UPDATE event via Guild:Init(guildName)
local function resetGuild(self)
	local guildName = getGuildInfo(self)
	if not guildName then
		return
	end

    GBCR.UI.Inventory:Close()
    GBCR.Database:ResetGuildDatabase(guildName)

    GBCR.Database.savedVariables = GBCR.Database:Load(guildName)

	self.lastRosterRebuildTime = nil
	rebuildGuildBankAltsRoster(self)

	GBCR.Search:MarkAllDirty()

	GBCR.UI:QueueUIRefresh()
end

-- Wipe guild-specific data when no longer in a guild
local function clearGuildCaches(self)
    wipe(self.onlineMembers)
    wipe(self.onlineMembersThatAreGuildBankAlts)
    wipe(self.banksCache)
    wipe(self.guildMembersCache)
    wipe(self.uidToNameCache)
    wipe(self.guildRankAuthorityCache)
    wipe(self.guildRankOfficerCache)

    self.onlineMembersCount = 0
    self.rosterRefreshNeeded = nil
    self.canWeViewOfficerNotes = nil
	self.isAnyoneAuthority = nil
	self.canWeEditOfficerNotes = nil
end

-- Resets if the data does not already exist, only runs on GUILD_RANKS_UPDATE
local function init(self, guildName)
	self.player = nil

    self.normalizedNameCache = {}
    self.uidToNameCache = {}
    self.onlineMembers = {}
    self.onlineMembersThatAreGuildBankAlts = {}
    self.banksCache = {}
    self.guildMembersCache = {}
    self.guildRankAuthorityCache = {}
    self.guildRankOfficerCache = {}

    self.onlineMembersCount = 0
	self.rosterRefreshNeeded = nil
	self.canWeViewOfficerNotes = nil
	self.isAnyoneAuthority = nil
	self.canWeEditOfficerNotes = nil

	if not guildName then
		return false
	end

	if GBCR.Database.savedVariables and GBCR.Database.savedVariables.guildName == guildName then
		return false
	end

	GBCR.Database.savedVariables = GBCR.Database:Load(guildName)
	if GBCR.Database.savedVariables then
		rebuildGuildBankAltsRoster(self)

		return true
	end

	resetGuild(self)

	return true
end

-- Export functions for other modules
Guild.GetGuildInfo = getGuildInfo
Guild.NormalizeName = normalizeName
Guild.GetNormalizedPlayer = getNormalizedPlayer

Guild.GetRosterGuildBankAlts = getRosterGuildBankAlts
Guild.RequestMissingGuildBankAltData = requestMissingGuildBankAltData
Guild.IsGuildBankAlt = isGuildBankAlt

Guild.FindGuildMemberByUid = findGuildMemberByUid
Guild.GetGuildMemberInfo = getGuildMemberInfo
Guild.IsPlayerOnlineMember = isPlayerOnlineMember
-- Guild.GetOnlineMemberList = getOnlineMemberList
-- Guild.IsPlayerOnlineGuildBankAlt = isPlayerOnlineGuildBankAlt
Guild.GetOnlineGuildBankAlts = getOnlineGuildBankAlts
Guild.GetOnlineMembersCount = getOnlineMembersCount
Guild.RefreshOnlineMembersCache = refreshOnlineMembersCache
Guild.CanWeViewOfficerNotes = canWeViewOfficerNotes
Guild.IsAuthority = isAuthority
Guild.IsAnyoneAuthority = isAnyoneAuthority
Guild.RebuildGuildBankAltsRoster = rebuildGuildBankAltsRoster

Guild.ColorPlayerName = colorPlayerName
Guild.ResetGuild = resetGuild
Guild.ClearGuildCaches = clearGuildCaches
Guild.Init = init