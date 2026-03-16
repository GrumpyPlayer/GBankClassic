GBankClassic_Guild = GBankClassic_Guild or {}

local Guild = GBankClassic_Guild

Guild.Info = nil

Guild.player = nil
Guild.banksCache = {}
Guild.guildMembersCache = {}
Guild.areOfficerNotesUsedToDefineGuildBankAlts = false
Guild.guildRankAuthorityCache = {}
Guild.guildRankOfficerCache = {}
Guild.isAnyoneAuthority = false
Guild.canWeEditOfficerNotes = false
Guild.canWeViewOfficerNotes = false
Guild.onlineMembers = {}
Guild.onlineMembersThatAreGuildBankAlts = {}
Guild.onlineMembersCount = 0
Guild.rosterRefreshNeeded = false
Guild.MAX_PENDING_SENDS = 3
Guild.pendingSendCount = 0

local PENDING_SYNC_TTL_SECONDS = 180

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("wipe", "debugprofilestop")
local wipe = upvalues.wipe
local debugprofilestop = upvalues.debugprofilestop
local upvalues = Globals.GetUpvalues("GetNormalizedRealmName", "UnitName", "NewTicker", "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GetAddOnMetadata", "GetServerTime", "GetTime", "GetItemInfo", "After", "CanViewOfficerNote", "GuildControlGetNumRanks", "GuildControlGetRankFlags")
local GetNormalizedRealmName = upvalues.GetNormalizedRealmName
local UnitName = upvalues.UnitName
local NewTicker = upvalues.NewTicker
local IsInGuild = upvalues.IsInGuild
local GetGuildInfo = upvalues.GetGuildInfo
local GetNumGuildMembers = upvalues.GetNumGuildMembers
local GetGuildRosterInfo = upvalues.GetGuildRosterInfo
local GetAddOnMetadata = upvalues.GetAddOnMetadata
local GetServerTime = upvalues.GetServerTime
local GetTime = upvalues.GetTime
local GetItemInfo = upvalues.GetItemInfo
local After = upvalues.After
local CanViewOfficerNote = upvalues.CanViewOfficerNote
local GuildControlGetNumRanks = upvalues.GuildControlGetNumRanks
local GuildControlGetRankFlags = upvalues.GuildControlGetRankFlags
local upvalues = Globals.GetUpvalues("Item")
local Item = upvalues.Item

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
            local name, realm = UnitName("player"), self:GetCachedNormalizedRealm()
            if name and realm then
                self.player = name .. "-" .. realm
                timer:Cancel()
                self._playerRetryScheduled = false
            elseif retryCount >= maxRetries then
                timer:Cancel()
                self._playerRetryScheduled = false
            end
        end)
    end

    -- Always return a value (cached or fallback)
    return self.player or "Unknown-Unknown"
end

-- Cache the normalized realm name
local cachedNormalizedRealm = nil
function Guild:GetCachedNormalizedRealm()
    if not cachedNormalizedRealm then
        cachedNormalizedRealm = GetNormalizedRealmName()
    end

    return cachedNormalizedRealm
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

	local guildMemberFromCache = GBankClassic_Guild.guildMembersCache[self:NormalizeName(player) or player]
	local class = guildMemberFromCache and guildMemberFromCache.class or nil
	local isAuthority = guildMemberFromCache and guildMemberFromCache.isAuthority or false

	return class, isAuthority
end

-- AddOn config "Reset database", /bank reset, /bank wipe, /bank wipeall, GUILD_RANKS_UPDATE event via Guild:Init(name)
function Guild:Reset(name)
	if not name then
		return
	end

    GBankClassic_UI_Inventory:Close()
    GBankClassic_Database:Reset(name)
	GBankClassic_Guild.lastRosterRebuildTime = nil
    self.Info = GBankClassic_Database:Load(name)
	-- self:EnsureRequestsInitialized()
	self:RebuildGuildBankAltsRoster()
end

-- Resets if the data does not already exist, only runs on GUILD_RANKS_UPDATE
function Guild:Init(name)
	if not name then
		return false
	end

	if self.Info and self.Info.name == name then
		return false
	end

    self.hasRequested = false
    self.requestCount = 0

	self.Info = GBankClassic_Database:Load(name)
	if self.Info then
		-- self:EnsureRequestsInitialized()
		self:RebuildGuildBankAltsRoster()

		return true
	end

	self:Reset(name)

	return true
end

function Guild:CleanupMalformedAlts()
	if not self.Info or not self.Info.alts then
		return 0
	end

    local cleaned = 0
    for name, alt in pairs(self.Info.alts) do
        local remove = false
        if type(alt) ~= "table" then
            remove = true
        else
            -- Ensure version is present, but malformed nested fields are problematic
			if alt.items then
				-- alt.items should be an array or a map of items with ID fields; remove any empty entries
				for k, v in pairs(alt.items) do
					if not v or type(v) ~= "table" or not v.ID then
						alt.items[k] = nil
					end
				end
			end
            -- If after cleaning the alt has no meaningful fields (no version, no money, no items), remove it
			local hasData = false
			if alt.version then
				hasData = true
			end
			if alt.money then
				hasData = true
			end
			if alt.items and next(alt.items) then
				hasData = true
			end
			if not hasData then
				remove = true
			end
        end

        if remove then
			GBankClassic_Output:Debug("DATABASE", "Removing malformed guild bank alt entry for", name)
            self.Info.alts[name] = nil
            cleaned = cleaned + 1
        end
    end

    -- Ensure roster.alts is a proper array (remove nils and non-strings)
    if self.Info.roster and self.Info.roster.alts then
        local new_alts = {}
        for _, v in pairs(self.Info.roster.alts) do
            if type(v) == "string" and v ~= "" then
                table.insert(new_alts, v)
            end
        end
        self.Info.roster.alts = new_alts

		-- Remove data for characters that are no longer on the roster
		local roster = self.Info.roster.alts
		local alts = self.Info.alts

		-- Build a lookup set from roster values (guild bank alts)
		local rosterSet = {}
		for _, playerName in pairs(roster) do
			rosterSet[playerName] = true
		end

		-- Helper function to clean tables based on roster
		local function cleanTable(tbl)
			local keysToRemove = {}
			for playerName in pairs(tbl) do
				if not rosterSet[playerName] then
					table.insert(keysToRemove, playerName)
				end
			end
			for _, playerName in ipairs(keysToRemove) do
				tbl[playerName] = nil
			end
		end

		-- Clean the tables
		cleanTable(alts)
    end

    return cleaned
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

	return Guild.guildRankOfficerCache[rankIndex] == true
end

