GBankClassic_Guild = {}

GBankClassic_Guild.Info = nil

-- Cache of online guild members (updated via GUILD_ROSTER_UPDATE)
-- Avoids stale data from GuildRoster() which only requests an update
GBankClassic_Guild.onlineMembers = {}

-- Cache of guild guild bank alts (updated via GUILD_ROSTER_UPDATE)
-- Prevents iterating through entire guild roster on every IsBank() call
GBankClassic_Guild.banksCache = nil

-- Temporary in-memory error storage for when Guild.Info is not initialized
GBankClassic_Guild.tempDeltaErrors = {
	lastErrors = {},
	failureCounts = {},
	notifiedAlts = {},
}

-- Migrate temporary errors to database once Guild.Info is initialized
function GBankClassic_Guild:MigrateTempErrors()
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
function GBankClassic_Guild:RecordDeltaError(altName, errorType, errorMessage)
	return GBankClassic_DeltaComms:RecordDeltaError(self.Info and self.Info.name, altName, errorType, errorMessage)
end

-- Reset failure count for an alt (called on successful sync)
function GBankClassic_Guild:ResetDeltaErrorCount(altName)
	return GBankClassic_DeltaComms:ResetDeltaErrorCount(self.Info and self.Info.name, altName)
end

-- Get recent delta errors
function GBankClassic_Guild:GetRecentDeltaErrors()
	return GBankClassic_DeltaComms:GetRecentDeltaErrors(self.Info and self.Info.name)
end

-- Get failure count for an alt
function GBankClassic_Guild:GetDeltaFailureCount(altName)
	return GBankClassic_DeltaComms:GetDeltaFailureCount(self.Info and self.Info.name, altName)
end

function GetPlayerWithNormalizedRealm(name)
	if string.match(name, "(.*)%-(.*)") then
		return name
	end
    
	return name .. "-" .. GetNormalizedRealmName("player")
end

local function NormalizePlayerName(name)
	if not name then
		return nil
	end

	if _G.type(name) ~= "string" then
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
	if GetPlayerWithNormalizedRealm then
		return GetPlayerWithNormalizedRealm(normalized)
	end

	-- Fallback: append current realm
	return normalized .. "-" .. GetNormalizedRealmName("player")
end
GBankClassic_Guild.NormalizePlayerName = NormalizePlayerName

function GBankClassic_Guild:NormalizeName(name)
	if not name then
		return nil
	end

	local normalize = self.NormalizePlayerName
	if normalize then
		return normalize(name)
	end

	return name
end

function GBankClassic_Guild:GetNormalizedPlayer(name)
	return self:NormalizeName(name or self:GetPlayer())
end

function GBankClassic_Guild:GetPlayer()
    if GBankClassic_Bank.player then
        return GBankClassic_Bank.player
    end

    -- The below code should never be called, but is here for safety
    local function try()
        local name, realm = UnitName("player"), GetNormalizedRealmName()
        if name and realm then
            GBankClassic_Bank.player = name .. "-" .. realm

            return true
        end
    end
    if try() then
        return GBankClassic_Bank.player
    end
    local count, max, delay = 0, 10, 15
	local timer
    timer = C_Timer.NewTicker(delay, function()
        count = count + 1
        if try() or count >= max then
            if timer then
                timer:Cancel()
            end
        end
    end)
  
    return nil
end

function GBankClassic_Guild:GetGuild()
    return IsInGuild("player") and GetGuildInfo("player") or nil
end

-- Check if a player is in the current guild roster
-- Returns true if the player is a member of the current guild
function GBankClassic_Guild:IsInCurrentGuildRoster(playerName)
	if not playerName then
		return false
	end

	if not IsInGuild() then
		return false
	end

	local normPlayer = self:NormalizeName(playerName)

    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
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

function GBankClassic_Guild:GetPlayerInfo(name)
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if playerRealm == name then
            return class
        end
    end

    return nil
end

function GBankClassic_Guild:Reset(name)
	if not name then
		return
	end

    GBankClassic_UI_Inventory:Close()
    GBankClassic_Database:Reset(name)
    self.Info = GBankClassic_Database:Load(name)
	self:MigrateTempErrors()
end

function GBankClassic_Guild:Init(name)
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
		self:MigrateTempErrors()
		self:RebuildGuildBankAltsRoster()

		return true
	end

    self:Reset(name)

    return true
end

