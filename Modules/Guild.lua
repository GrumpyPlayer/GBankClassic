GBankClassic_Guild = GBankClassic_Guild or {}

local Guild = GBankClassic_Guild

Guild.Info = nil
Guild.onlineMembers = {}
Guild.banksCache = nil
Guild.tempDeltaErrors = {
	lastErrors = {},
	failureCounts = {},
	notifiedAlts = {},
}

local PENDING_SYNC_TTL_SECONDS = 180

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("wipe")
local wipe = upvalues.wipe
local upvalues = Globals.GetUpvalues("GetNormalizedRealmName", "UnitName", "NewTicker", "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GetAddOnMetadata", "GetServerTime", "GetTime", "GetItemInfo", "After", "debugprofilestop", "CanViewOfficerNote")
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
local debugprofilestop = upvalues.debugprofilestop
local CanViewOfficerNote = upvalues.CanViewOfficerNote
local upvalues = Globals.GetUpvalues("Item")
local Item = upvalues.Item

-- Migrate temporary errors to database once GBankClassic_Guild.Info is initialized
function Guild:MigrateTempErrors()
	if not self.Info or not self.Info.name then
		return
	end

	local db = GBankClassic_Database.db.factionrealm[self.Info.name]
	if not db or not db.deltaErrors then
		return
	end

	-- Migrate errors
	if #self.tempDeltaErrors.lastErrors > 0 then
		for i = #self.tempDeltaErrors.lastErrors, 1, -1 do
			table.insert(db.deltaErrors.lastErrors, 1, self.tempDeltaErrors.lastErrors[i])
		end
		-- Keep only recent errors (max 10)
		while #db.deltaErrors.lastErrors > 10 do
			table.remove(db.deltaErrors.lastErrors)
		end
	end

	-- Migrate failure counts
	for altName, count in pairs(self.tempDeltaErrors.failureCounts) do
		if not db.deltaErrors.failureCounts[altName] then
			db.deltaErrors.failureCounts[altName] = 0
		end
		db.deltaErrors.failureCounts[altName] = db.deltaErrors.failureCounts[altName] + count
	end

	-- Migrate notification flags
	for altName, flag in pairs(self.tempDeltaErrors.notifiedAlts) do
		if flag then
			db.deltaErrors.notifiedAlts[altName] = true
		end
	end

	-- Clear temp storage
	self.tempDeltaErrors.lastErrors = {}
	self.tempDeltaErrors.failureCounts = {}
	self.tempDeltaErrors.notifiedAlts = {}

	GBankClassic_Output:Debug("DATABASE", "Migrated temporary delta errors to database")
end

-- Record a delta error with details (persisted to database or temp storage)
function Guild:RecordDeltaError(altName, errorType, errorMessage)
	return GBankClassic_DeltaComms:RecordDeltaError(self.Info and self.Info.name, altName, errorType, errorMessage)
end

-- Reset failure count for an alt (called on successful sync)
function Guild:ResetDeltaErrorCount(altName)
	return GBankClassic_DeltaComms:ResetDeltaErrorCount(self.Info and self.Info.name, altName)
end

-- Get failure count for an alt
function Guild:GetDeltaFailureCount(altName)
	return GBankClassic_DeltaComms:GetDeltaFailureCount(self.Info and self.Info.name, altName)
end

local function getPlayerWithNormalizedRealm(name)
	if string.match(name, "(.*)%-(.*)") then
		return name
	end
    
	return name .. "-" .. GetNormalizedRealmName("player")
end