-- Check if we can view officer notes
function Guild:VerifyOfficerNotePermissions()
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
	if not self.Info then
		return
	end

	local time = GetServerTime()
	if self.lastRosterRebuildTime == nil or time - self.lastRosterRebuildTime > 30 then
		self.lastRosterRebuildTime = time
	else
		GBankClassic_Output:Debug("ROSTER", "Skipping excessive roster rebuild (last rebuild was %.2f seconds ago)", time - self.lastRosterRebuildTime)
		return
	end

	local guildBankAlts = {}
	local startTime = debugprofilestop()
	if self.banksCache then wipe(self.banksCache) end
	if self.guildMembersCache then wipe(self.guildMembersCache) end
	if self.guildRankAuthorityCache then wipe(self.guildRankAuthorityCache) end
	self.areOfficerNotesUsedToDefineGuildBankAlts = false
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
			local uid = guid:sub(8)
			if rankIndex and class then
				self.guildMembersCache[normName] = { isAuthority = self:IsAuthority(rankIndex), class = class, uid = uid }
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

				-- Register additional events if we're a guild bank alt
				if player == normName then
					GBankClassic_Events:RegisterGuildBankAltEvents()
				end
			end
		end
	end
    GBankClassic_Output:Debug("ROSTER", "Scanned %d members (%d guild bank alts, areOfficerNotesUsedToDefineGuildBankAlts=%s) in %.2fms", numTotal, GBankClassic_Globals:Count(self.banksCache), tostring(self.areOfficerNotesUsedToDefineGuildBankAlts), debugprofilestop() - startTime)

	-- Determine what to do with the roster (copy/merge/broadcast)
	local selfIsAuthority = self.guildMembersCache[player] and self.guildMembersCache[player].isAuthority
	if isAnyoneAuthority or selfIsAuthority then
		-- Our local roster is always complete
		self.Info.roster.alts = guildBankAlts
		-- Determine if we need to broadcast our roster
		if isAnyoneAuthority then
			-- If all ranks can view officer notes, then everyone is authority and rosters do not need to be synced
			self.Info.roster.version = nil
		elseif selfIsAuthority then
			-- Only some ranks can view officer notes, and we're an authority
			self.Info.roster.version = GetServerTime()
			-- Determine if officer notes are relevant (does at least one officer note contain 'gbank'?)
			if self.areOfficerNotesUsedToDefineGuildBankAlts then
				-- Officer notes are used to define guild bank alts
				-- Broadcast our roster fingerprint as an authority to the guild to allow pull requests via whisper for non-authorities
				-- The hash is to identify if content changed

				-- TODO:
				-- GBankClassic_Output:Debug("ROSTER", "Broadcasting fingerprint of our roster as authority")
				-- gbank-roster-heartbeat to GUILD: 
				--   senderIsAuthority: true, 
				--   self.areOfficerNotesUsedToDefineGuildBankAlts: true,
				--   version: unix timestamp
				--   hash: GBankClassic_Bank:ComputeImprovedInventoryHash(guildBankAlts.items, true)

				-- when player receives the heartbeat, and if they are not an authority:
				--   gbank-roster-request WHISPER to sender that is an authority: send me your roster
				-- 
				-- when an authority receives gbank-roster-request WHISPER:
				--   gbank-roster WHISPER to requester
				--     roster alts: table
				--     version:
			end
		end
		GBankClassic_Output:Debug("ROSTER", "Rebuilt guild bank alt roster from guild notes with %d guild bank alts (version=%s, isAnyoneAuthority=%s, selfIsAuthority=%s)", #guildBankAlts, tostring(self.Info.roster.version), tostring(isAnyoneAuthority), tostring(selfIsAuthority))
	else
		-- We're unable to view officer notes
		-- Our roster may be incomplete (it is complete if officer notes are irrelevant)
		-- A possible incoming roster broadcast will make it clear if they are relevant
		-- We whisper the sender to request their roster when we see the gbank-roster-heartbeat
		-- If we never see gbank-roster-heartbeat then the officer notes are irrelevant

		-- Verify if there's a change in the roster of guild bank alts
		-- Preserve the existing roster and only add newly detected guild bank alts (preserve existing entries)
		local function updateRosterWithNewBankAlts(currentRosterList, scannedBankAltsList)
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

			-- Return true if roster changed
			return addedCount > 0
		end

		-- If we identified a new guild bank, add it to our local roster
		local hasNewEntries = updateRosterWithNewBankAlts(self.Info.roster.alts, guildBankAlts)
		if hasNewEntries then
			-- Ensure our version is set to nil to avoid broadcasting this to others
			-- We do not know if officer notes are used to define guild bank alts
			-- We may have an incomplete roster
			self.Info.roster.version = nil

			-- -- Ask the guild bank alt sync leader for their roster
			-- local _, leader = GBankClassic_Guild:CheckIfWeAreGuildBankAltSyncLeader()
			-- -- TODO:
			-- GBankClassic_Output:Debug("ROSTER", "Rebuilt (possibly incomplete) guild bank alt roster from guild notes with %d guild bank alts - requesting latest roster from authority", #self.Info.roster.alts)
			-- --   gbank-roster-request WHISPER to leader: send me your roster
			-- GBankClassic_Output:Debug("ROSTER", "Requested %s for an updated roster", leader)
		end
	end

	-- TODO: only allow manual roster sync for if version is not nil (gbank-roster to guild with roster alts: table, and version)
	-- done elsewhere

	-- Ensure local alt data exists for all roster guild bank alts
	if not self.Info.alts then
		self.Info.alts = {}
	end
	for _, normName in ipairs(self.Info.roster.alts) do
		if normName and not self.Info.alts[normName] then
			self.Info.alts[normName] = {
				name = normName,
				version = 0,
				money = 0,
				inventoryHash = 0,
				items = {},
				ledger = {}
			}
			GBankClassic_Output:Debug("ROSTER", "Added missing guild bank alt stub data for %s", normName)
		end
	end

	-- Update lookup tables and variables after the roster rebuild
	self.rosterRefreshNeeded = false
	GBankClassic_Output:Debug("ROSTER", "Done with roster operations after %.2fms", debugprofilestop() - startTime)

	-- Update online status
	self:RefreshOnlineMembersCache(true)

	-- Return the guildBankAlts table so it can be cached
	return guildBankAlts
end

-- Retrieve the list of guild bank alts from self.Info.roster.alts
-- This returns an array (ordered iteration)
-- for i = 1, #list do print(list[i]) end
function Guild:GetRosterGuildBankAlts()
	if not self.Info then
		return nil
	end

	local roster = self.Info.roster
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
	GBankClassic_Output:Debug("PROTOCOL", "RequestMissingGuildBankAltData: Starting check of %d roster alts", #rosterAlts)

	for i = 1, #rosterAlts do
        local guildBankAltName = rosterAlts[i]
		local norm = self:NormalizeName(guildBankAltName) or guildBankAltName
		local localAlt = self.Info.alts and norm and self.Info.alts[norm]
		local hasEntry = localAlt ~= nil
		local hasContent = hasEntry and self:HasAltContent(localAlt, norm)
		local isSelf = norm == self.player

		-- Log every alt to see what's happening
		GBankClassic_Output:Debug("PROTOCOL", "RequestMissingGuildBankAltData check: %s hasEntry=%s hasContent=%s, self=%s", tostring(norm), tostring(hasEntry), tostring(hasContent), tostring(isSelf))

		-- Check if we need to request this alt that's not ourself: no entry, no content, OR hash mismatch
		if (not hasEntry or not hasContent) and not isSelf then
			table.insert(missing, norm)
		end
	end

	if #missing == 0 then
		GBankClassic_Output:Debug("ROSTER", "All %d roster alts present locally.", #rosterAlts)

		return
	end

	GBankClassic_Output:Info("Requesting %d missing guild bank alts (have %d/%d).", #missing, #rosterAlts - #missing, #rosterAlts)

	-- Query each missing alt using pull-based protocol
	for _, norm in ipairs(missing) do
		self:QueryAltPullBased(norm)
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

function Guild:GetVersion()
	if not self.Info then
		return nil
	end

    local rosterAlts = self:GetRosterGuildBankAlts()
	if not rosterAlts or #rosterAlts == 0 then
		GBankClassic_Output:Debug("PROTOCOL", "GetVersion: early exit because our roster is empty")

		return nil
	end

    local versionInfo = GetAddOnMetadata("GBankClassic", "Version"):gsub("%.", "")
    local versionNumber = tonumber(versionInfo)
    local data = {
        addon = versionNumber,
		protocol_version = PROTOCOL.VERSION,
		roster = nil,
		alts = {},
    }

    if self.Info.name then
        data.name = self.Info.name
    end
    if self.Info.roster.version then
        data.roster = self.Info.roster.version
    end

	-- -- Include request sync summary (version + hash) in version broadcasts.
	-- data.requests = {
	-- 	version = self:GetRequestsVersion(),
	-- 	hash = self:GetRequestsHash(),
	-- }

    for k, v in pairs(self.Info.alts) do
		if self:IsGuildBankAlt(k) then
			local hasContent = self:HasAltContent(v, k)
			if not hasContent then
				GBankClassic_Output:Debug("PROTOCOL", "GetVersion: excluding %s from version broadcast (no content)", k)
			else
				if type(v) == "table" and v.version then
					if v.inventoryHash then
						data.alts[k] = {
							version = v.version,
							hash = v.inventoryHash
						}
						GBankClassic_Output:Debug("PROTOCOL", "GetVersion: including %s in local version data (ver=%d, hash=%d)", k, v.version, v.inventoryHash)
					else
						-- Legacy format for old clients
						data.alts[k] = v.version
						GBankClassic_Output:Debug("PROTOCOL", "GetVersion: including %s in local version data (ver=%d, no hash)", k, v.version)
					end
				end
			end
		else
			GBankClassic_Output:Debug("PROTOCOL", "GetVersion: excluding %s from local version data (not in the roster)", k)
		end
    end

    return data
end

function Guild:MarkPendingSync(syncType, sender, name)
	if not syncType or not sender then
		return
	end

	local now = GetServerTime()
	local normSender = self:NormalizeName(sender) or sender
	if not self.pendingSync then
		self.pendingSync = { roster = {}, alts = {} }
	end
	if not self.pendingSync.roster then
		self.pendingSync.roster = {}
	end
	if not self.pendingSync.alts then
		self.pendingSync.alts = {}
	end

	if syncType == "roster" then
		if self.pendingSync.roster and normSender then
			self.pendingSync.roster[normSender] = now
		end
	elseif syncType == "alt" and name then
		local normName = self:NormalizeName(name) or name
		if self.pendingSync.alts and normName and not self.pendingSync.alts[normName] then
			self.pendingSync.alts[normName] = {}
		end
		if self.pendingSync.alts and normName and normSender and self.pendingSync.alts[normName] then
			self.pendingSync.alts[normName][normSender] = now
		end
	end
end

function Guild:ConsumePendingSync(syncType, sender, name)
	if not syncType or not sender then
		return false
	end

	if not self.pendingSync then
		return false
	end

	local now = GetServerTime()
	local normSender = self:NormalizeName(sender) or sender
	if syncType == "roster" then
		local roster = self.pendingSync.roster
		local ts = roster and roster[normSender]
		if ts and now - ts <= PENDING_SYNC_TTL_SECONDS then
			roster[normSender] = nil

			return true
		end
		if ts then
			roster[normSender] = nil
		end

		return false
	end
	if syncType == "alt" and name then
		local normName = self:NormalizeName(name) or name
		local alts = self.pendingSync.alts and self.pendingSync.alts[normName]
		local ts = alts and alts[normSender]
		if ts and now - ts <= PENDING_SYNC_TTL_SECONDS then
			alts[normSender] = nil
			if next(alts) == nil then
				self.pendingSync.alts[normName] = nil
			end

			return true
		end
		if ts then
			alts[normSender] = nil
			if next(alts) == nil then
				self.pendingSync.alts[normName] = nil
			end
		end
	end

	return false
end

function Guild:QueryRoster(player, version)
	self.hasRequested = true
	if self.requestCount == nil then
		self.requestCount = 1
	else
		self.requestCount = self.requestCount + 1
	end
	self:MarkPendingSync("roster", player)
	local data = GBankClassic_Core:SerializeWithChecksum({ player = player, type = "roster", version = version })
	GBankClassic_Core:SendCommMessage("gbank-r", data, "Guild", nil, "NORMAL")
end

function Guild:QueryAlt(player, name, version)
	self.hasRequested = true
	if self.requestCount == nil then
		self.requestCount = 1
	else
		self.requestCount = self.requestCount + 1
	end
	self:MarkPendingSync("alt", player, name)
	local data = GBankClassic_Core:SerializeWithChecksum({ player = player, type = "alt", name = name, version = version })
	GBankClassic_Core:SendCommMessage("gbank-r", data, "Guild", nil, "NORMAL")
end

-- Pull-based query - whisper to guild bank alt if known, send to guild otherwise
function Guild:QueryAltPullBased(name)
	if not name then
		return
	end

	if GBankClassic_Guild.onlineMembersCount <= 1 then
		return
	end

	local normName = self:NormalizeName(name) or name

	-- Log that we're sending a query
	GBankClassic_Output:Debug("PROTOCOL", "QueryAltPullBased called for %s", normName)

	local norm = normName
	self.hasRequested = true
	if self.requestCount == nil then
		self.requestCount = 1
	else
		self.requestCount = self.requestCount + 1
	end

	-- Check if we have an online guild bank alt
	local guildBankAlt = nil
	local onlineGuildBankAltCount = 0

	for member, _ in pairs(self.onlineMembers or {}) do
		if self:IsGuildBankAlt(member) and member ~= self:GetNormalizedPlayer() then
			onlineGuildBankAltCount = onlineGuildBankAltCount + 1
			GBankClassic_Output:Debug("PROTOCOL", "Online guild bank alt from roster: %s, isOnline=%s", member, tostring(self:IsPlayerOnlineMember(member)))
			if not guildBankAlt then
				guildBankAlt = member
			end
		end
	end
	GBankClassic_Output:Debug("PROTOCOL", "QueryAltPullBased for %s: %d online guild bank alts found from guild roster", norm, onlineGuildBankAltCount)

	-- Build request message
	local request = {
		type = "alt-request",
		name = norm,
		requester = self:GetNormalizedPlayer()
	}

	local data = GBankClassic_Core:SerializeWithChecksum(request)

	-- No guild bank alt found in roster - broadcast to guild hoping someone has data
	if not guildBankAlt then
		GBankClassic_Output:Debug("PROTOCOL", "QueryAltPullBased for %s: no guild bank alt found, broadcasting to guild", norm)
		GBankClassic_Core:SendCommMessage("gbank-r", data, "GUILD", nil, "NORMAL")
		self:MarkPendingSync("alt", "guild", norm)

		return
	end

	-- Guild bank alt exists but offline - broadcast to guild to ask if someone else has data
	if not self:IsPlayerOnlineMember(guildBankAlt) then
		GBankClassic_Output:Debug("PROTOCOL", "QueryAltPullBased for %s: guild bank alt %s offline, broadcasting to guild", norm, guildBankAlt)
		GBankClassic_Core:SendCommMessage("gbank-r", data, "GUILD", nil, "NORMAL")
		self:MarkPendingSync("alt", "guild", norm)

		return
	end

	-- Whisper guild bank alt last (guild bank alt confirmed online)
	GBankClassic_Output:Debug("PROTOCOL", "Whisper query for %s to guild bank alt %s", norm, guildBankAlt)
	if not GBankClassic_Core:SendWhisper("gbank-r", data, guildBankAlt, "NORMAL") then
		GBankClassic_Output:Debug("PROTOCOL", "Whisper query failed for %s to %s", norm, guildBankAlt)

		return
	end

	self:MarkPendingSync("alt", guildBankAlt, norm)
end

function Guild:SendRosterData()
	if not self.Info or not self.Info.roster or not self.Info.roster.alts then
		GBankClassic_Output:Debug("ROSTER", "SendRosterData skipped - no roster data available")

		return
	end

	local data = GBankClassic_Core:SerializeWithChecksum({ type = "roster", roster = self.Info.roster })
	GBankClassic_Core:SendCommMessage("gbank-d", data, "Guild", nil, "BULK")
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
            wipe(self.onlineMembers)
			wipe(self.onlineMembersThatAreGuildBankAlts)
            self.onlineMembersCount = 0
        end

        return
    end

    -- Rebuild cache of online members and online guild bank alts
	-- We only need to scan until we've found all online members (they always appear first)
    wipe(self.onlineMembers)
	wipe(self.onlineMembersThatAreGuildBankAlts)
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
    GBankClassic_Output:Debug("ROSTER", "Refreshed online status (%d online, %d bank alts) in %.2fms", numOnline, GBankClassic_Globals:Count(self.onlineMembersThatAreGuildBankAlts), debugprofilestop() - startTime)
end

-- Check if a player is currently online in the guild
function Guild:IsPlayerOnlineMember(playerName)
	if not playerName then
		return false
	end

	return self.onlineMembers[self:NormalizeName(playerName) or playerName] == true
end

-- Get list of all online members (for broadcasts)
local onlineMembersCache = {}
function Guild:GetOnlineMemberList()
    wipe(onlineMembersCache)
    for normName in pairs(self.onlineMembers) do
        table.insert(onlineMembersCache, normName)
    end

    return onlineMembersCache
end

-- Check if a player is currently online in the guild and a guild bank alt
function Guild:IsPlayerOnlineGuildBankAlt(playerName)
	if not playerName then
		return false
	end

	return self.onlineMembersThatAreGuildBankAlts[self:NormalizeName(playerName) or playerName] == true
end

-- Get list of all online guild bank alts
local onlineGuildBankAltsCache = {}
function Guild:GetOnlineGuildBankAlts()
    wipe(onlineGuildBankAltsCache)
    for normName in pairs(self.onlineMembersThatAreGuildBankAlts) do
        table.insert(onlineGuildBankAltsCache, normName)
    end

    return onlineGuildBankAltsCache
end

-- Compute minimal state summary for pull-based protocol
function Guild:ComputeStateSummary(name)
	if not name then
		return nil
	end

	local norm = self:NormalizeName(name) or name

	-- If we don't have data for this alt, return a "no data" summary
	if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
		return { version = 0, hash = nil, money = 0, items = {}, ledger = {} }
	end

	local alt = self.Info.alts[norm]
	local summary = {
		version = alt.version or 0,
		hash = alt.inventoryHash or nil
	}

	return summary
end

-- Send state summary to responder (step 4 of pull-based flow)
function Guild:SendStateSummary(name, target)
	GBankClassic_Output:DebugComm("SendStateSummary called: name=%s, target=%s", tostring(name), tostring(target))
	if not name or not target then
		GBankClassic_Output:DebugComm("SendStateSummary early return: missing params")

		return
	end

	local summary = self:ComputeStateSummary(name)
	if not summary then
		GBankClassic_Output:DebugComm("SendStateSummary: No summary for %s", tostring(name))
		GBankClassic_Output:Debug("SYNC", "Cannot send state summary for %s (no data)", name)

		return
	end

	local message = {
		type = "state-summary",
		name = name,
		summary = summary,
	}

	local data = GBankClassic_Core:SerializeWithChecksum(message)
	GBankClassic_Output:DebugComm("Sending state summary via whisper to %s for %s (%d bytes, hash=%s)", target, name, #data, tostring(summary.hash))
	if not GBankClassic_Core:SendWhisper("gbank-state", data, target, "NORMAL") then
		return
	end
	GBankClassic_Output:Debug("SYNC", "Sent state summary for %s to %s (items=%d, %d bytes)", name, target, summary.items and #summary.items or 0, string.len(data))
end

-- Respond to state summary
-- Compare requester's state with our data and send appropriate response
function Guild:RespondToStateSummary(name, summary, requester)
	GBankClassic_Output:DebugComm("RespondToStateSummary called: name=%s, requester=%s", tostring(name), tostring(requester))
	if not name or not summary or not requester then
		GBankClassic_Output:DebugComm("RespondToStateSummary early return: missing params")
		return
	end

	local norm = self:NormalizeName(name)
	if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
		GBankClassic_Output:DebugComm("RespondToStateSummary: No data for %s", norm)
		GBankClassic_Output:Debug("SYNC", "Cannot respond to state summary for %s (no data)", norm)

		return
	end

	local currentAlt = self.Info.alts[norm]
	local requesterVersion = summary.version or 0
	local currentVersion = currentAlt.version or 0
	local requesterHash = summary.hash or nil
	local currentHash = currentAlt.inventoryHash or nil

	GBankClassic_Output:DebugComm("RespondToStateSummary: %s requesterV=%d currentV=%d requesterHash=%s currentHash=%s", norm, requesterVersion, currentVersion, tostring(requesterHash), tostring(currentHash))

	-- If current alt doesn't have a hash, send full data (might be from pre-hash version)
	if not currentHash then
		GBankClassic_Output:DebugComm("Current alt missing hash - sending full data for %s", norm)
		GBankClassic_Output:Debug("SYNC", "Sending full data to %s for %s (responder has no hash)", requester, norm)
		self:SendAltData(norm, requester)

		return
	end

	-- If requester has no hash (nil), they have no data - send everything
	if not requesterHash then
		GBankClassic_Output:DebugComm("Requestor has no data (hash=nil) - sending full data for %s", norm)
		GBankClassic_Output:Debug("SYNC", "Sending full data to %s for %s (requester has no data)", requester, norm)
		self:SendAltData(norm, requester)

		return
	end

	-- Compare hashes
	if requesterHash == currentHash then
		local noChangeMsg = {
			type = "no-change",
			name = norm,
			version = currentVersion,
			hash = currentHash
		}
		local data = GBankClassic_Core:SerializeWithChecksum(noChangeMsg)
		GBankClassic_Output:DebugComm("Sending no-change to %s for %s (hash=%d)", requester, norm, currentHash)
		if not GBankClassic_Core:SendWhisper("gbank-nochange", data, requester, "NORMAL") then
			return
		end

		GBankClassic_Output:Debug("SYNC", "Sent no-change reply to %s for %s (hash=%d)", requester, norm, currentHash)

		return
	else
		GBankClassic_Output:DebugComm("Inventory change - calling SendAltData for %s (inv: requester=%d, current=%d)", norm, requesterHash, currentHash)
		GBankClassic_Output:Debug("SYNC", "Sending data to %s for %s (hash mismatch: inv=%d->%d)", requester, norm, requesterHash, currentHash)
		self:SendAltData(norm, requester)

		return
	end
end

-- Strip link fields from items for transmission (bandwidth optimization)
-- Saves 60-80 bytes per item, receiver reconstructs with GetItemInfo()
function Guild:StripItemLinks(items)
	if not items then
		return nil
	end

	local stripped = {}
	for _, item in ipairs(items) do
		local strippedItem = {
			ID = item.ID,
			Count = item.Count
		}
		-- Preserve link (weapons/armor)
		if item.Link and GBankClassic_Item:NeedsLink(item.Link) then
			strippedItem.Link = item.Link
		end

		table.insert(stripped, strippedItem)
	end

	return stripped
end

-- Reconstruct link fields after receiving data
-- Calls GetItemInfo() to recreate links from ItemID
-- Throttle UI refreshes to prevent stuttering when many items load async
local lastUIRefresh = 0
local function throttledUIRefresh()
	local now = GetTime()
	if now - lastUIRefresh < 0.5 then -- Throttle to max once per 0.5 seconds
		return
	end

	lastUIRefresh = now

	-- Only refresh if UI is actually open
	if GBankClassic_UI_Inventory.isOpen then
		GBankClassic_UI_Inventory:DrawContent()
		GBankClassic_UI_Inventory:RefreshCurrentTab()
	end
	if GBankClassic_UI_Search.isOpen then
		GBankClassic_UI_Search:BuildSearchData()
		GBankClassic_UI_Search:DrawContent()
    	GBankClassic_UI_Search.searchField:Fire("OnEnterPressed")
	end
	if GBankClassic_UI_Donations.isOpen then
		GBankClassic_UI_Donations:DrawContent()
	end
end

-- Queue system for batched item reconstruction
local itemReconstructQueue = {}
local isProcessingQueue = false
local pendingAsyncLoads = 0 -- Track number of pending async loads
local MAX_CONCURRENT_ASYNC = 3 -- Limit concurrent async operations
local BATCH_SIZE = 10 -- Process 10 items at a time
local BATCH_DELAY = 0.2 -- 0.2 second delay between batches (slower = smoother)

local function processItemQueue()
	if #itemReconstructQueue == 0 then
		isProcessingQueue = false

		return
	end

	-- Process a batch of items
	local processCount = math.min(BATCH_SIZE, #itemReconstructQueue)
	local loadedAnyInBatch = false

	for i = 1, processCount do
		local item = table.remove(itemReconstructQueue, 1)
		if item and item.ID and not item.Link then
			local itemLink = select(2, GetItemInfo(item.ID))
			if itemLink then
				item.Link = itemLink
				loadedAnyInBatch = true
			else
				-- Item not in cache - only start async if under limit
				if pendingAsyncLoads < MAX_CONCURRENT_ASYNC then
					pendingAsyncLoads = pendingAsyncLoads + 1
					local itemObj = Item:CreateFromItemID(item.ID)

					-- Check itemObj state
					GBankClassic_Output:Debug("ITEM", "Loading item %d: itemObj=%s, itemObj.itemID=%s", item.ID or -1, tostring(itemObj), itemObj and tostring(itemObj.itemID) or "nil")

					if itemObj and itemObj.itemID and itemObj.itemID == item.ID then
						-- Item object is valid, try ContinueOnItemLoad with error protection
						GBankClassic_Output:Debug("ITEM", "Item %d passed validation, calling ContinueOnItemLoad", item.ID)
						local success, err = pcall(function()
							itemObj:ContinueOnItemLoad(function()
								pendingAsyncLoads = pendingAsyncLoads - 1
								local link = itemObj:GetItemLink()
								if link then
									item.Link = link
									throttledUIRefresh()
								end
							end)
						end)
						if not success then
							GBankClassic_Output:Debug("ITEM", "ContinueOnItemLoad crashed for item %d: %s", item.ID, tostring(err))
							pendingAsyncLoads = pendingAsyncLoads - 1
						end
					else
						-- Item object is nil or corrupted, skip
						GBankClassic_Output:Debug("ITEM", "Item %d failed validation, skipping", item.ID or -1)
						pendingAsyncLoads = pendingAsyncLoads - 1
					end
				else
					-- Too many pending, requeue for later
					table.insert(itemReconstructQueue, item)
				end
			end
		end
	end

	-- Refresh UI if any items loaded synchronously in this batch
	if loadedAnyInBatch then
		throttledUIRefresh()
	end

	-- Schedule next batch
	if #itemReconstructQueue > 0 then
		After(BATCH_DELAY, processItemQueue)
	else
		isProcessingQueue = false
	end
end

-- Reconstruct single item link (immediate, synchronous only)
function Guild:ReconstructItemLink(item)
	if not item or not item.ID or item.Link then
		return
	end

	-- Try synchronous reconstruction from cache only
	local itemLink = select(2, GetItemInfo(item.ID))
	if itemLink then
		item.Link = itemLink
	end
end

-- Reconstruct link fields after receiving data
-- Calls GetItemInfo() to recreate links from ItemID
-- Queued/batched to prevent stuttering
function Guild:ReconstructItemLinks(items)
	if not items then
		return
	end

	-- Add all items without links to queue for async loading
	-- Items already in cache will load synchronously and won't need async
	for _, item in ipairs(items) do
		if item and item.ID and not item.Link then
			table.insert(itemReconstructQueue, item)
		end
	end

	-- Start processing queue if not already running
	if not isProcessingQueue and #itemReconstructQueue > 0 then
		isProcessingQueue = true
		processItemQueue()
	end
end

-- SendAddonMessageResult enum values from ChatThrottleLib
local SEND_RESULT = {
	Success = 0,
	AddonMessageThrottle = 3,
	NotInGroup = 5,
	ChannelThrottle = 8,
	GeneralError = 9,
}

local function getSendResultName(result)
	if result == SEND_RESULT.Success or result == true then
        return "Success"
	elseif result == SEND_RESULT.AddonMessageThrottle then
        return "AddonMessageThrottle"
	elseif result == SEND_RESULT.NotInGroup then
        return "NotInGroup"
	elseif result == SEND_RESULT.ChannelThrottle then
        return "ChannelThrottle"
	elseif result == SEND_RESULT.GeneralError then
        return "GeneralError"
	elseif result == false then
        return "Failed"
	else
        return tostring(result)
	end
end

-- Create a per-send callback with its own stats tracking
local function createOnChunkSentCallback(altName)
	-- Per-send stats (closure captures these)
	local sendStats = {
		startTime = nil,
		lastBytes = 0,
		chunksSent = 0,
		failures = 0,
		throttled = 0,
	}

	return function(arg, bytesSent, totalBytes, sendResult)
		-- Detect start of a new send and auto-reset state
		if bytesSent > 0 and sendStats.lastBytes == 0 then
			sendStats.abort = false
			sendStats.startTime = nil
			sendStats.lastBytes = 0
			sendStats.chunksSent = 0
			sendStats.failures = 0
			sendStats.throttled = 0
		end

		-- Abort further processing on failure
		if sendStats.abort then
			return
		end

		-- Track chunk count (each callback = one chunk sent, ~254 bytes each)
		local bytesThisChunk = bytesSent - sendStats.lastBytes
		if bytesThisChunk > 0 then
			sendStats.chunksSent = sendStats.chunksSent + 1
		end
		sendStats.lastBytes = bytesSent

		-- Track failures
		local isSuccess = (sendResult == SEND_RESULT.Success or sendResult == true or sendResult == nil)
		local isThrottled = (sendResult == SEND_RESULT.AddonMessageThrottle or sendResult == SEND_RESULT.ChannelThrottle)
		if isThrottled then
			sendStats.throttled = sendStats.throttled + 1
		elseif not isSuccess then
			sendStats.failures = sendStats.failures + 1
		end

		-- Initialize start time on first chunk
		if sendStats.startTime == nil then
			sendStats.startTime = GetTime()
		end

		local totalChunks = math.ceil(totalBytes / 254)

		-- Print error on failed send
		if not isSuccess then
			local resultStr = getSendResultName(sendResult)
			GBankClassic_Output:Debug("CHUNK","chunk %d/%d failed: %s", sendStats.chunksSent, totalChunks, resultStr, "Aborting send due to failure")
			sendStats.abort = true

			return
		end

		-- Show progress at start
		if sendStats.chunksSent == 1 then
			GBankClassic_Output:Debug("CHUNK", "Sharing guild bank data: %d bytes in ~%d chunks...", totalBytes, totalChunks)
		end

		-- Completion summary
		if bytesSent >= totalBytes then
			local elapsed = GetTime() - (sendStats.startTime or GetTime())
			local summary = string.format("Send complete: %d chunks, %d bytes in %.1fs", sendStats.chunksSent, totalBytes, elapsed)
			if sendStats.failures > 0 or sendStats.throttled > 0 then
				summary = summary .. string.format(" | failures: %d, throttled: %d", sendStats.failures, sendStats.throttled)
			end

			GBankClassic_Output:Debug("CHUNK", summary)

			-- Decrement peer send queue counter
			if Guild.pendingSendCount > 0 then
				Guild.pendingSendCount = Guild.pendingSendCount - 1
				GBankClassic_Output:Debug("SYNC", "Peer send completed - queue now: %d/%d", Guild.pendingSendCount, Guild.MAX_PENDING_SENDS)
			end

			-- Warn on failures
			if sendStats.failures > 0 then
				GBankClassic_Output:Debug("CHUNK", "%d send failures occurred!", sendStats.failures)
			end

			-- Reset stats for next operation
			sendStats.abort = false
			sendStats.startTime = nil
			sendStats.lastBytes = 0
			sendStats.chunksSent = 0
			sendStats.failures = 0
			sendStats.throttled = 0
		end
	end
end

function Guild:SendAltData(name, target)
	if not name then
		return
	end

    -- Ensure we have guild info before proceeding
    if not self.Info or not self.Info.name then
        GBankClassic_Output:Error("SendAltData failed: Guild info not loaded for %s", name)

        return
    end

    -- Ensure alts table exists
    if not self.Info.alts then
        GBankClassic_Output:Error("SendAltData failed: No alts table for %s", name)

        return
    end

    -- Check if alt data exists before proceeding
	local norm = self:NormalizeName(name) or name
    local currentAlt = self.Info.alts[norm]
    if not currentAlt then
        GBankClassic_Output:Error("SendAltData failed: No data for alt %s (norm=%s)", name, norm)

         return
     end

    -- Validate alt has content or hash before sending
    if not self:HasAltData(currentAlt) then
        GBankClassic_Output:Debug("SYNC", "SendAltData skipped: No valid data for %s", norm)

        return
    end

	local channel = target and "WHISPER" or "GUILD"
    local dest = target or nil

	GBankClassic_Output:Debug("SYNC", "SendAltData for %s", norm)

	-- Log what we're about to send
	local itemsCount = currentAlt.items and #currentAlt.items or 0
	GBankClassic_Output:Debug("SYNC", "Sending %s: alt.items=%d", norm, itemsCount)

	-- Send full dataync
	local onChunkSent = createOnChunkSentCallback(norm)
	local dataNoLinks

	-- New format (only keep links for items with an enchant, suffix, or weapon/armor class)
	local strippedAlt = self:StripAltLinks(currentAlt)
	dataNoLinks = GBankClassic_Core:SerializeWithChecksum({ type = "alt", name = norm, alt = strippedAlt })
	GBankClassic_Output:DebugComm("Sending response: gbank-d for %s (%d bytes)", norm, #dataNoLinks)
	if channel == "WHISPER" and dest then
		GBankClassic_Core:SendWhisper("gbank-d", dataNoLinks, dest, "NORMAL", onChunkSent)
	else
		GBankClassic_Core:SendCommMessage("gbank-d", dataNoLinks, "Guild", nil, "BULK", onChunkSent)
	end

	-- Log what was sent
	GBankClassic_Output:Debug("SYNC", "Sent full sync for %s: gbank-d (%d bytes without links)", norm, string.len(dataNoLinks or ""))
end

-- Only keep links for items with an enchant, suffix, or weapon/armor class before transmission
function Guild:StripAltLinks(alt)
	if not alt then
		return nil
	end

	local strippedItems = self:StripItemLinks(alt.items)
	local stripped = {
		version = alt.version,
		inventoryHash = alt.inventoryHash,
		improvedInventoryHash = alt.improvedInventoryHash,
		money = alt.money,
		items = strippedItems,
		ledger = alt.ledger
	}

	return stripped
end


function Guild:ReceiveAltData(name, alt, sender)
	if not self.Info then
		return ADOPTION_STATUS.IGNORED
	end

	-- Sanitize incoming alt data
	local function sanitizeAlt(a)
		if not a or type(a) ~= "table" then
			return nil
		end

		GBankClassic_Output:Debug("SYNC", "ReceiveAltData for %s", name)

		-- Sanitize alt.items (array)
		if a.items then
			local cleaned = {}
			for k, v in pairs(a.items) do
				if v and type(v) == "table" and v.ID then
					table.insert(cleaned, v)
				end
			end
			a.items = cleaned
		end

		return a
	end

	alt = sanitizeAlt(alt)
	if not alt then
		return ADOPTION_STATUS.INVALID
	end

	-- Log what we received
	GBankClassic_Output:Debug("SYNC", "ReceiveAltData for %s: alt.items=%d", name, GBankClassic_Globals:Count(alt.items))

	-- Dedupe
	if next(alt.items) then
		local aggregated = GBankClassic_Item:Aggregate(alt.items, nil)
		local arrayItems = {}
		for _, item in pairs(aggregated) do
			table.insert(arrayItems, item)
		end
		alt.items = arrayItems
		GBankClassic_Output:Debug("SYNC", "alt.items exists for %s, deduplicated and converted to array: %d items", name, #alt.items)
	end

	local norm = self:NormalizeName(name) or name
	local existing = self.Info.alts[norm]
	local senderNorm = sender and (self:NormalizeName(sender) or sender) or nil

	-- Guild bank alt protection logic
	-- Rule 1: Never accept data about yourself (you are source of truth)
	-- Rule 2: Guild bank alts only accept data about other guild bank alts from that guild bank alt
	-- Rule 3: Non-guild bank alts accept data from anyone
	local playerNorm = self:GetNormalizedPlayer()
	local isOwnData = playerNorm == norm
	local targetIsGuildBankAlt = self:IsGuildBankAlt(norm)
	local receiverIsGuildBankAlt = self:IsGuildBankAlt(playerNorm)

	-- Rule 1: Reject data about ourselves (we already have our own current data)
	if isOwnData then
		GBankClassic_Output:Debug("SYNC", "Rejected alt data about ourselves (we are the source of truth)")

		return ADOPTION_STATUS.UNAUTHORIZED
	end

	-- Rule 2: Guild bank alt protection - only apply if WE are a guild bank alt protecting our data
	-- Regular users should accept guild bank alt data from anyone
	if receiverIsGuildBankAlt and targetIsGuildBankAlt then
		-- We are a guild bank alt, and data is about a guild bank alt - only accept if sender is that guild bank alt
		if senderNorm ~= norm then
			-- Check timestamps before rejecting - allow if no existing data OR incoming is newer
			local incomingUpdatedAt = alt.version
			local existingUpdatedAt = existing and existing.version or nil
			local shouldAccept = false

			if not existing then
				shouldAccept = true
				GBankClassic_Output:Info("Accepting guild bank alt data from non-guild bank alt: no existing data for %s", norm)
			elseif incomingUpdatedAt and existingUpdatedAt and incomingUpdatedAt > existingUpdatedAt then
				shouldAccept = true
				GBankClassic_Output:Info("Accepting newer guild bank alt data: %s about %s (timestamp %d > %d)", senderNorm or "unknown", norm, incomingUpdatedAt, existingUpdatedAt)
			end

			if not shouldAccept then
				GBankClassic_Output:Debug("SYNC", "Rejected data about guild bank alt %s from %s (not newer: incoming=%s, existing=%s)", norm, senderNorm or "unknown", tostring(incomingUpdatedAt), tostring(existingUpdatedAt))

				return ADOPTION_STATUS.UNAUTHORIZED
			end

		else
			-- If we get here: senderNorm == norm (guild bank alt updating themselves) - ACCEPT
			GBankClassic_Output:Debug("SYNC", "Accepting data about guild bank alt %s from themselves", norm)
		end
	end

	-- Rule 3: Non-guild bank alts accept all data, non-guild bank alt data accepted from anyone
	-- Non-guild bank alt conflict resolution: newest wins (timestamped hash)
	local incomingUpdatedAt = alt.version
	local existingUpdatedAt = existing and existing.version or nil
	local existingHasContent = existing and self:HasAltContent(existing, norm) or false
	local incomingHasContent = self:HasAltContent(alt, norm)

	-- Allow incoming data if we have no existing data OR existing has no content
	local allowStaleBecauseMissingContent = (not existing) or (not existingHasContent and incomingHasContent)
	if allowStaleBecauseMissingContent then
		GBankClassic_Output:Debug("SYNC", "Accepting data for %s (no existing data or existing has no content)", norm)
	end
	if existingHasContent and not incomingHasContent then
		GBankClassic_Output:Debug("SYNC", "Rejecting empty data for %s because existing has content", norm)

		return ADOPTION_STATUS.STALE
	end

	-- If we already have data with mail, don't accept incomplete data from old clients
	local incomingHasMail = alt.mail ~= nil
	local existingHasMail = existing and existing.mail ~= nil
	if existing and existingHasMail and not incomingHasMail then
		GBankClassic_Output:Debug("SYNC", "Rejecting old client sync for %s (we have mail, incoming doesn't)", norm)

		return ADOPTION_STATUS.STALE
	end

	-- Only reject if we actually have content - if existing has no content, always accept incoming data
	if existing and existingHasContent and alt.inventoryHash and existing.inventoryHash and alt.inventoryHash == existing.inventoryHash then
		GBankClassic_Output:Debug("SYNC", "Hash match for %s (hash=%d) - data unchanged, rejecting as stale", norm, alt.inventoryHash)

		return ADOPTION_STATUS.STALE
	end

	if not targetIsGuildBankAlt and existing and incomingUpdatedAt and existingUpdatedAt and not allowStaleBecauseMissingContent then
		GBankClassic_Output:Debug("SYNC", "Timestamp staleness check for %s: incoming=%d, existing=%d, hasContent=%s", norm, incomingUpdatedAt, existingUpdatedAt, tostring(existingHasContent))
		if incomingUpdatedAt < existingUpdatedAt then
			GBankClassic_Output:Debug("SYNC", "Rejecting %s: incoming timestamp %d < existing %d", norm, incomingUpdatedAt, existingUpdatedAt)

			return ADOPTION_STATUS.STALE
		elseif incomingUpdatedAt == existingUpdatedAt then
			-- Tie-breaker: choose the one with more items
			local incomingCount = GBankClassic_Globals:Count(alt)
			local existingCount = GBankClassic_Globals:Count(existing)
			GBankClassic_Output:Debug("SYNC", "Timestamp tie for %s: incomingCount=%d, existingCount=%d", norm, incomingCount, existingCount)
			if incomingCount <= existingCount then
				GBankClassic_Output:Debug("SYNC", "Rejecting %s: incoming itemCount %d <= existing %d", norm, incomingCount, existingCount)

				return ADOPTION_STATUS.STALE
			end
		end
	end

	-- Legacy fallback: version-based staleness check
	if existing and alt.version ~= nil and existing.version ~= nil and alt.version < existing.version and not allowStaleBecauseMissingContent then
		return ADOPTION_STATUS.STALE
	end

	if self.hasRequested then
		if self.requestCount == nil then
			self.requestCount = 0
		else
			self.requestCount = self.requestCount - 1
		end
		if self.requestCount == 0 then
			self.hasRequested = false
			GBankClassic_Output:Info("Sync completed.")
		end
	end

	if not self.Info.alts then
		self.Info.alts = {}
	end
	self.Info.alts[norm] = alt
	GBankClassic_Output:Debug("MAIL", "Overwrote self.Info.alts[%s], mail field now: %s", norm, alt.mail and "EXISTS" or "GONE")
	GBankClassic_Output:Debug("SYNC", "Stored alt data for %s", norm)

	-- Reset search data flag so inventory UI rebuilds search index
	if GBankClassic_UI_Inventory then
		GBankClassic_UI_Inventory.searchDataBuilt = false
	end

	-- Reconstruct links for items (bandwidth optimization)
	if alt.items then
		self:ReconstructItemLinks(alt.items)
		throttledUIRefresh()
	end

	return ADOPTION_STATUS.ADOPTED
end

function Guild:HasAltData(alt)
	if not alt or type(alt) ~= "table" then
		return false
	end

	if alt.version and alt.version > 0 then
		return true
	end

	if alt.inventoryHash and alt.inventoryHash > 0 then
		return true
	end

	if alt.items and #alt.items > 0 then
		return true
	end

	return false
end

function Guild:HasAltContent(alt, altName)
	if not alt or type(alt) ~= "table" then
		GBankClassic_Output:Debug("DATABASE", "Type check for %s: not a table", altName or (alt and alt.name) or "unknown")

		return false
	end

	local hasItems = alt.items and next(alt.items)
    local result = hasItems
    GBankClassic_Output:Debug("DATABASE", "Content check for %s: items=%s (%d) => %s", altName or alt.name or "unknown", tostring(hasItems and "Y" or "N"), alt.items and #alt.items or 0, tostring(result))

	return result
end

-- /bank hello, or upon receipt of "gbank-h" (type = "reply")
-- Broadcast "gbank-h" to guild
-- Print output to ourselves
function Guild:Hello(type)
	local addon_data = self:GetVersion()
	local current_data = Guild.Info
	if addon_data and current_data then
		local roster_alts = ""
		local guild_bank_alts = ""
		local hello = "Hi! " .. self:GetNormalizedPlayer() .. " is using version " .. addon_data.addon .. "."
		if GBankClassic_Globals:Count(current_data.roster) > 0 and GBankClassic_Globals:Count(current_data.alts) > 0 then
			for _, v in pairs(current_data.roster.alts) do
				if roster_alts ~= "" then
					roster_alts = roster_alts .. ", "
				end
				roster_alts = roster_alts .. v
			end
			if roster_alts ~= "" then
				roster_alts = " (" .. roster_alts .. ")"
			end
			for k, _ in pairs(current_data.alts) do
				if guild_bank_alts ~= "" then
					guild_bank_alts = guild_bank_alts .. ", "
				end
				guild_bank_alts = guild_bank_alts .. k
			end
			if guild_bank_alts ~= "" then
				guild_bank_alts = " (" .. guild_bank_alts .. ")"
			end
			if current_data.roster.alts then
				hello = hello .. "\n"
				hello = hello .. "I know about " .. GBankClassic_Globals:Count(current_data.roster.alts) .. " guild bank alts" .. roster_alts .. " on the roster."
				hello = hello .. "\n"
				hello = hello .. "I have guild bank data from " .. GBankClassic_Globals:Count(current_data.alts) .. " alts" .. guild_bank_alts .. "."
			end
		else
			hello = hello .. " I know about 0 guild bank alts on the roster, and have guild bank data from 0 alts."
		end

		-- local pending_count = 0
		-- local fulfilled_count = 0
		-- local pending_banks = {}
		-- for _, req in pairs(current_data.requests or {}) do
		-- 	local clean = self:SanitizeRequest(req)
		-- 	if clean and clean.item and clean.item ~= "" then
		-- 		local qty = tonumber(clean.quantity or 0) or 0
		-- 		local fulfilled = tonumber(clean.fulfilled or 0) or 0
		-- 		if qty > 0 then
		-- 			local is_fulfilled = clean.status == "fulfilled" or clean.status == "complete" or fulfilled >= qty
		-- 			local is_pending = clean.status == "open" and fulfilled < qty
		-- 			if is_fulfilled then
		-- 				fulfilled_count = fulfilled_count + 1
		-- 			elseif is_pending then
		-- 				pending_count = pending_count + 1
		-- 				if clean.bank and clean.bank ~= "" then
		-- 					pending_banks[clean.bank] = true
		-- 				end
		-- 			end
		-- 		end
		-- 	end
		-- end

		-- local pending_bank_list = {}
		-- for name in pairs(pending_banks) do
		-- 	table.insert(pending_bank_list, name)
		-- end
		-- table.sort(pending_bank_list)

		-- hello = hello .. "\n" .. string.format("I have %d pending item requests and %d fulfilled item requests.", pending_count, fulfilled_count)
		-- if #pending_bank_list > 0 then
		-- 	hello = hello .. "\n" .. "Pending requests for bank alts: " .. table.concat(pending_bank_list, ", ") .. "."
		-- else
		-- 	hello = hello .. "\n" .. "Pending requests for bank alts: none."
		-- end

		if type ~= "reply" then
			GBankClassic_Output:Info(hello)
		end

		local data = GBankClassic_Core:SerializeWithChecksum(hello)
		if type ~= "reply" then
			GBankClassic_Core:SendCommMessage("gbank-h", data, "Guild", nil, "BULK")
		else
			GBankClassic_Core:SendCommMessage("gbank-hr", data, "Guild", nil, "BULK")
		end
	end
end

-- Wipe every online members' data: /bank wipeall (only by officers)
function Guild:Wipe(type)
    local guild = self:GetGuildName()
	if not guild and not self.canWeEditOfficerNote then
		return
	end

    local wipe = "I wiped all addon data from " .. guild .. "."
    self:Reset(guild)

	local data = GBankClassic_Core:SerializeWithChecksum(wipe)
    if type ~= "reply" then
        GBankClassic_Core:SendCommMessage("gbank-w", data, "Guild", nil, "BULK")
    else
        GBankClassic_Core:SendCommMessage("gbank-wr", data, "Guild", nil, "BULK")
    end
end

-- Wipe your own data: /bank wipe --
function Guild:WipeMine()
    local guild = self:GetGuildName()
	if not guild then
		return
	end

    self:Reset(guild)
end

-- /bank share + after Bank:Scan() + Events:OnShareTimer() every 3 minutes (TIMER_INTERVALS.VERSION_BROADCAST) + once every 30 seconds if UI inventory is empty
function Guild:Share(type)
    local guild = self:GetGuildName()
	if not guild then
		return
	end

	if self.Info and self.Info.name == guild then
		local normPlayer = self:GetNormalizedPlayer()
		local share = "I'm sharing my bank data. Share yours please."

		if not self.Info.alts[normPlayer] then
			if type ~= "reply" then
				share = "Share your bank data please."
			else
				share = "Nothing to share."
			end
		end

		-- Broadcast fingerprint for pull-based protocol containing if we have data in our roster: 
		--	addon and protocol data,
		--  guild name,
		--  whether the sender is a guild bank alt or not,
		--	roster version timestamp,
		-- 	version timestamp + inventory hash (bags, bank, money + mail)
		self:ShareAllGuildBankAltData()

		local data = GBankClassic_Core:SerializeWithChecksum(share)
		if type ~= "reply" then
			GBankClassic_Core:SendCommMessage("gbank-s", data, "Guild", nil, "NORMAL")
		else
			GBankClassic_Core:SendCommMessage("gbank-sr", data, "Guild", nil, "NORMAL")
		end
	end
end

-- Create and send latest version of the roster after enabling a new guild bank alt or /bank roster
function Guild:AuthorRosterData()
	if GBankClassic_Guild.isAnyoneAuthority then
	 	GBankClassic_Output:Info("All guild members can view officer notes. There's no point in broadcasting your roster. Aborting...")

		return
	end

    local rosterGuildBankAlts = self:GetRosterGuildBankAlts()
	if not GBankClassic_Guild.isAnyoneAuthority and GBankClassic_Guild.canWeViewOfficerNotes then
		self:SendRosterData()
		if rosterGuildBankAlts then
			local characterNames = {}
			for i = 1, #rosterGuildBankAlts do
				local guildBankAltName = rosterGuildBankAlts[i]
				table.insert(characterNames, guildBankAltName)
			end
			if #characterNames > 0 then
				GBankClassic_Output:Info("Sent updated roster containing the follow banks: " .. table.concat(characterNames, ", "))
			else
				GBankClassic_Output:Info("Sent empty roster.")
			end
		else
			GBankClassic_Output:Info("Sent empty roster.")
		end
	else
		GBankClassic_Output:Warn("You lack permissions to share the roster. Only players that can view officer notes are permitted.")

		return
	end
end

-- Share our fingerprint data
function Guild:ShareAllGuildBankAltData(priority)
	local guild = self:GetGuildName()
	if not guild then
		return
	end

	local version = self:GetVersion()
	if version == nil then
		return
	end

	local player = self:GetNormalizedPlayer()
	local isGuildBankAlt = player and self:IsGuildBankAlt(player) or false
	version.isGuildBankAlt = isGuildBankAlt

	local data = GBankClassic_Core:SerializeWithChecksum(version)
	GBankClassic_Core:SendCommMessage("gbank-dv2", data, "Guild", nil, priority or "NORMAL")
end