function GBankClassic_Guild:CleanupMalformedAlts()
	if not self.Info or not self.Info.alts then
		return 0
	end

    local cleaned = 0
    for name, alt in pairs(self.Info.alts) do
        local remove = false
        if _G.type(alt) ~= "table" then
            remove = true
        else
            -- Ensure version is present, but malformed nested fields are problematic
            if alt.bank and _G.type(alt.bank) == "table" and alt.bank.items then
                for k, v in pairs(alt.bank.items) do
                    if not v or _G.type(v) ~= "table" or not v.ID then
                        alt.bank.items[k] = nil
                    end
                end
            end
            if alt.bags and _G.type(alt.bags) == "table" and alt.bags.items then
                for k, v in pairs(alt.bags.items) do
                    if not v or _G.type(v) ~= "table" or not v.ID then
                        alt.bags.items[k] = nil
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
			if alt.bank and next(alt.bank.items or {}) then
				hasData = true
			end
			if alt.bags and next(alt.bags.items or {}) then
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
            if _G.type(v) == "string" and v ~= "" then
                table.insert(new_alts, v)
            end
        end
        self.Info.roster.alts = new_alts
    end

    return cleaned
end

function GBankClassic_Guild:GetBanks()
	-- Return cached banks list if available
	if self.banksCache ~= nil then
		return self.banksCache
	end

	-- Build banks list
    local banks = {}
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, publicNote, officer_note, _, _, _ = GetGuildRosterInfo(i)
        if publicNote ~= nil or officer_note ~= nil then
            if string.match(publicNote, "(.*)gbank(.*)") or string.match(officer_note, "(.*)gbank(.*)") then
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
function GBankClassic_Guild:InvalidateBanksCache()
	self.banksCache = nil
end