local function normalizePlayerName(name)
	if not name then
		return nil
	end

	if type(name) ~= "string" then
		name = tostring(name)
	end

	local trimmed = string.gsub(name, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return nil
	end

	-- Canonicalize hyphen spacing: convert "Name - Realm" or "Name- Realm" to "Name-Realm"
	local normalized = string.gsub(trimmed, "%s*%-%s*", "-")
	local left, right = string.match(normalized, "^(.-)%-(.-)$")
	if left and right then
		if left == "" then
			return nil
		end
		if string.lower(left) == "unknown" then
			return "Unknown"
		end
		if right ~= "" then
			return normalized
		end
		normalized = left
	end
	if string.lower(normalized) == "unknown" then
		return "Unknown"
	end

	-- If helper exists, use it
	if getPlayerWithNormalizedRealm then
		return getPlayerWithNormalizedRealm(normalized)
	end

	-- Fallback: append current realm
	return normalized .. "-" .. GetNormalizedRealmName("player")
end
Guild.NormalizePlayerName = normalizePlayerName

function Guild:NormalizeName(name)
	if not name then
		return nil
	end

	local normalize = self.NormalizePlayerName
	if normalize then
		return normalize(name)
	end

	return name
end

function Guild:GetNormalizedPlayer(name)
	return self:NormalizeName(name or self:GetPlayer())
end

function Guild:GetPlayer()
    -- Return cached player if available
    if GBankClassic_Bank.player then
        return GBankClassic_Bank.player
    end

    -- Try to get player info immediately
    local name, realm = UnitName("player"), GetNormalizedRealmName()
    if name and realm then
        GBankClassic_Bank.player = name .. "-" .. realm

        return GBankClassic_Bank.player
    end

    -- If player info not yet available, set up background retry (happens once)
    if not self._playerRetryScheduled then
        self._playerRetryScheduled = true
        local retryCount = 0
        local maxRetries = 20
        local timer
        timer = NewTicker(0.5, function()
            retryCount = retryCount + 1
            local name, realm = UnitName("player"), GetNormalizedRealmName()
            if name and realm then
                GBankClassic_Bank.player = name .. "-" .. realm
                timer:Cancel()
                self._playerRetryScheduled = false
            elseif retryCount >= maxRetries then
                timer:Cancel()
                self._playerRetryScheduled = false
            end
        end)
    end

    -- Always return a value (cached or fallback)
    return GBankClassic_Bank.player or "Unknown-Unknown"
end

function Guild:GetGuild()
    return IsInGuild("player") and GetGuildInfo("player") or nil
end

-- Check if a player is in the current guild roster
-- Returns true if the player is a member of the current guild
function Guild:IsInCurrentGuildRoster(playerName)
	if not playerName then
		return false
	end

	if not IsInGuild() then
		return false
	end

	local normPlayer = self:NormalizeName(playerName)
	for i = 1, GetNumGuildMembers() do
		local rosterName = GetGuildRosterInfo(i)
		if rosterName then
			local normRoster = self:NormalizeName(rosterName)
			if normRoster == normPlayer then
				return true
			end
		end
	end

	return false
end

function Guild:GetPlayerInfo(name)
    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if playerRealm == name then
            return class
        end
    end

    return nil
end

function Guild:Reset(name)
	if not name then
		return
	end

    GBankClassic_UI_Inventory:Close()
    GBankClassic_Database:Reset(name)
    self.Info = GBankClassic_Database:Load(name)
	-- self:EnsureRequestsInitialized()
	self:MigrateTempErrors()
end

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
		self:MigrateTempErrors()
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
			GBankClassic_Output:Debug("DATABASE", "Removing malformed bank entry for", name)
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
		local deltaSnapshots = self.Info.deltaSnapshots
		local deltaHistory = self.Info.deltaHistory
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
		cleanTable(deltaSnapshots)
		cleanTable(deltaHistory)
		cleanTable(alts)
    end

    return cleaned
end

function Guild:GetBanks()
	-- Return cached banks list if available
	if self.banksCache ~= nil then
		return self.banksCache
	end

	-- Build banks list
    local banks = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
        if publicNote ~= nil or officer_note ~= nil then
            if (publicNote and string.match(publicNote, "(.*)gbank(.*)")) or (officer_note and string.match(officer_note, "(.*)gbank(.*)")) then
                table.insert(banks, name)
            end
        end
    end

	-- Cache the result (nil if no banks found)
	if #banks == 0 then
		self.banksCache = nil
		return nil
	end

	self.banksCache = banks

	return banks
end

-- Invalidate the banks cache (call when guild roster changes)
function Guild:InvalidateBanksCache()
	self.banksCache = nil
end

-- Rebuild roster of guild bank alts from local guild notes (no network communication needed)
-- Called automatically on GUILD_ROSTER_UPDATE event
-- This will be incomplete for players without access to view officer notes where gbank can also be maintained
function Guild:RebuildGuildBankAltsRoster()
	if not self.Info then
		return
	end

	local banks = {}
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
		if name and (publicNote or officer_note) then
			if (publicNote and string.match(publicNote, "(.*)gbank(.*)")) or (officer_note and string.match(officer_note, "(.*)gbank(.*)")) then
				table.insert(banks, name)
			end
		end
	end

	-- Update roster.alts list (no version tracking needed - purely local)
	local oldRoster = table.concat(self.Info.roster.alts or {}, ",")
	local newRoster = table.concat(banks, ",")
	
	if oldRoster ~= newRoster then
		self.Info.roster.alts = banks
		GBankClassic_Output:Debug("ROSTER", "Rebuilt guild bank alt roster from guild notes: %d guild bank alts", #banks)
	end
end

function Guild:GetRosterAlts()
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

	for name, alt in pairs(self.Info.alts or {}) do
		if type(alt) == "table" then
			table.insert(list, name)
		end
	end

	if #list == 0 then
		return nil
	end

	return list
end

-- Request missing guild bank alts on UI open
-- Compares roster guild bank alts against local alt data and queries for missing guild bank alts
-- Use current guild roster instead of cached roster to prevent requesting data for guild bank alts from other guilds
function Guild:FastFillMissingAlts()
	return GBankClassic_DeltaComms:FastFillMissingAlts(self.Info)
end

function Guild:IsBank(player)
	if not player then
		return false
	end

    local banks = self:GetBanks()
	if banks == nil then
		return false
	end

	local normPlayer = self:NormalizeName(player) or player
    local isBank = false
    for _, v in pairs(banks) do
		local normBank = self:NormalizeName(v) or v
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

    local versionInfo = GetAddOnMetadata("GBankClassic", "Version"):gsub("%.", "")
    local versionNumber = tonumber(versionInfo)
    local data = {
        addon = versionNumber,
		protocol_version = PROTOCOL.VERSION,
		supports_delta = PROTOCOL.SUPPORTS_DELTA,
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
        if type(v) == "table" and v.version then
			-- Send hash only in delta-enabled mode (backwards compatibility)
			if PROTOCOL.SUPPORTS_DELTA and v.inventoryHash then
				data.alts[k] = {
					version = v.version,
					hash = v.inventoryHash,
				}
				GBankClassic_Output:Debug("SYNC", "Broadcasting %s: version=%d, hash=%d", k, v.version, v.inventoryHash)
			else
				-- Legacy format for old clients
				data.alts[k] = v.version
				GBankClassic_Output:Debug("SYNC", "Broadcasting %s: version=%d (no hash)", k, v.version)
			end
        end
    end

    return data
end

function Guild:MarkPendingSync(syncType, sender, name)
	if not syncType or not sender then
		return
	end

	local now = GetServerTime()
	local normSender = self:NormalizeName(sender)
	if not self.pending_sync then
		self.pending_sync = { roster = {}, alts = {} }
	end
	if not self.pending_sync.roster then
		self.pending_sync.roster = {}
	end
	if not self.pending_sync.alts then
		self.pending_sync.alts = {}
	end

	if syncType == "roster" then
		if self.pending_sync.roster and normSender then
			self.pending_sync.roster[normSender] = now
		end
	elseif syncType == "alt" and name then
		local normName = self:NormalizeName(name)
		if self.pending_sync.alts and normName and not self.pending_sync.alts[normName] then
			self.pending_sync.alts[normName] = {}
		end
		if self.pending_sync.alts and normName and normSender and self.pending_sync.alts[normName] then
			self.pending_sync.alts[normName][normSender] = now
		end
	end
end

function Guild:ConsumePendingSync(syncType, sender, name)
	if not syncType or not sender then
		return false
	end

	if not self.pending_sync then
		return false
	end

	local now = GetServerTime()
	local normSender = self:NormalizeName(sender) or ""
	if syncType == "roster" then
		local roster = self.pending_sync.roster
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
		local normName = self:NormalizeName(name) or ""
		local alts = self.pending_sync.alts and self.pending_sync.alts[normName]
		local ts = alts and alts[normSender]
		if ts and now - ts <= PENDING_SYNC_TTL_SECONDS then
			alts[normSender] = nil
			if next(alts) == nil then
				self.pending_sync.alts[normName] = nil
			end

			return true
		end
		if ts then
			alts[normSender] = nil
			if next(alts) == nil then
				self.pending_sync.alts[normName] = nil
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

	local norm = self:NormalizeName(name) or ""
	self.hasRequested = true
	if self.requestCount == nil then
		self.requestCount = 1
	else
		self.requestCount = self.requestCount + 1
	end

	-- Skip repeated triggers if last query < cooldown (per alt)
	self._lastQueryTime = self._lastQueryTime or {}
	local now = GetTime()
	local last = self._lastQueryTime[norm] or 0
	local cooldown = 15 -- Seconds
	if now - last < cooldown then
		GBankClassic_Output:Debug("SYNC", "QueryAltPullBased: Skipping %s due to cooldown (%.2fs remaining)", norm, cooldown - (now - last))

		return
	end
	self._lastQueryTime[norm] = now

	-- Check if we have an online guild bank alt
	local onlineGuildBankAlts = GBankClassic_Chat.online_guild_bank_alts or {}
	local guildBankAlt = nil
	local mostRecent = 0

	for sender, info in pairs(onlineGuildBankAlts) do
		if info.seen > mostRecent then
			mostRecent = info.seen
			guildBankAlt = sender
		end
	end

	-- Build request message
	local request = {
		type = "alt-request",
		name = norm,
		requester = self:GetNormalizedPlayer(),
	}

	local data = GBankClassic_Core:SerializeWithChecksum(request)

	if guildBankAlt and (GetServerTime() - mostRecent) < 600 and self:IsPlayerOnline(guildBankAlt) then
		-- Guild bank alt known, seen recently (within 10 min), and currently online - whisper directly
		GBankClassic_Output:DebugComm("Sending whisper: gbank-r to %s for alt %s", guildBankAlt, norm)
		GBankClassic_Output:Debug("SYNC", "Pull-based query for %s (whisper to guild bank alt %s)", norm, guildBankAlt)
		GBankClassic_Core:SendWhisper("gbank-r", data, guildBankAlt, "NORMAL")
		self:MarkPendingSync("alt", guildBankAlt, norm)
	else
		-- No known guild bank alt, stale, or offline - broadcast to guild
		GBankClassic_Output:DebugComm("Sending guild broadcast: gbank-r for alt %s (no online guild bank alt)", norm)
		GBankClassic_Output:Debug("SYNC", "Pull-based query for %s (guild broadcast, no online guild bank alt)", norm)
		GBankClassic_Core:SendCommMessage("gbank-r", data, "GUILD", nil, "NORMAL")
		self:MarkPendingSync("alt", nil, norm)
	end
end

function Guild:SendRosterData()
	if not self.Info then
		return
	end

	local data = GBankClassic_Core:SerializeWithChecksum({ type = "roster", roster = self.Info.roster })
	GBankClassic_Core:SendCommMessage("gbank-d", data, "Guild", nil, "BULK")
end

function Guild:SenderHasGbankNote(sender)
	if not sender then
		return false
	end

    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, _, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
        if playerRealm then
            local norm = self:NormalizeName(playerRealm)
            if norm == sender then
                if (publicNote and string.match(publicNote, "(.*)gbank(.*)")) or (officer_note and string.match(officer_note, "(.*)gbank(.*)")) then
                    return true
                end
            end
        end
    end

    return false
end

-- Refresh the online members cache from current guild roster
-- Called automatically when GUILD_ROSTER_UPDATE event fires
function Guild:RefreshOnlineCache()
	self.onlineMembers = self.onlineMembers or {}
	wipe(self.onlineMembers)

	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		if name and isOnline then
			local normalized = self:NormalizeName(name)
			if self.onlineMembers and normalized then
				self.onlineMembers[normalized] = true
			end
		end
	end

	local count = GBankClassic_Globals:Count(self.onlineMembers)
	GBankClassic_Output:Debug("ROSTER", "Refreshed online cache: %d members online", count)
end

-- Check if a player is currently online in the guild
-- Uses cached roster data updated via GUILD_ROSTER_UPDATE event
function Guild:IsPlayerOnline(playerName)
	if not playerName then
		return false
	end

	local norm = self:NormalizeName(playerName)

	return self.onlineMembers[norm] == true
end

-- Compute minimal state summary for pull-based protocol
-- Returns {[itemID] = quantity} - no links, bags, slots, or metadata
-- ~800 bytes for 100 items vs 5-7KB for full data
function Guild:ComputeStateSummary(name)
	if not name then
		return nil
	end

	local norm = self:NormalizeName(name)

	-- If we don't have data for this alt, return a "no data" summary
	if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
		return { version = 0, hash = nil, money = 0, items = {} }
	end

	local alt = self.Info.alts[norm]
	local summary = {
		version = alt.version or 0,
		hash = alt.inventoryHash or nil,
		money = alt.money or 0,
		items = {}
	}

	-- Aggregate items by ID (combine bank + bags)
	local function addItems(items)
		if not items then
			return
		end

		for _, item in ipairs(items) do
			if item and item.ID then
				local id = tostring(item.ID)
				local count = item.Count or 1
				summary.items[id] = (summary.items[id] or 0) + count
			end
		end
	end

	if alt.items then
		addItems(alt.items)
	end

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

	local itemCount = GBankClassic_Globals:Count(summary.items)
	GBankClassic_Output:Debug("SYNC", "Sent state summary for %s to %s (%d unique items, %d bytes)", name, target, itemCount, string.len(data))
end

-- Respond to state summary (step 5 & 6 of pull-based flow)
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

	-- In delta mode, compare hashes not versions
	local requesterHash = summary.hash or nil
	local currentHash = currentAlt.inventoryHash or nil

	GBankClassic_Output:DebugComm("RespondToStateSummary: %s requesterV=%d currentV=%d requesterHash=%s currentHash=%s", norm, requesterVersion, currentVersion, tostring(requesterHash), tostring(currentHash))

	-- Track last sent hash per guild+alt+requester
	self._lastSentState = self._lastSentState or {}
	local key = norm .. ":" .. requester
	local hashOrVersion = currentHash or 0
	if self._lastSentState[key] == hashOrVersion then
		GBankClassic_Output:DebugComm("RespondToStateSummary: already sent data to %s for %s (hash/version unchanged), skipping", requester, norm)
		GBankClassic_Output:Debug("SYNC", "RespondToStateSummary: already sent data to %s for %s (hash/version unchanged), skipping", requester, norm)

		return
	end

	-- Delta mode - only use hashes, no version fallback
	-- If current alt doesn't have a hash, send full data (might be from pre-hash version)
	if not currentHash then
		GBankClassic_Output:DebugComm("Delta mode: Current alt missing hash - sending full data for %s", norm)
		GBankClassic_Output:Debug("SYNC", "Sending full data to %s for %s (responder has no hash)", requester, norm)
		self:SendAltData(norm, requester)
		self._lastSentState[key] = hashOrVersion

		return
	end

	-- If requester has no hash (nil), they have no data - send everything
	if not requesterHash then
		GBankClassic_Output:DebugComm("Delta mode: Requestor has no data (hash=nil) - sending full data for %s", norm)
		GBankClassic_Output:Debug("SYNC", "Sending full data to %s for %s (requester has no data)", requester, norm)
		self:SendAltData(norm, requester)
		self._lastSentState[key] = hashOrVersion

		return
	end

	if requesterHash == currentHash then
		-- Hashes match - no changes needed
		local noChangeMsg = {
			type = "no-change",
			name = norm,
			version = currentVersion,
			hash = currentHash,
		}
		local data = GBankClassic_Core:SerializeWithChecksum(noChangeMsg)
		GBankClassic_Output:DebugComm("Delta mode: Sending no-change to %s for %s (hash match: %d)", requester, norm, currentHash)
		if not GBankClassic_Core:SendWhisper("gbank-nochange", data, requester, "NORMAL") then
			return
		end

		GBankClassic_Output:Debug("SYNC", "Sent no-change reply to %s for %s (hash=%d)", requester, norm, currentHash)
		self._lastSentState[key] = hashOrVersion

		return
	else
		-- Hashes differ - send data
		GBankClassic_Output:DebugComm("Delta mode: Hash mismatch, calling SendAltData for %s (requester=%d, current=%d)", norm, requesterHash, currentHash)
		GBankClassic_Output:Debug("SYNC", "Sending data to %s for %s (hash mismatch: requester=%d, current=%d)", requester, norm, requesterHash, currentHash)
		self:SendAltData(norm, requester)
		self._lastSentState[key] = hashOrVersion

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

		-- Preserve itemString for items with unique stats (suffixes, enchants, etc.)
		-- Extract from link if available: |Hitem:itemString|h[Name]|h
		if item.Link then
			local itemString = string.match(item.Link, "item:([^|]+)")
			if itemString then
				strippedItem.ItemString = itemString
			end
         
			if GBankClassic_Item:NeedsLink(item.Link) then
				strippedItem.Link = item.Link
			end
		end

		table.insert(stripped, strippedItem)
	end

	return stripped
end

-- Reconstruct link fields after receiving data
-- Calls GetItemInfo() to recreate links from ItemID or ItemString
-- Throttle UI refreshes to prevent stuttering when many items load async
local lastUIRefresh = 0
local function throttledUIRefresh()
	local now = GetTime()
	if now - lastUIRefresh < 0.5 then -- Throttle to max once per 0.5 seconds
		return
	end

	lastUIRefresh = now

	-- Only refresh if UI is actually open
	if GBankClassic_UI_Inventory and GBankClassic_UI_Inventory.isOpen then
		GBankClassic_UI_Inventory:DrawContent()
	end
	if GBankClassic_UI_Search and GBankClassic_UI_Search.isOpen then
		GBankClassic_UI_Search:DrawContent()
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
			-- If we have an ItemString, use it to reconstruct full link
			if item.ItemString then
				local itemName = GetItemInfo(item.ID)
				if itemName then
					item.Link = string.format("|cffffffff|Hitem:%s|h[%s]|h|r", item.ItemString, itemName)
					loadedAnyInBatch = true
				else
					-- Item not in cache - only start async if under limit
					if pendingAsyncLoads < MAX_CONCURRENT_ASYNC then
						pendingAsyncLoads = pendingAsyncLoads + 1
						local itemObj = Item:CreateFromItemID(item.ID)

						-- Check itemObj state
						GBankClassic_Output:Debug("ITEM", "ItemString item %d: itemObj=%s, itemObj.itemID=%s", item.ID or -1, tostring(itemObj), itemObj and tostring(itemObj.itemID) or "nil")

						if itemObj and itemObj.itemID and itemObj.itemID == item.ID then
							-- Item object is valid, try ContinueOnItemLoad with error protection
							GBankClassic_Output:Debug("ITEM", "ItemString item %d passed validation, calling ContinueOnItemLoad", item.ID)
							local success, err = pcall(function()
								itemObj:ContinueOnItemLoad(function()
									pendingAsyncLoads = pendingAsyncLoads - 1
									local name = itemObj:GetItemName()
									if name then
										item.Link = string.format("|cffffffff|Hitem:%s|h[%s]|h|r", item.ItemString, name)
										throttledUIRefresh()
									end
								end)
							end)
							if not success then
								GBankClassic_Output:Debug("ITEM", "ContinueOnItemLoad crashed for ItemString item %d: %s", item.ID, tostring(err))
								pendingAsyncLoads = pendingAsyncLoads - 1
							end
						else
							-- Item object is nil or corrupted, skip
							GBankClassic_Output:Debug("ITEM", "ItemString item %d failed validation, skipping", item.ID or -1)
							pendingAsyncLoads = pendingAsyncLoads - 1
						end
					else
						-- Too many pending, requeue for later
						table.insert(itemReconstructQueue, item)
					end
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
	if item.ItemString then
		local itemName = GetItemInfo(item.ID)
		if itemName then
			item.Link = string.format("|cffffffff|Hitem:%s|h[%s]|h|r", item.ItemString, itemName)
		end
	else
		local itemLink = select(2, GetItemInfo(item.ID))
		if itemLink then
			item.Link = itemLink
		end
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

-- Strip links from entire alt structure before transmission
function Guild:StripAltLinks(alt)
	if not alt then
		return nil
	end

	-- Strip links from aggregate items
	local strippedItems = self:StripItemLinks(alt.items)

	-- Also strip links from legacy bank/bags fields for backward compatibility
	-- Old clients can reconstruct links, new clients use alt.items
	local strippedBank = nil
	if alt.bank then
		strippedBank = {
			slots = alt.bank.slots,
			items = self:StripItemLinks(alt.bank.items)
		}
	end

	local strippedBags = nil
	if alt.bags then
		strippedBags = {
			slots = alt.bags.slots,
			items = self:StripItemLinks(alt.bags.items)
		}
	end

	local stripped = {
		version = alt.version,
		money = alt.money,
		inventoryHash = alt.inventoryHash,
		items = strippedItems,
		bank = strippedBank,
		bags = strippedBags,
		mail = alt.mail,
		ledger = alt.ledger
	}

	return stripped
end

-- Strip links from delta changes structure (bandwidth optimization)
function Guild:StripDeltaLinks(delta)
	return GBankClassic_DeltaComms:StripDeltaLinks(delta)
end

-- Ensure legacy fields (bank.items, bags.items) exist for backward compatibility with old clients
-- New clients use alt.items, but old clients need bank.items and bags.items
-- This also ensures mail items are included in legacy fields for old clients
function Guild:EnsureLegacyFields(alt)
	if not alt or not alt.items then
		return alt
	end

	-- If no legacy fields exist, reconstruct from alt.items
	if not alt.bank or not alt.bank.items then
		GBankClassic_Output:Debug("SYNC", "Reconstructing legacy fields from alt.items for %s", alt.name or "unknown")

		if not alt.bank then
			alt.bank = {}
		end
		alt.bank.items = {}
		-- Copy all items from alt.items to bank.items (includes mail)
		for _, item in ipairs(alt.items) do
			table.insert(alt.bank.items, item)
		end

		if not alt.bags then
			alt.bags = {}
		end
		if not alt.bags.items then
			alt.bags.items = {}
		end

		return alt
	end

	-- Legacy fields exist, but they don't include mail
	-- DO not modify alt.bank.items directly - it corrupts the data!
	-- Old clients will see mail items via alt.mail field, or can aggregate themselves
	-- If needed, create temporary copies with mail included only for transmission

	-- Ensure bags.items exists (even if empty)
	if not alt.bags then
		alt.bags = {}
	end
	if not alt.bags.items then
		alt.bags.items = {}
	end

	return alt
end

function Guild:SendAltData(name, target)
	if not name then
		return
	end

	local norm = self:NormalizeName(name)
	if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
		return
	end

	local channel = target and "WHISPER" or "GUILD"
    local dest = target

	-- Version is only set by Bank:Scan() when inventory actually changes
	-- No longer bump version here - that caused version drift from communication

	local currentAlt = self.Info.alts[norm]

	-- Ensure legacy fields exist for backward compatibility with old clients
	-- This ensures old clients that only read bank.items/bags.items still get data
	self:EnsureLegacyFields(currentAlt) -- Modifies in place, no need to reassign

	-- Log what we're about to send (all 3 arrays for backward compatibility)
	local itemsCount = currentAlt.items and #currentAlt.items or 0
	local bankCount = (currentAlt.bank and currentAlt.bank.items) and #currentAlt.bank.items or 0
	local bagsCount = (currentAlt.bags and currentAlt.bags.items) and #currentAlt.bags.items or 0
	GBankClassic_Output:Debug("SYNC", "Sending %s: alt.items=%d, alt.bank.items=%d (includes mail), alt.bags.items=%d", norm, itemsCount, bankCount, bagsCount)

	-- Log sample counts from what we're about to send
	if currentAlt.items and #currentAlt.items > 0 then
		local sampleItems = {}
		for i = 1, math.min(5, #currentAlt.items) do
			local item = currentAlt.items[i]
			if item then
				table.insert(sampleItems, string.format("%s:%d", item.ID or "?", item.Count or 0))
			end
		end
		GBankClassic_Output:Debug("SYNC", "First 5 items in alt.items being sent: %s", table.concat(sampleItems, ", "))
	end

	local useDelta = false
	local deltaData = nil
	local computeStart = debugprofilestop()

	-- Check if delta sync should be used
	-- No longer skip delta based on force flag (removed)
	deltaData = self:ComputeDelta(norm, currentAlt)
	if deltaData and self:DeltaHasChanges(deltaData) then
		local deltaSize = self:EstimateSize(deltaData)
		local fullSize = self:EstimateSize({ type = "alt", name = norm, alt = currentAlt })

		-- Always use delta if smaller
		if deltaSize < fullSize then
			useDelta = true
			GBankClassic_Output:Debug("DELTA", "✓ Delta selected for %s: %d bytes vs %d bytes full (%.1f%% size, %.0f bytes saved)", norm, deltaSize, fullSize, (deltaSize / fullSize) * 100, fullSize - deltaSize)
		else
			GBankClassic_Output:Debug("DELTA", "✗ Delta larger than full for %s: %d bytes vs %d bytes full (%.1f%%), using full sync", norm, deltaSize, fullSize, (deltaSize / fullSize) * 100)
		end
	else
		if deltaData then
			GBankClassic_Output:Debug("DELTA", "No changes detected for %s (delta would be empty)", norm)
		else
			GBankClassic_Output:Debug("DELTA", "No previous snapshot for %s (first sync)", norm)
		end
	end

	-- Record compute time if delta was computed
	if deltaData and self.Info and self.Info.name then
		local computeTime = debugprofilestop() - computeStart
		GBankClassic_Database:RecordDeltaComputeTime(self.Info.name, computeTime)
		GBankClassic_Output:Debug("DELTA", "Delta computation took %.2fms", computeTime)
	end

	if useDelta then
		-- Send delta
		local deltaNoLinks

		-- New format (without links) - saves 60-80 bytes per item
		local strippedDelta = self:StripDeltaLinks(deltaData)
		deltaNoLinks = GBankClassic_Core:SerializeWithChecksum(strippedDelta)
		if channel == "WHISPER" and dest then
			GBankClassic_Core:SendWhisper("gbank-dd", deltaNoLinks, dest, "NORMAL", OnChunkSent)
		else
			GBankClassic_Core:SendCommMessage("gbank-dd", deltaNoLinks, "Guild", nil, "BULK", OnChunkSent)
		end
		GBankClassic_Output:Debug("DELTA", "Sent delta update for %s via gbank-dd (no links)", norm)

		-- Track metrics using the size of the format we're using
		local totalSize = (deltaNoLinks and string.len(deltaNoLinks) or 0)
		GBankClassic_Output:Debug("DELTA", "Final delta size: %d bytes total", totalSize)

		-- Track metrics
		if self.Info and self.Info.name then
			GBankClassic_Database:RecordDeltaSent(self.Info.name, totalSize)
		end

		-- Save delta to history for potential chain replay
		if self.Info and self.Info.name and deltaData.version and deltaData.changes then
			local previous = GBankClassic_Database:GetSnapshot(self.Info.name, norm)
			local previousVersion = previous and previous.version or 0
			GBankClassic_Database:SaveDeltaHistory(self.Info.name, norm, previousVersion, deltaData.version, deltaData)
		end

		-- Save snapshot for next delta
		if self.Info and self.Info.name then
			GBankClassic_Database:SaveSnapshot(self.Info.name, norm, currentAlt)
		end
	else
		-- Fallback to full sync via gbank-d
		-- Record fallback reason if we computed delta but chose full sync
		if deltaData and self:DeltaHasChanges(deltaData) then
			if self.Info and self.Info.name then
				GBankClassic_Database:RecordFullSyncFallback(self.Info.name)
			end

			-- Save delta to history even when falling back to full sync
			-- This allows chain replay to work for offline players even when deltas were too large
			if self.Info and self.Info.name and deltaData.version and deltaData.changes then
				local previous = GBankClassic_Database:GetSnapshot(self.Info.name, norm)
				local previousVersion = previous and previous.version or 0
				GBankClassic_Database:SaveDeltaHistory(self.Info.name, norm, previousVersion, deltaData.version, deltaData)
			end
		end

		-- Send full sync based on protocol mode (user-configurable)
		local dataNoLinks

		-- New format (without links)
		local strippedAlt = self:StripAltLinks(currentAlt)
		dataNoLinks = GBankClassic_Core:SerializeWithChecksum({ type = "alt", name = norm, alt = strippedAlt })
		GBankClassic_Output:DebugComm("Sending response: gbank-d for %s (%d bytes)", norm, #dataNoLinks)
		if channel == "WHISPER" and dest then
			GBankClassic_Core:SendWhisper("gbank-d", dataNoLinks, dest, "NORMAL", OnChunkSent)
		else
			GBankClassic_Core:SendCommMessage("gbank-d", dataNoLinks, "Guild", nil, "BULK", OnChunkSent)
		end

		-- Log what was sent
		GBankClassic_Output:Debug("SYNC", "Sent full sync for %s: gbank-d (%d bytes without links)", norm, string.len(dataNoLinks or ""))

		-- Track metrics
		if self.Info and self.Info.name then
			local totalSize = (dataNoLinks and string.len(dataNoLinks) or 0)
			GBankClassic_Database:RecordFullSyncSent(self.Info.name, totalSize)
		end

		-- Save snapshot for next delta
		if self.Info and self.Info.name then
			GBankClassic_Database:SaveSnapshot(self.Info.name, norm, currentAlt)
		end
	end
end

-- Tracking stats for current send operation
local SendStats = {
	startTime = nil,
	lastBytes = 0,
	chunksSent = 0,
	failures = 0,
	throttled = 0,
}

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

function OnChunkSent(arg, bytesSent, totalBytes, sendResult)
	-- Detect start of a new send and auto-reset state
	if bytesSent > 0 and SendStats.lastBytes == 0 then
		SendStats.abort = false
		SendStats.startTime = nil
		SendStats.lastBytes = 0
		SendStats.chunksSent = 0
		SendStats.failures = 0
		SendStats.throttled = 0
	end

	-- Abort further processing on failure
	if SendStats.abort then
		return
	end

	-- Track chunk count (each callback = one chunk sent, ~254 bytes each)
	local bytesThisChunk = bytesSent - SendStats.lastBytes
	if bytesThisChunk > 0 then
		SendStats.chunksSent = SendStats.chunksSent + 1
	end
	SendStats.lastBytes = bytesSent

	-- Track failures
	local isSuccess = (sendResult == SEND_RESULT.Success or sendResult == true or sendResult == nil)
	local isThrottled = (sendResult == SEND_RESULT.AddonMessageThrottle or sendResult == SEND_RESULT.ChannelThrottle)
	if isThrottled then
		SendStats.throttled = SendStats.throttled + 1
	elseif not isSuccess then
		SendStats.failures = SendStats.failures + 1
	end

	-- Initialize start time on first chunk
	if SendStats.startTime == nil then
		SendStats.startTime = GetTime()
	end

	local totalChunks = math.ceil(totalBytes / 254)

	-- Print error on failed send
	if not isSuccess then
		local resultStr = getSendResultName(sendResult)
		GBankClassic_Output:Debug("CHUNK","chunk %d/%d failed: %s", SendStats.chunksSent, totalChunks, resultStr, "Aborting send due to failure")
		SendStats.abort = true

		return
	end

	-- Show progress at start
	if SendStats.chunksSent == 1 then
		GBankClassic_Output:Debug("CHUNK", "Sharing guild bank data: %d bytes in ~%d chunks...", totalBytes, totalChunks)
	end

	-- Completion summary
	if bytesSent >= totalBytes then
		local elapsed = GetTime() - (SendStats.startTime or GetTime())
		local summary = string.format("Send complete: %d chunks, %d bytes in %.1fs", SendStats.chunksSent, totalBytes, elapsed)
		if SendStats.failures > 0 or SendStats.throttled > 0 then
			summary = summary .. string.format(" | failures: %d, throttled: %d", SendStats.failures, SendStats.throttled)
		end

		GBankClassic_Output:Debug("CHUNK", summary)

		-- Warn on failures
		if SendStats.failures > 0 then
			GBankClassic_Output:Debug("CHUNK", "%d send failures occurred!", SendStats.failures)
		end

		-- Reset stats for next operation
		SendStats.abort = false
		SendStats.startTime = nil
		SendStats.lastBytes = 0
		SendStats.chunksSent = 0
		SendStats.failures = 0
		SendStats.throttled = 0
	end
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

		-- Sanitize bank items (array) - compact after removing invalids
		if a.bank and type(a.bank) == "table" and a.bank.items then
			local cleaned = {}
			for k, v in pairs(a.bank.items) do
				if v and type(v) == "table" and v.ID then
					table.insert(cleaned, v)
				end
			end
			a.bank.items = cleaned
		end

		-- Sanitize bag items (array) - compact after removing invalids
		if a.bags and type(a.bags) == "table" and a.bags.items then
			local cleaned = {}
			local beforeCount = 0
			local validCount = 0
			local invalidCount = 0
			for k, v in pairs(a.bags.items) do
				beforeCount = beforeCount + 1
				if v and type(v) == "table" and v.ID then
					table.insert(cleaned, v)
					validCount = validCount + 1
				else
					invalidCount = invalidCount + 1
					GBankClassic_Output:Debug("SYNC", "  Sanitize: invalid bag item at [%s]: v=%s, type=%s, ID=%s", tostring(k), tostring(v), type(v), v and tostring(v.ID) or "nil")
				end
			end
			GBankClassic_Output:Debug("SYNC", "Sanitized bags: before=%d, valid=%d, invalid=%d", beforeCount, validCount, invalidCount)
			a.bags.items = cleaned
		end

		return a
	end

	alt = sanitizeAlt(alt)
	if not alt then
		return ADOPTION_STATUS.INVALID
	end

	-- Log what we received
	GBankClassic_Output:Debug("SYNC", "ReceiveAltData for %s: alt.items=%d, alt.bank.items=%d, alt.bags.items=%d", name, GBankClassic_Globals:Count(alt.items), (alt.bank and alt.bank.items) and GBankClassic_Globals:Count(alt.bank.items) or 0, (alt.bags and alt.bags.items) and GBankClassic_Globals:Count(alt.bags.items) or 0)

	-- Backward compatibility: Compute alt.items from sources if missing
	-- This handles data from players who haven't rescanned after the aggregation update
	-- Previously, only bank and bags were synced (mail was local-only)

	-- Check if alt.items has any content (handles both array and key-value formats)
	local function hasAnyItems(items)
		if not items or type(items) ~= "table" then
			return false
		end

		return next(items) ~= nil
	end

	local needsReconstruction = not hasAnyItems(alt.items)

	if needsReconstruction then
		local bankItems = (alt.bank and alt.bank.items) or {}
		local bagItems = (alt.bags and alt.bags.items) or {}

		GBankClassic_Output:Debug("SYNC", "Reconstructing alt.items for %s: bank=%d, bags=%d", name, #bankItems, #bagItems)

		-- Aggregate bank + bags only (mail was never synced in old system)
		if #bankItems > 0 or #bagItems > 0 then
			local aggregated = GBankClassic_Item:Aggregate(bankItems, bagItems)
			alt.items = {}
			for _, item in pairs(aggregated) do
				table.insert(alt.items, item)
			end
			GBankClassic_Output:Debug("SYNC", "Reconstructed alt.items for %s: %d items from bank+bags", name, #alt.items)
		else
			GBankClassic_Output:Debug("SYNC", "No items to reconstruct for %s (bank and bags both empty)", name)
		end
	else
		-- alt.items exists, deduplicate and ensure array format
		-- Items may have duplicates from corrupted syncs, so aggregate to dedupe
		-- Log sample counts before deduplication
		if alt.items and #alt.items > 0 then
			local beforeSample = {}
			for i = 1, math.min(5, #alt.items) do
				local item = alt.items[i]
				if item then
					table.insert(beforeSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
				end
			end
			GBankClassic_Output:Debug("SYNC", "Before dedupe - First 5 items received: %s", table.concat(beforeSample, ", "))
		end

		-- Check if we need to merge mail items into alt.items
		-- Only merge if this is old data (no mailHash = created before mail sync existed)
		-- If mailHash exists, alt.items already includes mail from sender's Bank:Scan()
		local hasMailHash = alt.mailHash ~= nil
		local mailItems = (alt.mail and alt.mail.items) or {}
		local hasMailItems = mailItems and #mailItems > 0
		local needsMailMerge = hasMailItems and not hasMailHash

		if needsMailMerge then
			GBankClassic_Output:Debug("SYNC", "Old data: Merging %d mail items into alt.items for %s (no mailHash)", #mailItems, name)
			-- Aggregate alt.items with mail to ensure mail is included
			local aggregated = GBankClassic_Item:Aggregate(alt.items, mailItems)
			local arrayItems = {}
			for _, item in pairs(aggregated) do
				table.insert(arrayItems, item)
			end
			alt.items = arrayItems
			GBankClassic_Output:Debug("SYNC", "Merged alt.items for %s: %d items (including mail)", name, #alt.items)
		else
			if hasMailHash then
				GBankClassic_Output:Debug("SYNC", "New data: alt.items already includes mail (mailHash present) for %s", name)
			end
			-- No mail merge needed, just deduplicate
			local aggregated = GBankClassic_Item:Aggregate(alt.items, nil)
			local arrayItems = {}
			for _, item in pairs(aggregated) do
				table.insert(arrayItems, item)
			end
			alt.items = arrayItems
			GBankClassic_Output:Debug("SYNC", "alt.items exists for %s, deduplicated and converted to array: %d items", name, #alt.items)
		end

		-- Log sample counts after deduplication
		if alt.items and #alt.items > 0 then
			local afterSample = {}
			for i = 1, math.min(5, #alt.items) do
				local item = alt.items[i]
				if item then
					table.insert(afterSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
				end
			end
			GBankClassic_Output:Debug("SYNC", "After dedupe - First 5 items stored: %s", table.concat(afterSample, ", "))
		end
	end

	local norm = self:NormalizeName(name) or ""
	local existing = self.Info.alts[norm]
	local senderNorm = sender and self:NormalizeName(sender) or nil

	-- Guild bank alt protection logic
	-- Rule 1: Never accept data about yourself (you are source of truth)
	-- Rule 2: Guild bank alts only accept data about other guild bank alts from that guild bank alt
	-- Rule 3: Non-guild bank alts accept data from anyone
	local player = UnitName("player") .. "-" .. GetNormalizedRealmName()
	local playerNorm = self:NormalizeName(player)
	local isOwnData = playerNorm == norm
	local targetIsGuildBankAlt = self:IsBank(norm)
	local receiverIsGuildBankAlt = self:IsBank(playerNorm)

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
			GBankClassic_Output:Debug("SYNC", "Rejected data about guild bank alt %s from %s (guild bank alts only update themselves)", norm, senderNorm or "unknown")

			return ADOPTION_STATUS.UNAUTHORIZED
		end
		-- If we get here: senderNorm == norm (guild bank alt updating themselves) - ACCEPT
		GBankClassic_Output:Debug("SYNC", "Accepting data about guild bank alt %s from themselves", norm)
	end

	-- Rule 3: Non-guild bank alts accept all data, non-guild bank alt data accepted from anyone
	-- Version checking for all alts
	if existing and alt.version ~= nil and existing.version ~= nil and alt.version < existing.version then
		return ADOPTION_STATUS.STALE
	end

	if existing and existing.version and alt.version and alt.version < existing.version then
		-- Incoming is older; ignore
		return ADOPTION_STATUS.STALE
	elseif existing and existing.version and alt.version and alt.version == existing.version then
		-- Tie-breaker: always accept
	end

	-- Check against existing alt data, but only if version exists
	if self.Info.alts[name] and alt.version ~= nil and self.Info.alts[name].version ~= nil and alt.version < self.Info.alts[name].version then
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

	-- Preserve mail field from existing data when incoming sync lacks it
	-- Mail is now synced, but old clients don't include it in their syncs
	-- Preserve locally-scanned mail data to maintain visibility for new clients
	local existingMail = existing and existing.mail or nil
	local incomingHasMail = alt.mail ~= nil

	GBankClassic_Output:Debug("MAIL", "AdoptAltData for %s: existingMail=%s, incomingHasMail=%s", norm, existingMail and "YES" or "NO", tostring(incomingHasMail))
	if existingMail then
		GBankClassic_Output:Debug("MAIL", "  existingMail has %d items", existingMail.items and #existingMail.items or 0)
	end
	self.Info.alts[norm] = alt
	GBankClassic_Output:Debug("MAIL", "Overwrote self.Info.alts[%s], mail field now: %s", norm, alt.mail and "EXISTS" or "GONE")

	-- Restore preserved mail if we had it locally and incoming sync doesn't have it
	-- This handles backward compatibility: new clients preserve mail when receiving from old clients
	if existingMail and not incomingHasMail then
		self.Info.alts[norm].mail = existingMail
		local mailItemCount = existingMail.items and #existingMail.items or 0
		GBankClassic_Output:Debug("MAIL", "Restored mail for %s (%d items) - incoming sync lacked mail", norm, mailItemCount)
		GBankClassic_Output:Debug("MAIL", "Preserved mail data for %s (%d items, lastScan=%s) - backward compat", norm, mailItemCount, tostring(existingMail.lastScan))

		-- Re-aggregate alt.items to include the restored mail
		-- The incoming alt.items doesn't have mail, so we need to merge it back in
		if existingMail.items and #existingMail.items > 0 then
			GBankClassic_Output:Debug("MAIL", "Merging %d restored mail items into alt.items for %s", #existingMail.items, norm)
			local aggregated = GBankClassic_Item:Aggregate(self.Info.alts[norm].items, existingMail.items)
			self.Info.alts[norm].items = {}
			for _, item in pairs(aggregated) do
				table.insert(self.Info.alts[norm].items, item)
			end
			GBankClassic_Output:Debug("MAIL", "Re-aggregated alt.items for %s: %d items (including restored mail)", norm, #self.Info.alts[norm].items)
		end
	elseif incomingHasMail then
		GBankClassic_Output:Debug("MAIL", "Using incoming mail data for %s (new client sync)", norm)
	end

	-- Reset search data flag so inventory UI rebuilds search index (UI-008 fix)
	if GBankClassic_UI_Inventory then
		GBankClassic_UI_Inventory.searchDataBuilt = false
	end

	-- Reconstruct links for items (bandwidth optimization)
	if alt.items then
		self:ReconstructItemLinks(alt.bags.items)
	end

	-- Reset error count on successful full sync
	self:ResetDeltaErrorCount(norm)

	return ADOPTION_STATUS.ADOPTED
end

-- Protocol version helper functions

-- Get peer protocol capabilities
function Guild:GetPeerCapabilities(sender)
	return GBankClassic_DeltaComms:GetPeerCapabilities(self.Info and self.Info.name, sender)
end

-- Compare two items for equality
function Guild:ItemsEqual(item1, item2)
	return GBankClassic_DeltaComms:ItemsEqual(item1, item2)
end

-- Extract only the fields that changed between two items
function Guild:GetChangedFields(oldItem, newItem)
	return GBankClassic_DeltaComms:GetChangedFields(oldItem, newItem)
end

-- Build a slot-indexed lookup table from items array
function Guild:BuildItemIndex(items)
	return GBankClassic_DeltaComms:BuildItemIndex(items)
end

-- Compute delta between old and new item sets
function Guild:ComputeItemDelta(oldItems, newItems)
	return GBankClassic_DeltaComms:ComputeItemDelta(oldItems, newItems)
end

-- Compute full delta for an alt
function Guild:ComputeDelta(name, currentAlt)
	return GBankClassic_DeltaComms:ComputeDelta(self.Info and self.Info.name, name, currentAlt)
end

-- Estimate serialized size of a data structure
function Guild:EstimateSize(data)
	return GBankClassic_DeltaComms:EstimateSize(data)
end

-- Check if delta has any actual changes
function Guild:DeltaHasChanges(delta)
	return GBankClassic_DeltaComms:DeltaHasChanges(delta)
end

-- Apply item delta to an items table
function Guild:ApplyItemDelta(items, delta)
	return GBankClassic_DeltaComms:ApplyItemDelta(items, delta)
end

-- Apply a delta to alt data
function Guild:ApplyDelta(name, deltaData, sender)
	return GBankClassic_DeltaComms:ApplyDelta(self.Info, name, deltaData, sender)
end

-- Apply a chain of deltas sequentially
function Guild:ApplyDeltaChain(altName, deltaChain)
	return GBankClassic_DeltaComms:ApplyDeltaChain(self.Info, altName, deltaChain)
end

function Guild:Hello(type)
	local addon_data = self:GetVersion()
	local current_data = Guild.Info
	if addon_data and current_data then
		local roster_alts = ""
		local guild_bank_alts = ""
		local hello = "Hi! " .. self:GetPlayer() .. " is using version " .. addon_data.addon .. "."
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
				hello = hello
					.. "I know about "
					.. #current_data.roster.alts
					.. " guild bank alts"
					.. roster_alts
					.. " on the roster."
				hello = hello .. "\n"
				hello = hello
					.. "I have guild bank data from "
					.. GBankClassic_Globals:Count(current_data.alts)
					.. " alts"
					.. guild_bank_alts
					.. "."
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

function Guild:Wipe(type)
    local guild = self:GetGuild()
	if not guild and not CanViewOfficerNote() then
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

function Guild:WipeMine()
    local guild = self:GetGuild()
	if not guild then
		return
	end
    
    self:Reset(guild)
end

function Guild:Share(type, requestsMode)
    local guild = self:GetGuild()
	if not guild then
		return
	end

    self.Info = GBankClassic_Database:Load(guild)
    local player = self:GetPlayer()
	local normPlayer = self:GetNormalizedPlayer(player)
    local share = "I'm sharing my bank data. Share yours please."
	local mode = requestsMode or "snapshot"

    if not self.Info.alts[normPlayer] then
        if type ~= "reply" then
            share = "Share your bank data please."
        else
            share = "Nothing to share."
        end
    end

	if self.Info.alts[normPlayer] and self:IsBank(normPlayer) then
		self:SendAltData(normPlayer)
	end

	if mode == "snapshot" then
		-- -- Share current requests state alongside bank data so everyone stays in sync
		-- self:SendRequestsData()
	elseif mode == "version" then
		-- Lightweight ping; snapshots are sent only when queried.
		self:SendRequestsVersionPing()
	end

	-- Broadcast delta version with hashes for pull-based protocol
	-- Send both legacy and delta version broadcasts
	if GBankClassic_Events and GBankClassic_Events.Sync then
		GBankClassic_Events:Sync()
	end
	if GBankClassic_Events and GBankClassic_Events.SyncDeltaVersion then
		GBankClassic_Events:SyncDeltaVersion()
	end

	local data = GBankClassic_Core:SerializeWithChecksum(share)
	if type ~= "reply" then
		-- Use normal priority for share announcement so users are notified quickly
		-- Actual data transfers (deltas/snapshots) use bulk to avoid network spam
		GBankClassic_Core:SendCommMessage("gbank-s", data, "Guild", nil, "NORMAL")
	else
		GBankClassic_Core:SendCommMessage("gbank-sr", data, "Guild", nil, "NORMAL")
	end
end

function Guild:AuthorRosterData()
	if not self.Info then
		return
	end

    local info = self.Info
    local isBank = false
    local banks = self:GetBanks()
    local player = self:GetPlayer()
    if banks then
        for _, v in pairs(banks) do
            if v == player then
                isBank = true
                break
            end
        end
    end
    if isBank or CanViewOfficerNote() then
		if info and not info.roster then
			info.roster = {}
		end
		if info and info.roster then
			info.roster.alts = banks
			info.roster.version = GetServerTime()
			if not banks then
				info.roster.version = nil
			end
		end
		self:SendRosterData()
		if banks then
			local characterNames = {}
			for _, bankChar in pairs(banks) do
				table.insert(characterNames, bankChar)
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
		GBankClassic_Output:Warn("You lack permissions to share the roster.")

		return
	end
end

function Guild:SenderIsGM(player)
	if not player then
		return false
	end

	if not IsInGuild() then
		return false
	end

	for i = 1, GetNumGuildMembers() do
		local playerRealm, _, rankIndex = GetGuildRosterInfo(i)
		if playerRealm then
			local norm = self:NormalizeName(playerRealm)
			if rankIndex == 0 and norm == player then
				return true
			end
		end
	end
	
	return false
end