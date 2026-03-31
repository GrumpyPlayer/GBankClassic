local addonName, GBCR = ...

GBCR.Guild = {}
local Guild = GBCR.Guild

local Globals = GBCR.Globals
local wipe = Globals.wipe
local debugprofilestop = Globals.debugprofilestop
local GetNormalizedRealmName = Globals.GetNormalizedRealmName
local UnitName = Globals.UnitName
local NewTicker = Globals.NewTicker
local IsInGuild = Globals.IsInGuild
local GetGuildInfo = Globals.GetGuildInfo
local GetNumGuildMembers = Globals.GetNumGuildMembers
local GetGuildRosterInfo = Globals.GetGuildRosterInfo
local GetServerTime = Globals.GetServerTime
local CanViewOfficerNote = Globals.CanViewOfficerNote
local GuildControlGetNumRanks = Globals.GuildControlGetNumRanks
local GuildControlGetRankFlags = Globals.GuildControlGetRankFlags

-- Resets if the data does not already exist, only runs on GUILD_RANKS_UPDATE
function Guild:Init(name)
	if not name then
		return false
	end

	if GBCR.Database.savedVariables and GBCR.Database.savedVariables.name == name then
		return false
	end

	self.player = nil
	self.banksCache = {}
	self.guildMembersCache = {}
	self.guildRankAuthorityCache = {}
	self.guildRankOfficerCache = {}
	self.isAnyoneAuthority = false
	self.canWeEditOfficerNotes = false
	self.canWeViewOfficerNotes = false

    self.requestCount = 0
    self.hasRequested = false
	self.rosterRefreshNeeded = false

	GBCR.Database.savedVariables = GBCR.Database:Load(name)
	if GBCR.Database.savedVariables then
		self:RebuildGuildBankAltsRoster()

		return true
	end

	self:Reset(name)

	return true
end

-- AddOn config "Reset database", /bank reset, /bank wipe, /bank wipeall, GUILD_RANKS_UPDATE event via Guild:Init(name)
function Guild:Reset(name)
	if not name then
		return
	end

    GBCR.UI.Inventory:Close()
    GBCR.Database:Reset(name)
	self.lastRosterRebuildTime = nil
    GBCR.Database.savedVariables = GBCR.Database:Load(name)
	self:RebuildGuildBankAltsRoster()
	GBCR.UI:QueueUIRefresh()
end

-- Returns the normalized name (including the realm name) of a given name for database purposes
-- Remove the realm name for players on the same realm if the purpose is to whisper or mail that player (noRealm=true)
function Guild:NormalizeName(name, noRealm)
	if not name or type(name) ~= "string" then
        return nil
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
    local currentRealm = self:GetCachedNormalizedRealm()

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

    -- For database storage, always return with realm suffix
    return playerName .. "-" .. playerRealm
end