-- Rebuild roster of guild bank alts from local guild notes (no network communication needed)
-- Called automatically on GUILD_ROSTER_UPDATE event
-- Note: this will be incomplete for players without access to view officer notes where gbank can also be maintained
function GBankClassic_Guild:RebuildGuildBankAltsRoster()
	if not self.Info then
		return
	end

	local banks = {}
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
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
		GBankClassic_Output:Debug("ROSTER", "Rebuilt banker roster from guild notes: %d bankers", #banks)
	end
end

function GBankClassic_Guild:GetRosterAlts()
	if not self.Info then
		return nil
	end

	local roster = self.Info.roster
	local list = {}

	if roster and roster.alts then
		for _, v in pairs(roster.alts) do
			if _G.type(v) == "string" and v ~= "" then
				table.insert(list, v)
			end
		end
	end

	if #list > 0 then
		return list
	end

	for name, alt in pairs(self.Info.alts or {}) do
		if _G.type(alt) == "table" then
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
function GBankClassic_Guild:FastFillMissingAlts()
	return GBankClassic_DeltaComms:FastFillMissingAlts(self.Info)
end

function GBankClassic_Guild:IsBank(player)
	if not player then
		return false
	end

    local banks = GBankClassic_Guild:GetBanks()
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

function GBankClassic_Guild:GetAnyGuildBankAlt()
	local banks = self:GetBanks()
	if not banks or #banks == 0 then
		return nil
	end

	-- Return the first guild bank alt (normalized)
	return self:NormalizeName(banks[1])
end

function GBankClassic_Guild:CheckVersion(version)
	if self.Info then
		return false
	end

	if version > self.Info.roster.version then
		return false
	end

	return true
end

function GBankClassic_Guild:GetVersion()
	if not self.Info then
		return nil
	end

    local GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
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

    for k, v in pairs(self.Info.alts) do
        if _G.type(v) == "table" and v.version then
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

local PENDING_SYNC_TTL_SECONDS = 180

function GBankClassic_Guild:MarkPendingSync(syncType, sender, name)
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
		if self.pending_sync.roster then
			self.pending_sync.roster[normSender] = now
		end
	elseif syncType == "alt" and name then
		local normName = self:NormalizeName(name)
		if self.pending_sync.alts and not self.pending_sync.alts[normName] then
			self.pending_sync.alts[normName] = {}
		end
		if self.pending_sync.alts and self.pending_sync.alts[normName] then
			self.pending_sync.alts[normName][normSender] = now
		end
	end
end

function GBankClassic_Guild:ConsumePendingSync(syncType, sender, name)
	if not syncType or not sender then
		return false
	end

	if not self.pending_sync then
		return false
	end

	local now = GetServerTime()
	local normSender = self:NormalizeName(sender)
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
		local normName = self:NormalizeName(name)
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

function GBankClassic_Guild:QueryRoster(player, version)
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

function GBankClassic_Guild:QueryAlt(player, name, version)
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

-- Pull-based query - WHISPER to guild bank alt if known, GUILD if unknown
function GBankClassic_Guild:QueryAltPullBased(name)
	if not name then
		return
	end

	local norm = self:NormalizeName(name)
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
	local cooldown = 15 -- seconds
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
		-- Guild bank alt known, seen recently (within 10 min), AND currently online - WHISPER directly
		GBankClassic_Output:DebugComm("SENDING WHISPER: gbank-r to %s for alt %s", guildBankAlt, norm)
		GBankClassic_Output:Debug("SYNC", "Pull-based query for %s (WHISPER to guild bank alt %s)", norm, guildBankAlt)
		GBankClassic_Core:SendWhisper("gbank-r", data, guildBankAlt, "NORMAL")
		self:MarkPendingSync("alt", guildBankAlt, norm)
	else
		-- No known guild bank alt, stale, or offline - broadcast on GUILD
		GBankClassic_Output:DebugComm("SENDING GUILD BROADCAST: gbank-r for alt %s (no online guild bank alt)", norm)
		GBankClassic_Output:Debug("SYNC", "Pull-based query for %s (GUILD broadcast, no online guild bank alt)", norm)
		GBankClassic_Core:SendCommMessage("gbank-r", data, "GUILD", nil, "NORMAL")
		self:MarkPendingSync("alt", nil, norm)
	end
end

function GBankClassic_Guild:SendRosterData()
	if not self.Info then
		return
	end

	local data = GBankClassic_Core:SerializeWithChecksum({ type = "roster", roster = self.Info.roster })
	GBankClassic_Core:SendCommMessage("gbank-d", data, "Guild", nil, "BULK")
end

function GBankClassic_Guild:ReceiveRosterData(roster)
	if not self.Info then
		return
	end

	if self.Info.roster.version and roster.version and roster.version < self.Info.roster.version then
		return
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

	self.Info.roster = roster
end

function GBankClassic_Guild:SenderHasGbankNote(sender)
	if not sender then
		return false
	end

    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, _, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
        if playerRealm then
            local norm = NormalizePlayerName(playerRealm)
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
function GBankClassic_Guild:RefreshOnlineCache()
	local startTime = debugprofilestop()

	self.onlineMembers = self.onlineMembers or {}
	wipe(self.onlineMembers)

    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		if name and isOnline then
			local normalized = self:NormalizeName(name)
			if self.onlineMembers and normalized then
				self.onlineMembers[normalized] = true
			end
		end
	end

	local count = 0
	for _ in pairs(self.onlineMembers) do
		count = count + 1
	end

	local duration = debugprofilestop() - startTime
	GBankClassic_Performance:RecordOperation("RefreshOnlineCache", duration)
	GBankClassic_Output:Debug("CACHE", "Refreshed online cache: %d members online", count)
	GBankClassic_Output:Debug("ROSTER", "[GUILD ROSTER] Refreshed online cache: %d members online", count)
end

-- Check if a player is currently online in the guild
-- Uses cached roster data updated via GUILD_ROSTER_UPDATE event
function GBankClassic_Guild:IsPlayerOnline(playerName)
	if not playerName then
		return false
	end

	local norm = self:NormalizeName(playerName)

	return self.onlineMembers[norm] == true
end

-- Compute minimal state summary for pull-based protocol
-- Returns {[itemID] = quantity} - no links, bags, slots, or metadata
-- ~800 bytes for 100 items vs 5-7KB for full data
function GBankClassic_Guild:ComputeStateSummary(name)
	if not name then
		return nil
	end

	local norm = self:NormalizeName(name)

	-- If we don't have data for this alt, return a "no data" summary
	if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
		return {
			version = 0,
			hash = nil,
			money = 0,
			items = {}
		}
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
		if not items then return end
		for _, item in ipairs(items) do
			if item and item.ID then
				local id = tostring(item.ID)
				local count = item.Count or 1
				summary.items[id] = (summary.items[id] or 0) + count
			end
		end
	end

	if alt.bank and alt.bank.items then
		addItems(alt.bank.items)
	end
	if alt.bags and alt.bags.items then
		addItems(alt.bags.items)
	end

	return summary
end

-- Send state summary to responder (step 4 of pull-based flow)
function GBankClassic_Guild:SendStateSummary(name, target)
	GBankClassic_Output:DebugComm("SendStateSummary CALLED: name=%s, target=%s", tostring(name), tostring(target))
	if not name or not target then
		GBankClassic_Output:DebugComm("SendStateSummary EARLY RETURN: missing params")

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
	GBankClassic_Output:DebugComm("SENDING STATE SUMMARY via WHISPER to %s for %s (%d bytes, hash=%s)", target, name, #data, tostring(summary.hash))
	if not GBankClassic_Core:SendWhisper("gbank-state", data, target, "NORMAL") then
		return
	end

	local itemCount = 0
	for _ in pairs(summary.items) do
        itemCount = itemCount + 1
    end

	GBankClassic_Output:Debug(
		"SYNC",
		"Sent state summary for %s to %s (%d unique items, %d bytes)",
		name,
		target,
		itemCount,
		string.len(data)
	)
end

-- Respond to state summary (step 5 & 6 of pull-based flow)
-- Compare requester's state with our data and send appropriate response
function GBankClassic_Guild:RespondToStateSummary(name, summary, requester)
	GBankClassic_Output:DebugComm("RespondToStateSummary CALLED: name=%s, requester=%s", tostring(name), tostring(requester))
	if not name or not summary or not requester then
		GBankClassic_Output:DebugComm("RespondToStateSummary EARLY RETURN: missing params")
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

	-- In delta mode, compare HASHES not versions
	local requesterHash = summary.hash or nil
	local currentHash = currentAlt.inventoryHash or nil

	GBankClassic_Output:DebugComm("RespondToStateSummary: %s requesterV=%d currentV=%d requesterHash=%s currentHash=%s", norm, requesterVersion, currentVersion, tostring(requesterHash), tostring(currentHash))

	-- Track last sent hash per guild+alt+requester
	self._lastSentState = self._lastSentState or {}
	local key = norm .. ":" .. requester
	local hashOrVersion = self:ShouldUseDelta() and (currentHash or 0) or currentVersion
	if self._lastSentState[key] == hashOrVersion then
		GBankClassic_Output:DebugComm("RespondToStateSummary: already sent data to %s for %s (hash/version unchanged), skipping", requester, norm)
		GBankClassic_Output:Debug("SYNC", "RespondToStateSummary: already sent data to %s for %s (hash/version unchanged), skipping", requester, norm)

		return
	end

	-- Delta mode - ONLY use hashes, no version fallback
	if self:ShouldUseDelta() then
		-- If current alt doesn't have a hash, send full data (might be from pre-hash version)
		if not currentHash then
			GBankClassic_Output:DebugComm("DELTA MODE: Current alt missing hash - sending full data for %s", norm)
			GBankClassic_Output:Debug("SYNC", "Sending full data to %s for %s (responder has no hash)", requester, norm)
			self:SendAltData(norm, requester)
			self._lastSentState[key] = hashOrVersion

			return
		end

		-- If requester has no hash (nil), they have no data - send everything
		if not requesterHash then
			GBankClassic_Output:DebugComm("DELTA MODE: REQUESTER HAS NO DATA (hash=nil) - sending full data for %s", norm)
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
			GBankClassic_Output:DebugComm("DELTA MODE: SENDING NO-CHANGE to %s for %s (hash match: %d)", requester, norm, currentHash)
			if not GBankClassic_Core:SendWhisper("gbank-nochange", data, requester, "NORMAL") then
				return
			end
			GBankClassic_Output:Debug("SYNC", "Sent no-change reply to %s for %s (hash=%d)", requester, norm, currentHash)
			self._lastSentState[key] = hashOrVersion

			return
		else
			-- Hashes differ - send data
			GBankClassic_Output:DebugComm("DELTA MODE: HASH MISMATCH - calling SendAltData for %s (requester=%d, current=%d)", norm, requesterHash, currentHash)
			GBankClassic_Output:Debug(
				"SYNC",
				"Sending data to %s for %s (hash mismatch: requester=%d, current=%d)",
				requester,
				norm,
				requesterHash,
				currentHash
			)
			self:SendAltData(norm, requester)
			self._lastSentState[key] = hashOrVersion

			return
		end
	end

	-- Legacy mode: compare versions only
	GBankClassic_Output:DebugComm("LEGACY MODE: Comparing versions")
	if requesterVersion == currentVersion then
		-- No changes - send no-change message
		local noChangeMsg = {
			type = "no-change",
			name = norm,
			version = currentVersion,
		}
		local data = GBankClassic_Core:SerializeWithChecksum(noChangeMsg)
		GBankClassic_Output:DebugComm("SENDING NO-CHANGE to %s for %s (version match)", requester, norm)
		if not GBankClassic_Core:SendWhisper("gbank-nochange", data, requester, "NORMAL") then
			return
		end
		GBankClassic_Output:Debug("SYNC", "Sent no-change reply to %s for %s (v%d)", requester, norm, currentVersion)
		self._lastSentState[key] = hashOrVersion

		return
	end

	-- Version mismatch - send full data
	GBankClassic_Output:Debug("SYNC", "Sending data to %s for %s (version mismatch: requester=%d, current=%d)", requester, norm, requesterVersion, currentVersion)
	self:SendAltData(norm, requester)
	self._lastSentState[key] = hashOrVersion
end

-- Strip link fields from items for transmission (bandwidth optimization)
-- Saves 60-80 bytes per item, receiver reconstructs with GetItemInfo()
function GBankClassic_Guild:StripItemLinks(items)
	if not items then
		return nil
	end

	local stripped = {}
	for _, item in ipairs(items) do
		table.insert(stripped, {
			ID = item.ID,
			Count = item.Count
		})
	end
	return stripped
end

-- Reconstruct link fields after receiving data
-- Calls GetItemInfo() to recreate links from ItemID
function GBankClassic_Guild:ReconstructItemLinks(items)
	if not items then
		return
	end

	local needsAsyncLoad = false

	for _, item in ipairs(items) do
		if item and item.ID and not item.Link then
			-- Try to get link from item cache
			local itemLink = select(2, GetItemInfo(item.ID))
			if itemLink then
				item.Link = itemLink
			else
				-- Item not in cache, use async loading
				needsAsyncLoad = true
				local itemObj = Item:CreateFromItemID(item.ID)
				if itemObj then
					itemObj:ContinueOnItemLoad(function()
						local link = itemObj:GetItemLink()
						if link then
							item.Link = link
							-- Refresh UI when link becomes available
							if GBankClassic_UI_Inventory and GBankClassic_UI_Inventory.isOpen then
								GBankClassic_UI_Inventory:DrawContent()
							end
						end
					end)
				end
			end
		end
	end

	-- If some links loaded immediately from cache, refresh UI now
	if not needsAsyncLoad and GBankClassic_UI_Inventory and GBankClassic_UI_Inventory.isOpen then
		GBankClassic_UI_Inventory:DrawContent()
	end
end

-- Strip links from entire alt structure before transmission
function GBankClassic_Guild:StripAltLinks(alt)
	if not alt then
		return nil
	end

	local stripped = {
		version = alt.version,
		money = alt.money,
		bank = {
			items = self:StripItemLinks(alt.bank and alt.bank.items),
			numSlots = alt.bank and alt.bank.numSlots,
			slotsFilled = alt.bank and alt.bank.slotsFilled
		},
		bags = {
			items = self:StripItemLinks(alt.bags and alt.bags.items),
			numSlots = alt.bags and alt.bags.numSlots,
			slotsFilled = alt.bags and alt.bags.slotsFilled
		}
	}
	return stripped
end

-- Strip links from delta changes structure (bandwidth optimization)
function GBankClassic_Guild:StripDeltaLinks(delta)
	return GBankClassic_DeltaComms:StripDeltaLinks(delta)
end

function GBankClassic_Guild:SendAltData(name, target)
	if not name then
		return
	end

	local norm = self:NormalizeName(name)
	if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
		return
	end

	local channel = target and "WHISPER" or "GUILD"
    local dest = target

	-- Version is ONLY set by Bank:Scan() when inventory actually changes
	-- No longer bump version here - that caused version drift from communication

	local currentAlt = self.Info.alts[norm]
	local useDelta = false
	local deltaData = nil
	local computeStart = debugprofilestop()

	-- Check if delta sync should be used
	-- No longer skip delta based on force flag (removed)
	if self:ShouldUseDelta() then
		deltaData = self:ComputeDelta(norm, currentAlt)
		if deltaData and self:DeltaHasChanges(deltaData) then
			local deltaSize = self:EstimateSize(deltaData)
			local fullSize = self:EstimateSize({ type = "alt", name = norm, alt = currentAlt })

			-- Use delta if significantly smaller OR if forced
			local forceDelta = FEATURES and FEATURES.FORCE_DELTA_SYNC
			if forceDelta or deltaSize < fullSize * PROTOCOL.MIN_DELTA_SIZE_RATIO then
				useDelta = true
				GBankClassic_Output:Debug(
					"DELTA",
					"✓ Delta selected for %s: %d bytes vs %d bytes full (%.1f%% size, %.0f bytes saved)%s",
					norm,
					deltaSize,
					fullSize,
					(deltaSize / fullSize) * 100,
					fullSize - deltaSize,
					forceDelta and " [FORCED]" or ""
				)
			else
				GBankClassic_Output:Debug(
					"DELTA",
					"✗ Delta too large for %s: %d bytes vs %d bytes full (%.1f%% > %.0f%% threshold)",
					norm,
					deltaSize,
					fullSize,
					(deltaSize / fullSize) * 100,
					PROTOCOL.MIN_DELTA_SIZE_RATIO * 100
				)
			end
		else
			if deltaData then
				GBankClassic_Output:Debug("DELTA", "No changes detected for %s (delta would be empty)", norm)
			else
				GBankClassic_Output:Debug("DELTA", "No previous snapshot for %s (first sync)", norm)
			end
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
		local serialized = deltaNoLinks
		GBankClassic_Output:Debug("DELTA", "Final delta size: %d bytes", string.len(serialized or ""))

		-- Track metrics
		if self.Info and self.Info.name then
			GBankClassic_Database:RecordDeltaSent(self.Info.name, string.len(serialized or ""))
		end

		-- Save delta to history for potential chain replay
		-- Use previous.version for baseVersion in history (delta no longer includes it)
		if self.Info and self.Info.name and deltaData.version and deltaData.changes then
			local previous = GBankClassic_Database:GetSnapshot(self.Info.name, norm)
			local baseVer = previous and previous.version or 0
			GBankClassic_Database:SaveDeltaHistory(
				self.Info.name,
				norm,
				baseVer,
				deltaData.version,
				deltaData
			)
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
			-- Use previous.version for baseVersion in history (delta no longer includes it)
			if self.Info and self.Info.name and deltaData.version and deltaData.changes then
				local previous = GBankClassic_Database:GetSnapshot(self.Info.name, norm)
				local baseVer = previous and previous.version or 0
				GBankClassic_Database:SaveDeltaHistory(
					self.Info.name,
					norm,
					baseVer,
					deltaData.version,
					deltaData
				)
			end
		end

		-- Send full sync based on protocol mode (user-configurable)
		local dataNoLinks

		-- New format (without links)
		local strippedAlt = self:StripAltLinks(currentAlt)
		dataNoLinks = GBankClassic_Core:SerializeWithChecksum({ type = "alt", name = norm, alt = strippedAlt })
		GBankClassic_Output:DebugComm("SENDING RESPONSE: gbank-d for %s (%d bytes)", norm, #dataNoLinks)
		if channel == "WHISPER" and dest then
			GBankClassic_Core:SendWhisper("gbank-d", dataNoLinks, dest, "NORMAL", OnChunkSent)
		else
			GBankClassic_Core:SendCommMessage("gbank-d", dataNoLinks, "Guild", nil, "BULK", OnChunkSent)
		end

		-- Log what was sent
		GBankClassic_Output:Debug(
			"SYNC",
			"Sent full sync for %s: gbank-d (%d bytes without links)",
			norm,
			string.len(dataNoLinks or "")
		)

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

local function GetSendResultName(result)
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
		local resultStr = GetSendResultName(sendResult)
		GBankClassic_Output:Debug("CHUNK","chunk %d/%d failed: %s", SendStats.chunksSent, totalChunks, resultStr, "Aborting send due to failure")
		SendStats.abort = true

		return
	end

	-- Show progress at start
	if SendStats.chunksSent == 1 then
		if not GBankClassic_Options:IsSyncProgressMuted() then
			GBankClassic_Output:Debug("CHUNK", "Sharing guild bank data: %d bytes in ~%d chunks...", totalBytes, totalChunks)
		end
	end

	-- Completion summary
	if bytesSent >= totalBytes then
		local elapsed = GetTime() - (SendStats.startTime or GetTime())
		local summary = string.format(
			"Send complete: %d chunks, %d bytes in %.1fs",
			SendStats.chunksSent, totalBytes, elapsed
		)
		if SendStats.failures > 0 or SendStats.throttled > 0 then
			summary = summary .. string.format(" | failures: %d, throttled: %d", SendStats.failures, SendStats.throttled)
		end

		if not GBankClassic_Options:IsSyncProgressMuted() then
			GBankClassic_Output:Debug("CHUNK", summary)
		end

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

function GBankClassic_Guild:ReceiveAltData(name, alt)
	return GBankClassic_Performance:Track("ReceiveAltData", function()
		if not self.Info then
			return ADOPTION_STATUS.IGNORED
		end

		-- Sanitize incoming alt data
		local function sanitizeAlt(a)
			if not a or _G.type(a) ~= "table" then
				return nil
			end
			if a.bank and _G.type(a.bank) == "table" and a.bank.items then
				for k, v in pairs(a.bank.items) do
					if not v or _G.type(v) ~= "table" or not v.ID then
						a.bank.items[k] = nil
					end
				end
			end
			if a.bags and _G.type(a.bags) == "table" and a.bags.items then
				for k, v in pairs(a.bags.items) do
					if not v or _G.type(v) ~= "table" or not v.ID then
						a.bags.items[k] = nil
					end
				end
			end
			return a
		end

		alt = sanitizeAlt(alt)
		if not alt then
			return ADOPTION_STATUS.INVALID
		end

		local norm = self:NormalizeName(name)
		local existing = self.Info.alts[norm]
		if existing and alt.version ~= nil and existing.version ~= nil and alt.version < existing.version then
			return ADOPTION_STATUS.STALE
		end

		-- Accept incoming if newer version
		-- If same version, accept the alt with more items
		local function itemCount(a)
			local c = 0
			if a and a.bank and a.bank.items then
				for _, v in pairs(a.bank.items) do
					if v and v.ID then
						c = c + 1
					end
				end
			end
			if a and a.bags and a.bags.items then
				for _, v in pairs(a.bags.items) do
					if v and v.ID then
						c = c + 1
					end
				end
			end
			return c
		end

		if existing and existing.version and alt.version and alt.version < existing.version then
			-- Incoming is older; ignore
			return ADOPTION_STATUS.STALE
		elseif existing and existing.version and alt.version and alt.version == existing.version then
			-- Tie-breaker: choose the one with more items
			if itemCount(alt) <= itemCount(existing) then
				return ADOPTION_STATUS.STALE
			end
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
		self.Info.alts[norm] = alt

		-- Reconstruct links for items (bandwidth optimization)
		if alt.bank and alt.bank.items then
			self:ReconstructItemLinks(alt.bank.items)
		end
		if alt.bags and alt.bags.items then
			self:ReconstructItemLinks(alt.bags.items)
		end

		-- Reset error count on successful full sync
		self:ResetDeltaErrorCount(norm)

		return ADOPTION_STATUS.ADOPTED
	end)
end

-- Protocol version helper functions

-- Check if delta sync should be used
function GBankClassic_Guild:ShouldUseDelta()
	return GBankClassic_DeltaComms:ShouldUseDelta()
end

-- Get peer protocol capabilities
function GBankClassic_Guild:GetPeerCapabilities(sender)
	return GBankClassic_DeltaComms:GetPeerCapabilities(self.Info and self.Info.name, sender)
end

-- Compare two items for equality
function GBankClassic_Guild:ItemsEqual(item1, item2)
	return GBankClassic_DeltaComms:ItemsEqual(item1, item2)
end

-- Extract only the fields that changed between two items
function GBankClassic_Guild:GetChangedFields(oldItem, newItem)
	return GBankClassic_DeltaComms:GetChangedFields(oldItem, newItem)
end

-- Build a slot-indexed lookup table from items array
function GBankClassic_Guild:BuildItemIndex(items)
	return GBankClassic_DeltaComms:BuildItemIndex(items)
end

-- Compute delta between old and new item sets
function GBankClassic_Guild:ComputeItemDelta(oldItems, newItems)
	return GBankClassic_DeltaComms:ComputeItemDelta(oldItems, newItems)
end

-- Compute full delta for an alt
function GBankClassic_Guild:ComputeDelta(name, currentAlt)
	return GBankClassic_DeltaComms:ComputeDelta(self.Info and self.Info.name, name, currentAlt)
end

-- Estimate serialized size of a data structure
function GBankClassic_Guild:EstimateSize(data)
	return GBankClassic_DeltaComms:EstimateSize(data)
end

-- Check if delta has any actual changes
function GBankClassic_Guild:DeltaHasChanges(delta)
	return GBankClassic_DeltaComms:DeltaHasChanges(delta)
end

-- Apply item delta to an items table
function GBankClassic_Guild:ApplyItemDelta(items, delta)
	return GBankClassic_DeltaComms:ApplyItemDelta(items, delta)
end

-- Apply a delta to alt data
function GBankClassic_Guild:ApplyDelta(name, deltaData, sender)
	return GBankClassic_DeltaComms:ApplyDelta(self.Info, name, deltaData, sender)
end

-- Request a chain of deltas to catch up from an old version
function GBankClassic_Guild:RequestDeltaChain(altName, fromVersion, toVersion, sender)
	return GBankClassic_DeltaComms:RequestDeltaChain(self.Info and self.Info.name, altName, fromVersion, toVersion, sender)
end

-- Apply a chain of deltas sequentially
function GBankClassic_Guild:ApplyDeltaChain(altName, deltaChain)
	return GBankClassic_DeltaComms:ApplyDeltaChain(self.Info, altName, deltaChain)
end

local function GetTableEntriesCount(a)
    local b = 0
    for c, d in pairs(a) do 
        b = b + 1 
    end

    return b 
end 

function GBankClassic_Guild:Hello(type)
	local addon_data = GBankClassic_Guild:GetVersion()
	local current_data = GBankClassic_Guild.Info
	if addon_data and current_data then
		local roster_alts = ""
		local guild_bank_alts = ""
		local hello = "Hi! " .. GBankClassic_Guild:GetPlayer() .. " is using version " .. addon_data.addon .. "."
		if GetTableEntriesCount(current_data.roster) > 0 and GetTableEntriesCount(current_data.alts) > 0 then
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
					.. GetTableEntriesCount(current_data.alts)
					.. " alts"
					.. guild_bank_alts
					.. "."
			end
		else
			hello = hello .. " I know about 0 guild bank alts on the roster, and have guild bank data from 0 alts."
		end

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

function GBankClassic_Guild:Wipe(type)
    local guild = GBankClassic_Guild:GetGuild()
    local CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
	if not guild and not CanViewOfficerNote() then
		return
	end

    local wipe = "I wiped all addon data from " .. guild .. "."
    GBankClassic_Guild:Reset(guild)

	local data = GBankClassic_Core:SerializeWithChecksum(wipe)
    if type ~= "reply" then
        GBankClassic_Core:SendCommMessage("gbank-w", data, "Guild", nil, "BULK")
    else
        GBankClassic_Core:SendCommMessage("gbank-wr", data, "Guild", nil, "BULK")
    end
end

function GBankClassic_Guild:WipeMine(type)
    local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end
    
    GBankClassic_Guild:Reset(guild)
end

function GBankClassic_Guild:Share(type)
    local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

    self.Info = GBankClassic_Database:Load(guild)
    local player = GBankClassic_Guild:GetPlayer()
	local normPlayer = GBankClassic_Guild:GetNormalizedPlayer(player)
    local share = "I'm sharing my bank data. Share yours please."

    if not self.Info.alts[normPlayer] then
        if type ~= "reply" then
            share = "Share your bank data please."
        else
            share = "Nothing to share."
        end
    end

	if self.Info.alts[normPlayer] and GBankClassic_Guild:IsBank(normPlayer) then
		GBankClassic_Guild:SendAltData(normPlayer)
	end

	-- Broadcast delta version with hashes for pull-based protocol
	-- Send BOTH legacy and delta version broadcasts
	if GBankClassic_Events and GBankClassic_Events.Sync then
		GBankClassic_Events:Sync()
	end
	if GBankClassic_Events and GBankClassic_Events.SyncDeltaVersion then
		GBankClassic_Events:SyncDeltaVersion()
	end

	local data = GBankClassic_Core:SerializeWithChecksum(share)
	if type ~= "reply" then
		-- Use NORMAL priority for share announcement so users are notified quickly
		-- Actual data transfers (deltas/snapshots) use BULK to avoid network spam
		GBankClassic_Core:SendCommMessage("gbank-s", data, "Guild", nil, "NORMAL")
	else
		-- TODO: decide to remove?
		GBankClassic_Core:SendCommMessage("gbank-sr", data, "Guild", nil, "NORMAL")
	end
end

function GBankClassic_Guild:AuthorRosterData()
	if not self.Info then
		return
	end

    local info = self.Info
    local isBank = false
    local banks = GBankClassic_Guild:GetBanks()
    local player = GBankClassic_Guild:GetPlayer()
    local CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
    if banks then
        for _, v in pairs(banks) do
            if v == player then
                isBank = true
                break
            end
        end
    end
    if isBank or CanViewOfficerNote() then
		if not info.roster then
			info.roster = {}
		end
		if info.roster then
			info.roster.alts = banks
			info.roster.version = GetServerTime()
			if not banks then
				info.roster.version = nil
			end
		end
		GBankClassic_Guild:SendRosterData()
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

function GBankClassic_Guild:SenderIsGM(player)
	if not player then
		return false
	end

	if not IsInGuild() then
		return false
	end

    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
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