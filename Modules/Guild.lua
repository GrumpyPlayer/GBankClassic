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
local upvalues = Globals.GetUpvalues("GetNormalizedRealmName", "UnitName", "NewTicker", "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GetServerTime", "GetTime", "GetItemInfo", "After", "CanViewOfficerNote", "GuildControlGetNumRanks", "GuildControlGetRankFlags")
local GetNormalizedRealmName = upvalues.GetNormalizedRealmName
local UnitName = upvalues.UnitName
local NewTicker = upvalues.NewTicker
local IsInGuild = upvalues.IsInGuild
local GetGuildInfo = upvalues.GetGuildInfo
local GetNumGuildMembers = upvalues.GetNumGuildMembers
local GetGuildRosterInfo = upvalues.GetGuildRosterInfo
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
		self:RebuildGuildBankAltsRoster()

		return true
	end

	self:Reset(name)

	return true
end

function Guild:CleanupDatabase()
	local optionsSavedVariables = GBankClassic_Options.db.sv.global.bank
	if optionsSavedVariables.muteSyncProgress ~= nil then
		optionsSavedVariables.muteSyncProgress = nil
	end
	if optionsSavedVariables.peer_relay ~= nil then
		optionsSavedVariables.peer_relay = nil
	end

	local savedVariables = GBankClassic_Database.db.sv

    local legacyFactionData = savedVariables.faction
	if legacyFactionData then
		wipe(legacyFactionData)
	end

    local currentFactionRealmData = savedVariables.factionrealm
    local realmsToRemove = {}

    for factionRealm, factionRealmData in pairs(currentFactionRealmData) do
        local guildsToRemove = {}

        for guildName, guildData in pairs(factionRealmData) do
            local shouldRemove = false

            if guildName == "TestGuild" and guildData.guildProtocolVersions and guildData.guildProtocolVersions["V2User-TestRealm"] then
                shouldRemove = true
            end
            if guildName == "DeltaTest2" and guildData.deltaSnapshots and guildData.deltaSnapshots["DeltaAlt2"] then
                local item = guildData.deltaSnapshots["DeltaAlt2"].data.bags.items[1]
                if item and item.Link and item.Link:match("Test Item") then
                    shouldRemove = true
                end
            end
            if guildName == "ChainTest1" and guildData.deltaSnapshots then
                for alt, snapshot in pairs(guildData.deltaSnapshots) do
                    if snapshot.data and snapshot.data.items and snapshot.data.items[1] then
                        local item = snapshot.data.items[1]
                        if item.Link and item.Link:match("Test Item") then
                            shouldRemove = true
                            break
                        end
                    end
                end
            end

            if shouldRemove then
                table.insert(guildsToRemove, guildName)
			else
                if guildData.deltaErrors then
                    guildData.deltaErrors = nil
                end
                if guildData.deltaMetrics then
                    guildData.deltaMetrics = nil
                end
                if guildData.deltaHistory then
                    guildData.deltaHistory = nil
                end
                if guildData.deltaSnapshots then
                    guildData.deltaSnapshots = nil
                end
                if guildData.guildProtocolVersions then
                    guildData.guildProtocolVersions = nil
                end

                if guildData.alts then
                    for altName, altData in pairs(guildData.alts) do
                        if altData.bags then
                            altData.bags = nil
                        end
                        if altData.bank then
                            altData.bank = nil
                        end
                        if altData.mail then
                            altData.mail = nil
                        end
                        if altData.mailHash then
                            altData.mailHash = nil
                        end
                        if altData.inventoryUpdatedAt then
                            altData.inventoryUpdatedAt = nil
                        end
                    end
                end
            end
        end

        for _, guildName in ipairs(guildsToRemove) do
            factionRealmData[guildName] = nil
        end

        if next(factionRealmData) == nil then
            table.insert(realmsToRemove, factionRealm)
        end
    end

    for _, factionRealm in ipairs(realmsToRemove) do
        currentFactionRealmData[factionRealm] = nil
    end

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
			GBankClassic_Output:Debug("DATABASE", "Removing malformed guild bank alt entry for", name, "")
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
		local hasNewEntries, roster = updateRosterWithNewBankAlts(self.Info.roster.alts, guildBankAlts)
		self.Info.roster.alts = roster
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

	-- Notify others that we're ready
	self:Hello()

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
	GBankClassic_Output:Debug("SYNC", "RequestMissingGuildBankAltData: starting check of %d guild bank alts on the roster", #rosterAlts)

	for i = 1, #rosterAlts do
        local guildBankAltName = rosterAlts[i]
		local norm = self:NormalizeName(guildBankAltName) or guildBankAltName
		local localAlt = self.Info.alts and norm and self.Info.alts[norm]
		local hasEntry = localAlt ~= nil
		local hasContent = hasEntry and self:HasAltContent(localAlt, norm)
		local isSelf = norm == self.player

		GBankClassic_Output:Debug("SYNC", "RequestMissingGuildBankAltData: checking %s (hasEntry=%s, hasContent=%s, self=%s)", tostring(norm), tostring(hasEntry), tostring(hasContent), tostring(isSelf))
		if (not hasEntry or not hasContent) and not isSelf then
			table.insert(missing, norm)
		end
	end

	if #missing == 0 then
		GBankClassic_Output:Debug("SYNC", "RequestMissingGuildBankAltData: no missing data", #rosterAlts)

		return
	end

	GBankClassic_Output:Info("Requesting %d missing data (have data for %d/%d).", #missing, #rosterAlts - #missing, #rosterAlts)
	for _, norm in ipairs(missing) do
		self:QueryForGuildBankAltData(nil, norm)
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
		GBankClassic_Output:Debug("SYNC", "GetVersion: early exit because our roster is empty")

		return nil
	end

    local data = {
        addonVersionNumber = GBankClassic_Core.addonVersionNumber,
		protocolVersionNumber = PROTOCOL.VERSION,
		rosterVersionNumber = nil,
		alts = {},
    }

    if self.Info.name then
        data.guildName = self.Info.name
    end
    if self.Info.roster.version then
        data.rosterVersionNumber = self.Info.roster.version
    end

    for k, v in pairs(self.Info.alts) do
		if self:IsGuildBankAlt(k) then
			local hasContent = self:HasAltContent(v, k)
			if not hasContent then
				GBankClassic_Output:Debug("SYNC", "GetVersion: excluding %s from version broadcast (no content)", k)
			else
				if type(v) == "table" and v.version then
					if v.inventoryHash then
						data.alts[k] = {
							version = v.version,
							hash = v.inventoryHash
						}
						GBankClassic_Output:Debug("SYNC", "GetVersion: including %s in local version data (version=%d, hash=%d)", k, v.version, v.inventoryHash)
					else
						-- Legacy format for old clients
						data.alts[k] = v.version
						GBankClassic_Output:Debug("SYNC", "GetVersion: including %s in local version data (version=%d, no hash)", k, v.version)
					end
				end
			end
		else
			GBankClassic_Output:Debug("SYNC", "GetVersion: excluding %s (not in the roster)", k)
		end
    end

    return data
end

function Guild:IsQueryAllowed()
	if self.onlineMembersCount <= 1 then
		return false
	end

    self.hasRequested = true
    self.requestCount = (self.requestCount or 0) + 1

	return true
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

-- Query for roster data
function Guild:QueryForRosterData(target, theirRosterVersion)
	if not Guild:IsQueryAllowed() then
		return
	end

	self:MarkPendingSync("roster", target)

	GBankClassic_Output:Debug("SYNC", "Querying %s for roster (theirRosterVersion=%d)", GBankClassic_Chat:ColorPlayerName(target), theirRosterVersion)

	local payload = { type = "roster", version = theirRosterVersion }
	local data = GBankClassic_Core:SerializePayload(payload)
	if target and GBankClassic_Core:SendWhisper("gbank-r", data, target, "NORMAL") then
		self:MarkPendingSync("roster", target)

		return
	end

	-- Fallback: broadcast to the guild
	GBankClassic_Core:SendCommMessage("gbank-r", data, "Guild", nil, "NORMAL")
	self:MarkPendingSync("roster", "guild")
end

-- Query for guild bank alt to specific target or entire guild since self:RequestMissingGuildBankAltData() provides no target
function Guild:QueryForGuildBankAltData(target, altName)
	if not Guild:IsQueryAllowed() then
		return
	end

	if not target then
		local guildBankAlt = nil
		for member, _ in pairs(self:GetOnlineGuildBankAlts()) do
			if self:IsGuildBankAlt(member) and member ~= self:GetNormalizedPlayer() then
				if not guildBankAlt then
					guildBankAlt = member
					break
				end
			end
		end

		local onlinePeer = nil
		if not guildBankAlt then
			for guildMember in pairs(GBankClassic_Chat.guildMembersFingerprintData or {}) do
				if guildMember ~= self:GetNormalizedPlayer() and self:IsPlayerOnlineMember(guildMember) then
					if not onlinePeer then
						onlinePeer = guildMember
						break
					end
				end
			end
		end

		target = guildBankAlt or onlinePeer
	end

	local peerAddonVersionNumber = GBankClassic_Chat.guildMembersFingerprintData and GBankClassic_Chat.guildMembersFingerprintData[target] and GBankClassic_Chat.guildMembersFingerprintData[target].addonVersionNumber
	local isLegacy = false
	if target and peerAddonVersionNumber <= 254 then --TODO: fix hard coding
		isLegacy = true
	end

	GBankClassic_Output:Debug("SYNC", "Querying %s for %s (isLegacy=%s)", target and GBankClassic_Chat:ColorPlayerName(target) or "guild", GBankClassic_Chat:ColorPlayerName(altName), tostring(isLegacy))

	local payload
	if isLegacy then
		payload = { type = "alt", name = altName, player = target }
	else
		payload = { type = "alt-request", name = altName, requester = self:GetNormalizedPlayer() }
	end
	local data = GBankClassic_Core:SerializePayload(payload)
	if target and GBankClassic_Core:SendWhisper("gbank-r", data, target, "NORMAL") then
		self:MarkPendingSync("alt", target, altName)

		return
	end

	-- Fallback: broadcast to the guild
	GBankClassic_Core:SendCommMessage("gbank-r", data, "GUILD", nil, "NORMAL")
	self:MarkPendingSync("alt", "guild", altName)
end

function Guild:SendRosterData(target)
	if not self.Info or not self.Info.roster or not self.Info.roster.alts then
		GBankClassic_Output:Debug("ROSTER", "SendRosterData: skipped, no roster data available")

		return
	end

	local payload = { type = "roster", roster = self.Info.roster }
	local data = GBankClassic_Core:SerializePayload(payload)
	if target and GBankClassic_Core:SendWhisper("gbank-d", data, target, "BULK") then
		return
	end

	-- Fallback: broadcast to the guild
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

-- Send state summary to responder
function Guild:SendStateSummary(name, target)
	if not name or not target then
		GBankClassic_Output:Debug("SYNC", "SendStateSummary: early exit because of missing parameters")

		return
	end

	local summary = self:ComputeStateSummary(name)
	if not summary then
		GBankClassic_Output:Debug("SYNC", "SendStateSummary: early exit for %s (no data)", name)

		return
	end

	local payload = { type = "state-summary", name = name, summary = summary }
	local data = GBankClassic_Core:SerializePayload(payload)
	if not GBankClassic_Core:SendWhisper("gbank-state", data, target, "NORMAL") then
		return
	end
	GBankClassic_Output:Debug("SYNC", "SendStateSummary: sent for %s to %s (items=%d, %d bytes)", name, target, summary.items and #summary.items or 0, string.len(data))
end

-- Strip link fields from items for transmission (bandwidth optimization)
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

-- Queue system for batched item reconstruction
local itemReconstructQueue = {}
local isProcessingQueue = false
local pendingAsyncLoads = 0 -- Track number of pending async loads
local MAX_CONCURRENT_ASYNC = 3 -- Limit concurrent async operations
local BATCH_SIZE = 10 -- Limit the batch size
local BATCH_DELAY = 0.25 -- Delay between batches (slower = smoother)

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
									GBankClassic_UI:RequestRefresh()
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
		GBankClassic_UI:RequestRefresh()
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
local function createOnChunkSentCallback(altName, destination)
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
			GBankClassic_Output:Debug("CHUNK","Chunk %d/%d failed (%s). ", sendStats.chunksSent, totalChunks, resultStr, "Aborting send due to failure")
			sendStats.abort = true

			return
		end

		-- Show progress at start
		if sendStats.chunksSent == 1 then
			GBankClassic_Output:Debug("CHUNK", "Sharing data: %d bytes in ~%d chunks...", totalBytes, totalChunks)
		end

		-- Completion summary
		if bytesSent >= totalBytes then
			local elapsed = GetTime() - (sendStats.startTime or GetTime())
			local summary = string.format("Send complete: %d chunks, %d bytes in %.1fs", sendStats.chunksSent, totalBytes, elapsed)
			if sendStats.failures > 0 or sendStats.throttled > 0 then
				summary = summary .. string.format(" | failures: %d, throttled: %d", sendStats.failures, sendStats.throttled)
			end

			GBankClassic_Output:Debug("CHUNK", summary)
			if altName == GBankClassic_Guild.player then
				GBankClassic_Output:Response("Finished sending your latest data%s.", destination and string.format(" to %s", GBankClassic_Chat:ColorPlayerName(destination)))
			else
				GBankClassic_Output:Info("Finished sending data for %s%s.", GBankClassic_Chat:ColorPlayerName(altName), destination and string.format(" to %s", GBankClassic_Chat:ColorPlayerName(destination)))
			end

			-- Decrement peer send queue counter
			if Guild.pendingSendCount > 0 then
				Guild.pendingSendCount = Guild.pendingSendCount - 1
				GBankClassic_Output:Debug("CHUNK", "Send completed, queue now: %d/%d", Guild.pendingSendCount, Guild.MAX_PENDING_SENDS)
			end

			-- Warn on failures
			if sendStats.failures > 0 then
				GBankClassic_Output:Debug("CHUNK", "WARNING: %d send failures occurred!", sendStats.failures)
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

    if not self.Info or not self.Info.name then
        GBankClassic_Output:Debug("SYNC", "SendAltData: early exit because Guild.Info was not loaded for %s", name)

        return
    end

    if not self.Info.alts then
        GBankClassic_Output:Debug("SYNC", "SendAltData: early exit because Guild.Info.alts table does not exist for %s", name)

        return
    end

	local norm = self:NormalizeName(name) or name
    local currentAlt = self.Info.alts[norm]
    if not currentAlt then
        GBankClassic_Output:Debug("SYNC", "SendAltData: early exit because no data exists for guild bank alt %s (norm=%s)", name, norm)

         return
     end

    if not self:HasAltData(currentAlt) then
        GBankClassic_Output:Debug("SYNC", "SendAltData: early exit because no valid data exists for guild bank alt %s", norm)

        return
    end

	local channel = target and "WHISPER" or "GUILD"
    local dest = target or nil
	local itemsCount = currentAlt.items and #currentAlt.items or 0
	GBankClassic_Output:Debug("SYNC", "SendAltData: sending %d items for guild bank alt %s to %s", itemsCount, norm, dest or "guild")

	local onChunkSent = createOnChunkSentCallback(norm, dest)
	local payload = self:CraftDataPayload(currentAlt)
	local data = GBankClassic_Core:SerializePayload({ type = "alt", name = norm, alt = payload })
	if channel == "WHISPER" and dest then
		GBankClassic_Core:SendWhisper("gbank-d", data, dest, "NORMAL", onChunkSent)
	else
		GBankClassic_Core:SendCommMessage("gbank-d", data, "Guild", nil, "BULK", onChunkSent)
	end

	GBankClassic_Output:Debug("SYNC", "SendAltData: sent full data for %s (%d bytes)", norm, string.len(data or ""))
end

-- Only keep links for items with an enchant, suffix, or weapon/armor class before transmission
function Guild:CraftDataPayload(alt)
	if not alt then
		return nil
	end
	if not alt.version or alt.version == 0 then
		return
	end
	if not alt.inventoryHash or alt.inventoryHash == 0 then
		return
	end
	if #alt.items == 0 and alt.money == 0 then
		return
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

function Guild:ReceiveAltData(altName, incomingData, sender)
	if not self.Info then
        GBankClassic_Output:Debug("SYNC", "ReceiveAltData: early exit because Guild.Info was not loaded")

		return ADOPTION_STATUS.IGNORED
	end

	local function sanitizeData(data)
		if not data or type(data) ~= "table" then
			return nil
		end

		if data.items then
			local cleaned = {}
			for k, v in pairs(data.items) do
				if v and type(v) == "table" and v.ID then
					table.insert(cleaned, v)
				end
			end
			data.items = cleaned
		end

		return data
	end

	incomingData = sanitizeData(incomingData)
	if not incomingData then
        GBankClassic_Output:Debug("SYNC", "ReceiveAltData: early exit because of malformed items")

		return ADOPTION_STATUS.INVALID
	end

	GBankClassic_Output:Debug("SYNC", "ReceiveAltData: processing %d items for %s", GBankClassic_Globals:Count(incomingData.items), altName)

	if next(incomingData.items) then
		local aggregated = GBankClassic_Item:Aggregate(incomingData.items, nil)
		local arrayItems = {}
		for _, item in pairs(aggregated) do
			table.insert(arrayItems, item)
		end
		incomingData.items = arrayItems
		GBankClassic_Output:Debug("SYNC", "ReceiveAltData: deduplicated to %d items for %s", #incomingData.items, altName)
	end

	local existing = self.Info.alts[altName]
	local playerNorm = self:GetNormalizedPlayer()
	local isOwnData = playerNorm == altName

	if isOwnData then
		GBankClassic_Output:Debug("SYNC", "ReceiveAltData: rejected data about ourselves")

		return ADOPTION_STATUS.UNAUTHORIZED
	end

	local incomingVersion = incomingData.version
	local existingVersion = existing and existing.version or nil
	local existingHasContent = existing and self:HasAltContent(existing, altName) or false
	local incomingHasContent = self:HasAltContent(incomingData, altName)
	local targetIsGuildBankAlt = self:IsGuildBankAlt(altName)

	local allowStaleBecauseMissingContent = (not existing) or (not existingHasContent and incomingHasContent)
	if allowStaleBecauseMissingContent then
		GBankClassic_Output:Debug("SYNC", "ReceiveAltData: accepting data for %s (no existing data or existing has no content)", altName)
	end

	if existingHasContent and not incomingHasContent then
		GBankClassic_Output:Debug("SYNC", "ReceiveAltData: rejected empty data for %s (we have content)", altName)

		return ADOPTION_STATUS.STALE
	end

	if existing and existingHasContent and incomingData.inventoryHash and existing.inventoryHash and incomingData.inventoryHash == existing.inventoryHash then
		GBankClassic_Output:Debug("SYNC", "ReceiveAltData: rejected data as stale for %s (hashes match: incomingHash=%d)", altName, incomingData.inventoryHash)

		return ADOPTION_STATUS.STALE
	end

	if not targetIsGuildBankAlt and existing and incomingVersion and existingVersion and not allowStaleBecauseMissingContent then
		if incomingVersion < existingVersion then
			GBankClassic_Output:Debug("SYNC", "ReceiveAltData: rejecting %s (incomingVersion=%d < existingVersion=%d)", altName, incomingVersion, existingVersion)

			return ADOPTION_STATUS.STALE
		elseif incomingVersion == existingVersion then
			local incomingCount = GBankClassic_Globals:Count(incomingData)
			local existingCount = GBankClassic_Globals:Count(existing)
			if incomingCount <= existingCount then
				GBankClassic_Output:Debug("SYNC", "ReceiveAltData: rejecting %s (incoming itemCount %d <= existing %d)", altName, incomingCount, existingCount)

				return ADOPTION_STATUS.STALE
			end
		end
	end

	if existing and incomingData.version ~= nil and existing.version ~= nil and incomingData.version < existing.version and not allowStaleBecauseMissingContent then
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
		end
	end

	if not self.Info.alts then
		self.Info.alts = {}
	end
	self.Info.alts[altName] = incomingData
	GBankClassic_Output:Debug("SYNC", "ReceiveAltData: accepted and saved guild bank alt data for %s", altName)

	if GBankClassic_UI_Inventory then
		GBankClassic_UI_Inventory.searchDataBuilt = false
	end

	if incomingData.items then
		self:ReconstructItemLinks(incomingData.items)
		GBankClassic_UI:RequestRefresh()
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

	if alt.inventoryHash and alt.inventoryHash > 0 and alt.inventoryHash ~= 48095047 then
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
	local myVersionData = self:GetVersion()
	local currentData = Guild.Info
	if myVersionData and currentData then
		local helloParts = { "Hi! ", self:GetNormalizedPlayer(), " is using version ", myVersionData.addonVersionNumber, "." }
		local rosterCount = GBankClassic_Globals:Count(currentData.roster)
		local altsCount = GBankClassic_Globals:Count(currentData.alts)

		if rosterCount > 0 and altsCount > 0 then
			local rosterList = {}
			if currentData.roster.alts then
				for _, v in pairs(currentData.roster.alts) do
					table.insert(rosterList, v)
				end
			end
			local rosterAlts = #rosterList > 0 and " (" .. table.concat(rosterList, ", ") .. ")" or ""

			local guildBankList = {}
			for k, v in pairs(currentData.alts) do
				if v and v.items and GBankClassic_Globals:Count(v.items) > 0 then
					table.insert(guildBankList, k)
				end
			end
			local guildBankAlts = #guildBankList > 0 and " (" .. table.concat(guildBankList, ", ") .. ")" or ""

			local pluralRosterAlts = (rosterList ~= 1 and "s" or "")
			local pluralGuildBankAlts = (guildBankList ~= 1 and "s" or "")
			if currentData.roster.alts then
				table.insert(helloParts, "\n")
				table.insert(helloParts, "I know about " .. #rosterList .. " guild bank alt" .. pluralRosterAlts .. rosterAlts .. " on the roster.")
				table.insert(helloParts, "\n")
				table.insert(helloParts, "I have guild bank data from " .. #guildBankList .. " alt" .. pluralGuildBankAlts .. guildBankAlts .. ".")
			end
		else
			table.insert(helloParts, " I know about 0 guild bank alts on the roster, and have guild bank data from 0 alts.")
		end

		local hello = table.concat(helloParts)
		local data = GBankClassic_Core:SerializePayload(hello)
		if type ~= "reply" then
			GBankClassic_Output:Info(hello)
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

	local data = GBankClassic_Core:SerializePayload(wipe)
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
    local guildName = self:GetGuildName()
	if not guildName then
		return
	end

	if self.Info and self.Info.name == guildName then
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

		local data = GBankClassic_Core:SerializePayload(share)
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
	 	GBankClassic_Output:Response("All guild members can view officer notes. There's no point in broadcasting your roster. Aborted.")

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
				GBankClassic_Output:Response("Sent updated roster containing the follow banks: " .. table.concat(characterNames, ", ") .. ".")
			else
				GBankClassic_Output:Response("Sent empty roster.")
			end
		else
			GBankClassic_Output:Response("Sent empty roster.")
		end
	else
		GBankClassic_Output:Response("You lack permissions to share the roster. Only players that can view officer notes are permitted.")

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

	local data = GBankClassic_Core:SerializePayload(version)
	GBankClassic_Core:SendCommMessage("gbank-dv2", data, "Guild", nil, priority or "NORMAL")
end