-- Returns the normalized name (including the realm name) of the current player
function Guild:GetNormalizedPlayer()
    -- Return cached player if available
    if self.player then
        return self.player
    end

    -- Try to get player info immediately
    local name, realm = UnitName("player"), self:GetCachedNormalizedRealm()
    if name and realm then
        self.player = name .. "-" .. realm

        return self.player
    end

    -- If player info not yet available, set up background retry (happens once)
    if not self._playerRetryScheduled then
        self._playerRetryScheduled = true
        local retryCount = 0
        local maxRetries = 20
        local timer
        timer = NewTicker(0.5, function()
            retryCount = retryCount + 1
            local name, realm = UnitName("player"), Guild:GetCachedNormalizedRealm()
            if name and realm then
                Guild.player = name .. "-" .. realm
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

-- Cache the normalized realm name
function Guild:GetCachedNormalizedRealm()
    if not self.cachedNormalizedRealm then
        self.cachedNormalizedRealm = GetNormalizedRealmName()
    end

    return self.cachedNormalizedRealm
end

-- Returns the guild info for the current player if they are in a guild
-- guildName, guildRankName, guildRankIndex, realm = GetGuildInfo(unit)
function Guild:GetGuildName()
    return IsInGuild("player") and GetGuildInfo("player") or nil
end

-- Return the player's class, and whether or not they are the are able to view officer notes (consider an authority), based on the cached guild member data
function Guild:GetGuildMemberInfo(player)
	if not player then
		return false
	end

	local guildMemberFromCache = self.guildMembersCache[self:NormalizeName(player) or player]
	local playerClass = guildMemberFromCache and guildMemberFromCache.playerClass or nil
	local isAuthority = guildMemberFromCache and guildMemberFromCache.isAuthority or false

	return playerClass, isAuthority
end

function Guild:FindGuildMemberByUid(uid)
	if not uid then
		return nil, nil
	end

	for playerName, playerData in pairs(self.guildMembersCache) do
		if playerData.playerUid == uid then
			return playerName, playerData
		end
	end

	return nil, nil
end

-- Return a cached list of guild bank alts or rebuild the cache
-- This returns a hash table or set for fast O(1) lookups
-- for v in pairs(list) do print(v) end
function Guild:GetCachedGuildBankAlts()
	-- Return cached banks list if available
	if next(self.banksCache) then
		return self.banksCache
	end

	-- Build banks list
	self.banksCache = Guild:RebuildGuildBankAltsRoster()

	return self.banksCache
end

-- If all ranks can view officer notes, then all players are consider the authority on the roster
-- Also build a local cache of guild members that can edit officer notes (considered guild officer)
function Guild:IsAnyoneAuthority()
	local isAnyoneAuthority = true
	for i = 1, GuildControlGetNumRanks() do
		local viewOfficerNote = GuildControlGetRankFlags(i)[11]
		local editOfficerNote = GuildControlGetRankFlags(i)[12]
		self.guildRankAuthorityCache[i - 1] = viewOfficerNote
		self.guildRankOfficerCache[i - 1] = editOfficerNote
		isAnyoneAuthority = isAnyoneAuthority and viewOfficerNote
	end
	self.isAnyoneAuthority = isAnyoneAuthority

	return isAnyoneAuthority
end

-- If this rank can view officer notes, then it is considered the authority on the roster
function Guild:IsAuthority(rankIndex)
	if not rankIndex then
		return false
	end

	return Guild.guildRankAuthorityCache[rankIndex] == true
end

-- If this rank can edit officer notes, then it is considered a guild officer (able to wipe everyone's database)
function Guild:IsOfficer(rankIndex)
	if not rankIndex then
		return false
	end

	return self.guildRankOfficerCache[rankIndex] == true
end

-- Check if we can view officer notes
function Guild:VerifyOfficerNotePermissions()
	if not self.guildRankOfficerCache then
		self.guildRankOfficerCache = {}
	end
	self.canWeViewOfficerNotes = CanViewOfficerNote()
	self.canWeEditOfficerNotes = self:IsOfficer(select(3, GetGuildInfo("player")))
end

-- If we can view officer notes, we are certain of the guild bank alt roster
function Guild:CanWeViewOfficerNotes()
	return self.canWeViewOfficerNotes
end

-- Rebuild roster of guild bank alts based on guild notes we can view
-- Officer notes may be used for this purpose and we may be unable to view those
-- Request authoritative sources when unable to view the officer notes ourselves
-- Performed after initial login, /reload, guild join, important GUILD_ROSTER_UPDATE events, or when roster is empty (init/wipe)
function Guild:RebuildGuildBankAltsRoster()
	if not GBCR.Database.savedVariables then
		return
	end

	-- TODO
	-- local time = GetServerTime()
	-- if self.lastRosterRebuildTime == nil or time - self.lastRosterRebuildTime > 30 then
	-- 	self.lastRosterRebuildTime = time
	-- else
	-- 	GBCR.Output:Debug("ROSTER", "Skipping excessive roster rebuild (last rebuild was %.2f seconds ago)", time - self.lastRosterRebuildTime)

	-- 	return
	-- end

	local guildBankAlts = {}
	local startTime = debugprofilestop()
	if self.banksCache then wipe(self.banksCache) end
	if self.guildMembersCache then wipe(self.guildMembersCache) end
	if self.guildRankAuthorityCache then wipe(self.guildRankAuthorityCache) end
	self.areOfficerNotesUsedToDefineGuildBankAlts = nil
	local isAnyoneAuthority = self:IsAnyoneAuthority()
	local canWeViewOfficerNotes = self:CanWeViewOfficerNotes()
	local player = self:GetNormalizedPlayer()

	local function noteContainsGbank(note)
		return note and note ~= "" and note:lower():find("gbank", 1, true)
	end

	-- Scan the guild roster
	local numTotal = select(1, GetNumGuildMembers())
	for i = 1, numTotal do
		local name, _, rankIndex, _, _, _, publicNote, officerNote, _, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name and name ~= "" then
			local normName = self:NormalizeName(name) or name
			local playerUid = guid:sub(8)
			if rankIndex and class then
				self.guildMembersCache[normName] = { isAuthority = self:IsAuthority(rankIndex), playerClass = class, playerUid = playerUid }
			end

			local isGuildBankAlt
			if publicNote and noteContainsGbank(publicNote) then
				isGuildBankAlt = true
			elseif canWeViewOfficerNotes and officerNote and noteContainsGbank(officerNote) then
				isGuildBankAlt = true
				self.areOfficerNotesUsedToDefineGuildBankAlts = true
			end

			if isGuildBankAlt then
				table.insert(guildBankAlts, normName)
				self.banksCache[normName] = true

				-- Register additional events if we're this guild bank alt
				if player == normName then
					GBCR.Events:RegisterGuildBankAltEvents()
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
		GBCR.Database.savedVariables.roster.alts = guildBankAlts
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
		local function updateRosterWithNewBankAlts(currentRosterList, scannedBankAltsList)
			-- Initialize if missing
			currentRosterList = currentRosterList or {}
			scannedBankAltsList = scannedBankAltsList or {}

			-- Build lookup of current roster
			local currentLookup = {}
			for _, name in ipairs(currentRosterList) do
				currentLookup[name] = true
			end

			-- Add only entries missing from current roster
			local addedCount = 0
			for _, normName in ipairs(scannedBankAltsList) do
				if not currentLookup[normName] then
					table.insert(currentRosterList, normName)
					addedCount = addedCount + 1
				end
			end

			-- Return boolean and the table
			return addedCount > 0, currentRosterList
		end

		-- If we identified a new guild bank, add it to our local roster
		local hasNewEntries, roster = updateRosterWithNewBankAlts(GBCR.Database.savedVariables.roster.alts, guildBankAlts)
		GBCR.Database.savedVariables.roster.alts = roster
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
			GBCR.Database.savedVariables.alts[normName] = {
				name = normName,
				version = 0,
				money = 0,
				items = {},
				ledger = {}
			}
			GBCR.Output:Debug("ROSTER", "Added missing guild bank alt stub data for %s", normName)
		end
	end

	-- Update lookup tables and variables after the roster rebuild
	self.rosterRefreshNeeded = false
	GBCR.Output:Debug("ROSTER", "Done with roster operations after %.2fms", debugprofilestop() - startTime)

	-- Update online status
	self:RefreshOnlineMembersCache(true)

	-- Notify others that we're ready
	GBCR.Protocol:Hello()

	-- Return the guildBankAlts table so it can be cached
	return guildBankAlts
end

-- Retrieve the list of guild bank alts from GBCR.Database.savedVariables.roster.alts
-- This returns an array (ordered iteration)
-- for i = 1, #list do print(list[i]) end
function Guild:GetRosterGuildBankAlts()
	if not GBCR.Database.savedVariables then
		return nil
	end

	local roster = GBCR.Database.savedVariables.roster
	local list = {}
	if roster and roster.alts then
		for _, v in pairs(roster.alts) do
			if type(v) == "string" and v ~= "" then
				table.insert(list, v)
			end
		end
	end

	if #list > 0 then
		return list
	end

	return nil
end

-- Request online members to share their guild bank alt data if we're missing it
function Guild:RequestMissingGuildBankAltData()
	-- Retrieve the cached roster
	local rosterAlts = self:GetRosterGuildBankAlts()
	if not rosterAlts or #rosterAlts == 0 then
		return
	end

	local missing = {}
	GBCR.Output:Debug("SYNC", "RequestMissingGuildBankAltData: starting check of %d guild bank alts on the roster", #rosterAlts)

	for i = 1, #rosterAlts do
        local guildBankAltName = rosterAlts[i]
		local norm = self:NormalizeName(guildBankAltName) or guildBankAltName
		local localAlt = GBCR.Database.savedVariables.alts and norm and GBCR.Database.savedVariables.alts[norm]
		local hasEntry = localAlt ~= nil
		local hasContent = hasEntry and GBCR.Protocol:HasAltContent(localAlt, norm)
		local isSelf = norm == self:GetNormalizedPlayer()

		GBCR.Output:Debug("SYNC", "RequestMissingGuildBankAltData: checking %s (hasEntry=%s, hasContent=%s, self=%s)", tostring(norm), tostring(hasEntry), tostring(hasContent), tostring(isSelf))
		if (not hasEntry or not hasContent) and not isSelf then
			table.insert(missing, norm)
		end
	end

	if #missing == 0 then
		GBCR.Output:Debug("SYNC", "RequestMissingGuildBankAltData: no missing data", #rosterAlts)

		return
	end

	GBCR.Output:Info("Requesting missing data for %d guild bank alts (have data for %d/%d).", #missing, #rosterAlts - #missing, #rosterAlts)
	for _, norm in ipairs(missing) do
		GBCR.Protocol:QueryForGuildBankAltData(nil, norm)
	end
end

-- Returns whether or not the provided player exists in the roster of guild bank alts
-- Uses the roster instead of the cache to consider guild bank alts defined in officer notes we may be unable to view
function Guild:IsGuildBankAlt(player)
	if not player then
		return false
	end

    local rosterAlts = self:GetRosterGuildBankAlts()
	if not rosterAlts or #rosterAlts == 0 then
		return false
	end

	local normPlayer = self:NormalizeName(player) or player
    local isBank = false
    for i = 1, #rosterAlts do
		local normBank = rosterAlts[i]
        if normBank == normPlayer then
            isBank = true
        end
    end

    return isBank
end

function Guild:IsQueryAllowed()
	if self.onlineMembersCount <= 1 then
		return false
	end

    self.hasRequested = true
    self.requestCount = (self.requestCount or 0) + 1

	return true
end

-- Called whenever the GUILD_ROSTER_UPDATE event fires (server pushes updates)
-- This rebuild the local cache of online member from the current guild roster
function Guild:RefreshOnlineMembersCache(force)
    local numTotal, numOnline = GetNumGuildMembers()
	local startTime = debugprofilestop()

    -- Skip if online count unchanged
    if not force and numOnline == self.onlineMembersCount then
        return
    end

	-- Empty roster edge case (briefly during loading)
    if numOnline == 0 then
        if self.onlineMembersCount ~= 0 then
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
        local name = select(1, GetGuildRosterInfo(i))
        if name and name ~= "" then
			local normName = self:NormalizeName(name) or name
            self.onlineMembers[normName] = true
			if self.banksCache and self.banksCache[normName] then
				self.onlineMembersThatAreGuildBankAlts[normName] = true
			end
        end
    end

	self.onlineMembersCount = numOnline
    GBCR.Output:Debug("ROSTER", "Refreshed online status (%d online, %d bank alts) in %.2fms", numOnline, Globals:Count(self.onlineMembersThatAreGuildBankAlts), debugprofilestop() - startTime)
end

-- Check if a player is currently online in the guild
function Guild:IsPlayerOnlineMember(playerName)
	if not playerName then
		return false
	end

	return self.onlineMembers[self:NormalizeName(playerName) or playerName] == true
end

-- Get list of all online members (for broadcasts)
function Guild:GetOnlineMemberList()
    return self.onlineMembers
end

-- Check if a player is currently online in the guild and a guild bank alt
function Guild:IsPlayerOnlineGuildBankAlt(playerName)
	if not playerName then
		return false
	end

	return self.onlineMembersThatAreGuildBankAlts[self:NormalizeName(playerName) or playerName] == true
end

-- Get list of all online guild bank alts
function Guild:GetOnlineGuildBankAlts()
    return self.onlineMembersThatAreGuildBankAlts
end

-- Wipe your own data: /bank wipe --
function Guild:WipeMine()
    local guild = self:GetGuildName()
	if not guild then
		return
	end

    self:Reset(guild)
end