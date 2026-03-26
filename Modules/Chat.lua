GBankClassic_Chat = GBankClassic_Chat or {}

local Chat = GBankClassic_Chat
local preDebugLogLevel = nil

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("time", "wipe")
local time = upvalues.time
local wipe = upvalues.wipe
local upvalues = Globals.GetUpvalues("GetClassColor", "IsInRaid", "IsInInstance", "GetServerTime", "GetAddOnMetadata")
local GetClassColor = upvalues.GetClassColor
local IsInRaid = upvalues.IsInRaid
local IsInInstance = upvalues.IsInInstance
local GetServerTime = upvalues.GetServerTime
local GetAddOnMetadata = upvalues.GetAddOnMetadata

local SHARES_COLOR = "|cff80bfffshares|r"
local QUERIES_COLOR = "|cffffff00queries|r"

function Chat:Init()
    GBankClassic_Core:RegisterChatCommand("bank", function(input)
        return self:ChatCommand(input)
    end)

    self.isAddonOutdated = false
	self.guildMembersFingerprintData = {}
	self.lastRosterSync = nil

	self.debounceConfig = {
		enabled = true,
		intervals = {
			["gbank-dv2"] = 3.0,            -- Fingerprint broadcast (contains versions and hashes for all guild bank alts the sender has data for)
			["gbank-d:roster"] = 2.0,       -- Full roster sync
			["gbank-d:alt"] = 2.5,          -- Full data sync for a given guild bank alt
			["gbank-state"] = 2.0,          -- State summary
			["gbank-nochange"] = 1.5,       -- No-change confirmations
            ["gbank-r"] = 1.0,         		-- Query
            ["gbank-rr"] = 1.0,         	-- Query replies
		},
	}
	self.debounceQueues = {
		multipleAlts = {},					-- For gbank-dv2: [altName] = { version, hash, sender, queuedAt }
		singularAlt = {},					-- For other messages: [key] = { version, hash, sender, data, message, queuedAt }
	}
	self.debounceTimers = {
		multipleAlts = nil,          		-- Single timer for gbank-dv2 processing
		singularAlt = {},       			-- Per-key timers for other messages
	}

	-- Fingerprint
	GBankClassic_Core:RegisterComm("gbank-dv2", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- Data (roster or guild bank alt)
	GBankClassic_Core:RegisterComm("gbank-d", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- State summary
	GBankClassic_Core:RegisterComm("gbank-state", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
    -- State no change
	GBankClassic_Core:RegisterComm("gbank-nochange", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- Query
    GBankClassic_Core:RegisterComm("gbank-r", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    -- Query reply
	GBankClassic_Core:RegisterComm("gbank-rr", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- Hello
    GBankClassic_Core:RegisterComm("gbank-h", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    -- Hello reply
    GBankClassic_Core:RegisterComm("gbank-hr", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)

    -- Share
    GBankClassic_Core:RegisterComm("gbank-s", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    -- Share reply
    GBankClassic_Core:RegisterComm("gbank-sr", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)

    -- Wipe
    GBankClassic_Core:RegisterComm("gbank-w", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    -- Wipe reply
    GBankClassic_Core:RegisterComm("gbank-wr", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
end

-- Helper for the sync status
local function formatSyncStatus(status)
	if status == ADOPTION_STATUS.ADOPTED then
		return "(newer, integrating)"
	end
	if status == ADOPTION_STATUS.STALE then
		return "(older, discarding)"
	end
	if status == ADOPTION_STATUS.INVALID then
		return "(invalid, ignoring)"
	end
	if status == ADOPTION_STATUS.UNAUTHORIZED then
		return "(unauthorized, ignoring)"
	end
	if status == ADOPTION_STATUS.IGNORED then
		return "(ignored)"
	end

	return ""
end

-- Helper to color player names
function Chat:ColorPlayerName(name)
	if not name or name == "" then
		return ""
	end

	local normalized = GBankClassic_Guild:NormalizeName(name) or name
	local class = GBankClassic_Guild:GetGuildMemberInfo(normalized)
	if class then
		local _, _, _, color = GetClassColor(class)
		if color then
			return string.format("|c%s%s|r", color, name)
		end
	end

	return string.format("|cff80bfff%s|r", name)
end

-- Helper to determine whether to accept data or not
function Chat:IsAltDataAllowed(sender, claimedNorm)
	if not GBankClassic_Guild:GetGuildMemberInfo(sender) then
		GBankClassic_Output:Debug("PROTOCOL", "Rejecting data from %s (not a guild member)", claimedNorm)

		return false
	end

	if not GBankClassic_Guild:IsGuildBankAlt(claimedNorm) then
		GBankClassic_Output:Debug("PROTOCOL", "Rejecting data for %s (not a guild bank alt)", claimedNorm)

		return false
	end

	return true
end

-- Debounce timer cleanup
function Chat:CancelAllDebounceTimers()
    if self.debounceTimers and self.debounceTimers.multipleAlts then
        GBankClassic_Core:CancelTimer(self.debounceTimers.multipleAlts)
        self.debounceTimers.multipleAlts = nil
    end

    if self.debounceTimers and self.debounceTimers.singularAlt then
        for _, timer in pairs(self.debounceTimers.singularAlt) do
            GBankClassic_Core:CancelTimer(timer)
        end
        wipe(self.debounceTimers.singularAlt)
    end

    if self.debounceQueues then
        wipe(self.debounceQueues.multipleAlts)
        wipe(self.debounceQueues.singularAlt)
    end
end

-- Generate debounce key for messages with a singular guild bank alt
function Chat:GetDebounceKey(prefix, data)
    if prefix == "gbank-d" then
        if data.type == "roster" then
            return "gbank-d:roster"
        elseif data.type == "alt" and data.name then
            return "gbank-d:alt:" .. data.name
        end
    elseif prefix == "gbank-state" and data.name then
        return "gbank-state:" .. data.name
    elseif prefix == "gbank-nochange" and data.name then
        return "gbank-nochange:" .. data.name
    end

    return prefix .. ":" .. (data.name or "unknown")
end

-- Extract version/hash from the payload of messages  a singular guild bank alt
function Chat:ExtractVersionHashFromSingularGuildBankAltPayload(prefix, data)
    if prefix == "gbank-dv2" then
        return nil, nil -- Extracted in QueueDebouncedMessageWithMultipleGuildBankAlts
	elseif prefix == "gbank-d" then
        if data.type == "roster" and data.roster then
            return data.roster.version, nil
        elseif data.type == "alt" and data.alt then
            return data.alt.version, data.alt.inventoryHash
        end
    elseif prefix == "gbank-state" and data.summary then
        return data.summary.version, data.summary.hash
    elseif prefix == "gbank-nochange" then
        return data.version, data.hash
    end

    return nil, nil
end

-- Check if incoming is better than existing
function Chat:ShouldReplaceQueuedData(existing, newVersion, newHash)
    if not existing then
        return true
    end

    -- Hash comparison, prefer higher version as tiebreaker
    if newHash and existing.hash then
        if newHash ~= existing.hash then
            if not newVersion or not existing.version then
                return true
            end

            return newVersion > existing.version
        end

        return false
    end

    -- Version comparison
    if newVersion and existing.version then
        return newVersion > existing.version
    elseif newVersion and not existing.version then
        return true
    end

    -- Fallback: last-wins
    return true
end

-- Queue debounced message containing data for multiple guild bank alts (gbank-dv2)
function Chat:QueueDebouncedMessageWithMultipleGuildBankAlts(sender, data)
    if not self.debounceConfig.enabled or not data.alts then
		self:ProcessFingerprint(data, sender)

        return true
    end

    -- Cancel existing timer to extend quiet window
    if self.debounceTimers.multipleAlts then
        GBankClassic_Core:CancelTimer(self.debounceTimers.multipleAlts)
        self.debounceTimers.multipleAlts = nil
    end

    -- Track sender metadata (addon version, protocol, roster version)
    if data.addon then
        if not self.guildMembersFingerprintData then
            self.guildMembersFingerprintData = {}
        end
		local guildName = data.name or nil
		local isGuildBankAlt = data.isGuildBankAlt or false
		local addonVersion = data.addon
		local protocolVersion = data.protocol_version or 1
		local rosterVersion = data.roster or nil
        self.guildMembersFingerprintData[sender] = {
            seen = GetServerTime(),
            isGuildBankAlt = isGuildBankAlt,
            addonVersion = addonVersion,
            protocolVersion = protocolVersion,
            rosterVersion = rosterVersion,
        }
		GBankClassic_Database:UpdatePeerProtocol(guildName, sender, protocolVersion)
		GBankClassic_Output:Debug("ROSTER", "Tracking member %s from %s with addon version %s (isGuildBankAlt=%s, protocolVersion=%s, rosterVersion=%s)", self:ColorPlayerName(sender), tostring(guildName), tostring(addonVersion), tostring(isGuildBankAlt), tostring(protocolVersion), tostring(rosterVersion))

		-- Addon version check
		local myVersionData = GBankClassic_Guild:GetVersion()
		if myVersionData and myVersionData.addon and data.addon > myVersionData.addon then
			if not self.isAddonOutdated then
				-- Only make the callout once per session
				self.isAddonOutdated = true
				GBankClassic_Output:Info("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived")
			end
		end
    end

    -- For each alt in payload, track best sender across all senders
    for altName, altInfo in pairs(data.alts) do
        local altNorm = GBankClassic_Guild:NormalizeName(altName) or altName
        local theirVersion = type(altInfo) == "table" and altInfo.version or altInfo
        local theirHash = type(altInfo) == "table" and altInfo.hash or nil

        local existing = self.debounceQueues.multipleAlts[altNorm]

        if self:ShouldReplaceQueuedData(existing, theirVersion, theirHash) then
            self.debounceQueues.multipleAlts[altNorm] = {
                version = theirVersion,
                hash = theirHash,
                sender = sender, -- This sender has best data for this alt
                queuedAt = GetServerTime(),
            }
            GBankClassic_Output:Debug("PROTOCOL", "Best sender for %s is now %s (theirVersion=%s, theirHash=%s)", self:ColorPlayerName(altNorm), self:ColorPlayerName(sender), tostring(theirVersion), tostring(theirHash))
        end
    end

    -- Schedule processing after quiet period
    local interval = self.debounceConfig.intervals["gbank-dv2"] or 3.0
    self.debounceTimers.multipleAlts = GBankClassic_Core:ScheduleTimer(function()
        self:ProcessDebouncedMessageWithMultipleGuildBankAlts()
    end, interval)

    GBankClassic_Output:Debug("PROTOCOL", "Queued processing of guild bank alt data from %s for %d guild bank alts (processing in %.1fs)", self:ColorPlayerName(sender), GBankClassic_Globals:Count(data.alts or {}), interval)

    return true
end

-- Process debounced message containing data for multiple guild bank alts
function Chat:ProcessDebouncedMessageWithMultipleGuildBankAlts()
    self.debounceTimers.multipleAlts = nil

    GBankClassic_Output:Debug("PROTOCOL", "Processing debounced guild bank alt data (alts=%d)", GBankClassic_Globals:Count(self.debounceQueues.multipleAlts))

    local queryCount = self:ProcessFingerprintAltData(self.debounceQueues.multipleAlts)
	local pluralQueries = (queryCount ~= 1 and "s" or "")
	GBankClassic_Output:Debug("PROTOCOL", "Queried data for %d guild bank alt%s from best sources.", queryCount, pluralQueries)

    wipe(self.debounceQueues.multipleAlts)
end

-- Queue debounced message containing data for a singular guild bank alt (gbank-d, gbank-state, gbank-nochange)
function Chat:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data)
    if not self.debounceConfig.enabled then
        return false
    end

    local key = self:GetDebounceKey(prefix, data)
    local version, hash = self:ExtractVersionHashFromSingularGuildBankAltPayload(prefix, data)
    local interval = self.debounceConfig.intervals[key] or self.debounceConfig.intervals[prefix] or 2.0
    local existing = self.debounceQueues.singularAlt[key]

    -- Check if we should replace existing queued data
    if not self:ShouldReplaceQueuedData(existing, version, hash) then
        GBankClassic_Output:Debug("PROTOCOL", "Discarded older %s for key `%s` (queued version=%d vs incoming version=%d)", prefix, key, existing and existing.version or 0, version or 0)

		return true
    end

    -- Cancel existing timer
    if self.debounceTimers.singularAlt[key] then
        GBankClassic_Core:CancelTimer(self.debounceTimers.singularAlt[key])
        self.debounceTimers.singularAlt[key] = nil
    end

    -- Store best version for this key
    self.debounceQueues.singularAlt[key] = {
        prefix = prefix,
        message = message,
        distribution = distribution,
        sender = sender,
        data = data,
        version = version,
        hash = hash,
        queuedAt = GetServerTime(),
    }

    -- Schedule processing
    self.debounceTimers.singularAlt[key] = GBankClassic_Core:ScheduleTimer(function()
        self:ProcessDebouncedMessageWithSingularGuildBankAlt(key)
    end, interval)

    GBankClassic_Output:Debug("PROTOCOL", "Queued processing of %s for %s (version=%s, hash=%s, processing in %.1fs)", prefix, key, tostring(version), tostring(hash), interval)

    return true
end

-- Process debounced message containing data for a singular guild bank alt
function Chat:ProcessDebouncedMessageWithSingularGuildBankAlt(key)
    local queued = self.debounceQueues.singularAlt[key]
    if not queued then return end

    -- Clear queue and timer
    self.debounceQueues.singularAlt[key] = nil
    self.debounceTimers.singularAlt[key] = nil

    GBankClassic_Output:Debug("PROTOCOL", "Processing debounced %s for %s (version=%s)", queued.prefix, key, tostring(queued.version))

    -- Route to appropriate handler
    if queued.prefix == "gbank-d" then
        if queued.data.type == "roster" then
            self:ProcessRosterData(queued.data, queued.sender)
        elseif queued.data.type == "alt" then
            self:ProcessGuildBankAltData(queued.data, queued.sender)
        end
    elseif queued.prefix == "gbank-state" then
        self:ProcessStateSummary(queued.data, queued.sender)
    elseif queued.prefix == "gbank-nochange" then
        self:ProcessStateNoChange(queued.data, queued.sender)
    end
end

-- Centralized sync function for both /sync command and UI opening
function Chat:PerformSync()
	GBankClassic_Guild:ShareAllGuildBankAltData("ALERT")
	GBankClassic_Guild:RequestMissingGuildBankAltData()
	-- GBankClassic_Guild:QueryRequestsIndex(nil, "ALERT")
end

-- Process the alt version and hash data from a fingerprint broadcast (gbank-dv2)
function Chat:ProcessFingerprintAltData(fingerprintAltData, sender)
	local queryCount = 0
    local ourPlayer = GBankClassic_Guild:GetNormalizedPlayer()

	for altName, altData in pairs(fingerprintAltData) do
        if altName ~= ourPlayer then
			local shouldQuery = false
			local ourAlt = GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[altName]
			local ourVersion = type(ourAlt) == "table" and ourAlt.version
			local ourHash = type(ourAlt) == "table" and ourAlt.inventoryHash or nil
			local theirVersion = type(altData) == "table" and altData.version or 0
			local theirHash = type(altData) == "table" and altData.hash or nil

			GBankClassic_Output:Debug("PROTOCOL", "Evaluating fingerprint from %s for %s (theirVersion=%d, theirHash=%d, ourVersion=%s, ourHash=%s)", self:ColorPlayerName(sender or altData.sender), self:ColorPlayerName(altName), tostring(theirVersion), tostring(theirHash), tostring(ourVersion), tostring(ourHash))

			if not ourVersion or theirVersion > ourVersion then
				shouldQuery = true
				GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: their version is newer, query", self:ColorPlayerName(altName))
			elseif theirHash and theirVersion == ourVersion then
				if not ourHash then
					shouldQuery = true
					GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: we don't have data, query", self:ColorPlayerName(altName))
				elseif theirHash ~= ourHash then
					GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: hash differs, don't query", self:ColorPlayerName(altName))
				else
					GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: hashes match, don't query", self:ColorPlayerName(altName))
				end
			else
				GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: their version is same or older, don't query", self:ColorPlayerName(altName))
			end

			if shouldQuery then
				GBankClassic_Guild:QueryForGuildBankAltData(sender or altData.sender, altName)
				queryCount = queryCount + 1
			end
		end
	end

	return queryCount
end

-- Process fingerprint broadcast (gbank-dv2)
function Chat:ProcessFingerprint(data, sender)
	local altCount = data.alts and GBankClassic_Globals:Count(data.alts)
	GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), SHARES_COLOR, "fingerprint", string.format("(%d guild bank alts)", altCount))

	local myVersionData = GBankClassic_Guild:GetVersion()
	if myVersionData then
		if data.name then
			if myVersionData.name ~= data.name then
				GBankClassic_Output:Debug("PROTOCOL", "Rejecting fingerprint from %s (ourGuild=%s, theirGuild=%s)", self:ColorPlayerName(sender), myVersionData.name, data.name)

				return
			end
		end

		if data.roster then
			if myVersionData.roster == nil or data.roster > myVersionData.roster then
				GBankClassic_Guild:QueryForRosterData(sender, data.roster)
			end
		end

		if data.alts then
			local queryCount = self:ProcessFingerprintAltData(data.alts, sender)
			local pluralQueries = (queryCount ~= 1 and "s" or "")
			GBankClassic_Output:Debug("PROTOCOL", "Queried data for %d guild bank alt%s.", queryCount, pluralQueries)
		end
	end
end

-- Process roster data (gbank-d type "roster")
function Chat:ProcessRosterData(data, sender)
    local isSenderAuthority = GBankClassic_Guild.guildMembersCache and GBankClassic_Guild.guildMembersCache[sender] and GBankClassic_Guild.guildMembersCache[sender].isAuthority
    if isSenderAuthority then
        GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), SHARES_COLOR, "roster data: we accept it")
        GBankClassic_Guild:ConsumePendingSync("roster", sender)
        GBankClassic_Guild.Info.roster = data.roster
    end
end

-- Process guild bank alt data (gbank-d type "alt")
function Chat:ProcessGuildBankAltData(data, sender)
    local altName = data.name

    local allowed = self:IsAltDataAllowed(sender, altName)
    if GBankClassic_Guild:ConsumePendingSync("alt", sender, altName) then
        allowed = true
    end

    local itemCount = data.alt and GBankClassic_Globals:Count(data.alt.items)
    local status = allowed and GBankClassic_Guild:ReceiveAltData(altName, data.alt, sender) or ADOPTION_STATUS.UNAUTHORIZED
    GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), SHARES_COLOR, "bank data about", self:ColorPlayerName(altName) .. ": we", allowed and "accept it" or "do not accept it", formatSyncStatus(status))

    if allowed and status == ADOPTION_STATUS.ADOPTED then
        local pluralItems = (itemCount ~= 1 and "s" or "")
        GBankClassic_Output:Info("Received data for %s from %s (%d item%s).", self:ColorPlayerName(altName), self:ColorPlayerName(sender), itemCount, pluralItems)
        GBankClassic_UI:RequestRefresh()
	elseif allowed then
		GBankClassic_Output:Debug("PROTOCOL", "Ignoring data for %s from %s (reason: %s).", self:ColorPlayerName(altName), self:ColorPlayerName(sender), status)
	else
		return
    end
end

-- Process state summary (gbank-state)
function Chat:ProcessStateSummary(data, sender)
    local altName = data.name
    local summary = data.summary

    local allowed = self:IsAltDataAllowed(sender, altName)
    if GBankClassic_Guild:ConsumePendingSync("alt", sender, altName) then
        allowed = true
    end

    local normalizedSummary = {}
    for k, v in pairs(summary) do
        normalizedSummary[k] = v
    end
    if summary.items then
        local itemsArray = {}
        for itemId, itemCount in pairs(summary.items) do
            table.insert(itemsArray, { ID = tonumber(itemId), Count = itemCount })
        end
        normalizedSummary.items = itemsArray
    end

    local itemCount = GBankClassic_Globals:Count(normalizedSummary.items)
    local status = allowed and GBankClassic_Guild:ReceiveAltData(altName, normalizedSummary, sender) or ADOPTION_STATUS.UNAUTHORIZED
    GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), SHARES_COLOR, "bank data (link-less) about", self:ColorPlayerName(altName) .. ": we", allowed and "accept it" or "do not accept it", formatSyncStatus(status))

    if allowed and status == ADOPTION_STATUS.ADOPTED then
		local pluralItems = (itemCount ~= 1 and "s" or "")
		GBankClassic_Output:Info("Received data (link-less) for %s from %s (%d item%s).", self:ColorPlayerName(altName), self:ColorPlayerName(sender), itemCount, pluralItems)
	elseif allowed then
		GBankClassic_Output:Debug("PROTOCOL", "Ignoring data (link-less) for %s from %s (reason: %s).", self:ColorPlayerName(altName), self:ColorPlayerName(sender), status)
	else
		return
    end
end

-- Process no-change (gbank-nochange)
function Chat:ProcessStateNoChange(data, sender)
    local altName = data.name
    local version = data.version or 0

    GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), SHARES_COLOR, "no changes for", self:ColorPlayerName(altName), string.format("(version=%d)", version))
    GBankClassic_Guild:ConsumePendingSync("alt", sender, altName)
    if GBankClassic_Guild.hasRequested then
        GBankClassic_Guild.requestCount = (GBankClassic_Guild.requestCount or 0) - 1
        if GBankClassic_Guild.requestCount == 0 then
            GBankClassic_Guild.hasRequested = false
        end
    end
end

-- Main communication handler
function Chat:OnCommReceived(prefix, message, distribution, sender)
	local prefixDesc = COMM_PREFIX_DESCRIPTIONS[prefix] or "(Unknown)"
	local player = GBankClassic_Guild:GetNormalizedPlayer()
	sender = GBankClassic_Guild:NormalizeName(sender) or sender

	if not GBankClassic_Guild.player and not GBankClassic_Guild.addonVersion then
		GBankClassic_Output:Debug("COMMS", "<", "(ignoring)", prefix, prefixDesc, "(not ready yet)")

		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("COMMS", "<", "(suppressing)", prefix, prefixDesc, "from", self:ColorPlayerName(sender), "(in instance or raid)")

		return
	end

	if player == sender then
		GBankClassic_Output:Debug("COMMS", "<", "(ignoring)", prefix, prefixDesc, "(our own)")

		return
	end

	local success, data = GBankClassic_Core:DeSerializePayload(message)
	if not success then
		GBankClassic_Output:Debug("COMMS", "<", "(error)", prefix, prefixDesc, "from", self:ColorPlayerName(sender), "(failed to deserialize, error=" .. tostring(data) .. ")")

        return
	end

	-- GBankClassic_Output:Debug("COMMS", "<", prefix, prefixDesc, "via", string.upper(distribution), "from", self:ColorPlayerName(sender), "(" .. (#message or 0) .. " bytes" .. (data.type and ", type=" .. tostring(data and data.type) or "") ..")")
    local tablePayload = {}
    local payload
    if type(data) == "table" then
      for k, v in pairs(data) do
        table.insert(tablePayload, k .. "=" .. tostring(v))
      end
      payload = table.concat(tablePayload, ",")
    else
      payload = data
    end
	GBankClassic_Output:Debug("COMMS", "<", prefix, prefixDesc, "via", string.upper(distribution), "from", sender, "(" .. (#message or 0) .. " bytes" .. (data.type and ", type=" .. tostring(data and data.type) or "") ..")", "payload:", payload)

	if prefix == "gbank-dv2" then
		if self:QueueDebouncedMessageWithMultipleGuildBankAlts(sender, data) then
			return
		end

		-- Fallback to immediate processing if queuing failed
		self:ProcessFingerprint(data, sender)

		return
	end

	if prefix == "gbank-d" then
		if data.type == "alt" or data.type == "roster" then
			if self:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data) then
				return
			end
		end

		-- Fallback to immediate processing if queuing failed
		if data.type == "alt" then
			self:ProcessGuildBankAltData(data, sender)
		end

		if data.type == "roster" then
			self:ProcessRosterData(data, sender)
		end
	end

	if prefix == "gbank-state" then
		if data.type == "state-summary" then
			if self:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data) then
				return
			end

			-- Fallback to immediate processing if queuing failed
			self:ProcessStateSummary(data, sender)
		end
	end

	if prefix == "gbank-nochange" then
		if data.type == "no-change" then
			if self:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data) then
				return
			end

			-- Fallback to immediate processing if queuing failed
			self:ProcessStateNoChange(data, sender)
		end
	end

	if prefix == "gbank-r" then
		-- Legacy 2.5.4 query: ignore (2.6.0 doesn't send deltas, so this query is misdirected)
		if data.type == "alt" then
			local altName = data.name
			GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), QUERIES_COLOR, "guild bank alt data for", self:ColorPlayerName(altName), "using a deprecated protocol: ignored")

			return
		end

		if data.type == "alt-request" then -- See Guild:QueryForGuildBankAltData
			local altName = data.name
			local hasData = GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[altName] ~= nil
			local isStillAGuildBankAlt = GBankClassic_Guild:IsGuildBankAlt(altName) or false

            if sender == altName then
                GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), QUERIES_COLOR, "guild bank alt data for themselves: ignored")

                return
            end

			GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), QUERIES_COLOR, "guild bank alt data for", self:ColorPlayerName(altName), "")

			if hasData and isStillAGuildBankAlt then
				GBankClassic_Guild:SendAltData(altName, sender)
			end
		end

		if data.type == "roster" then -- See Guild:QueryForRosterData
			if (data.player and data.player == player) or not data.player then
				GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), QUERIES_COLOR, "roster data")

				local currentTime = GetServerTime()
				if self.lastRosterSync == nil or currentTime - self.lastRosterSync > 300 then
					self.lastRosterSync = currentTime
					GBankClassic_Guild:SendRosterData(sender)
				end
			end
		end
	end

	if prefix == "gbank-rr" then
		if data.type == "alt-request-reply" then
			local altName = data.name
			local hasData = data.hasData or false

			GBankClassic_Output:Debug("PROTOCOL", self:ColorPlayerName(sender), QUERIES_COLOR, "acknowledged guild bank alt data request (deprecated) for", self:ColorPlayerName(altName), string.format("(hasData=%s)", tostring(hasData)))

			if hasData then
            	GBankClassic_Guild:SendStateSummary(altName, sender)
			end
		end
	end

	if prefix == "gbank-h" then
		GBankClassic_Guild:Hello("reply")
	end

	if prefix == "gbank-hr" then
		GBankClassic_Output:Debug("QUERIES", "gbank-hr", data)

		local message = tostring(data)
		local versionStr = string.match(message, "version (%d+)")
		if versionStr then
			local addonVersion = tonumber(versionStr)
			if not self.guildMembersFingerprintData then
				self.guildMembersFingerprintData = {}
			end
			self.guildMembersFingerprintData[sender] = {
				addonVersion = addonVersion,
				seen = GetServerTime()
			}
			GBankClassic_Output:Debug("ROSTER", "Parsed version %s for %s from hello reply", addonVersion, self:ColorPlayerName(sender))

			-- Addon version check
			local myVersionData = GBankClassic_Guild:GetVersion()
			if myVersionData.addon and addonVersion > myVersionData.addon then
				if not self.isAddonOutdated then
					-- Only make the callout once per session
					self.isAddonOutdated = true
					GBankClassic_Output:Info("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived")
				end
			end
		end

		-- Print versions after a quiet period
		if self.printVersionsTimer then
			GBankClassic_Core:CancelTimer(self.printVersionsTimer)
			self.printVersionsTimer = nil
		end
		self.printVersionsTimer = GBankClassic_Core:ScheduleTimer(function()
			GBankClassic_Chat:PrintVersions()
		end, 15)
	end

	if prefix == "gbank-s" then
		GBankClassic_Guild:Share("reply")
	end

	if prefix == "gbank-sr" then
		GBankClassic_Output:Debug("QUERIES", "gbank-sr", data)
	end

	if prefix == "gbank-w" then
		GBankClassic_Guild:Wipe("reply")
	end

	if prefix == "gbank-wr" then
		GBankClassic_Output:Debug("QUERIES",  "gbank-wr", data)
	end
end

-- Help text color codes
local HELP_COLOR = {
	HEADER = "|cff33ff99",
	COMMAND = "|cffe6cc80",
	RESET = "|r",
}

-- Command registry: name, usage, help, expert, handler
-- Commands are displayed in help in the order they appear here
-- Set help = nil to hide from help output
local COMMAND_REGISTRY = {
	-- Basic commands
	{
		name = "help",
		help = "this message",
		handler = function()
			Chat:ShowHelp()
		end,
	},
	{
		name = "version",
		help = "display the GBankClassic version",
		handler = function()
			local version = GetAddOnMetadata("GBankClassic", "Version") or "unknown"
			GBankClassic_Output:Response("GBankClassic version: %s.", version)
		end,
	},
	{
		name = "sync",
		help = "manually receive the latest data from other online users with guild bank data; this is done every 10 minutes automatically",
		handler = function()
			Chat:PerformSync()
		end,
	},
	{
		name = "share",
		help = "manually share the contents of your guild bank with other online users of GBankClassic; this is done every 3 minutes automatically",
		handler = function()
			GBankClassic_Bank:OnUpdateStart()
			GBankClassic_Bank:OnUpdateStop()
			GBankClassic_Guild:Share()
		end,
	},
	{
		name = "reset",
		help = "reset your own GBankClassic database",
		handler = function()
			local guild = GBankClassic_Guild:GetGuildName()
			if not guild then
				return
			end

			GBankClassic_Guild:Reset(guild)
		end,
	},
	{
		name = "restoreui",
		help = "restore all user interface window positions to be within the screen boundaries",
		expert = true,
		handler = function()
			GBankClassic_Chat:RestoreUI()
		end,
	},
	-- Expert commands (alphabetically sorted)
	{
		name = "debounce",
		help = "show debounced message queue status (debug)",
		expert = true,
		handler = function(arg1)
			if arg1 == "off" then
				GBankClassic_Chat.debounceConfig.enabled = false
				GBankClassic_Output:Response("Debouncing disabled.")
			elseif arg1 == "on" then
				GBankClassic_Chat.debounceConfig.enabled = true
				GBankClassic_Output:Response("Debouncing enabled.")
			else
				local queueMultipleAltCount = GBankClassic_Globals:Count(GBankClassic_Chat.debounceQueues.multipleAlts or {})
				local queueSingularAltCount = GBankClassic_Globals:Count(GBankClassic_Chat.debounceQueues.singularAlt or {})
				GBankClassic_Output:Response("Debounce status: %s.", GBankClassic_Chat.debounceConfig.enabled and "enabled" or "disabled")
				GBankClassic_Output:Response("Queued messages with singular guild bank alt: %d.", queueSingularAltCount)
				GBankClassic_Output:Response("Queued messages with multiple guild bank alts: %d.", queueMultipleAltCount)

				if arg1 == "detail" then
					if queueMultipleAltCount > 0 then
						GBankClassic_Output:Response("Messages with multiple guild bankt alts:")
						for altNorm, best in pairs(GBankClassic_Chat.debounceQueues.multipleAlts) do
							GBankClassic_Output:Response("  %s: sender=%s, version=%s, hash=%s", altNorm, best.sender, tostring(best.version), tostring(best.hash))
						end
					end
					if queueSingularAltCount > 0 then
						GBankClassic_Output:Response("Messages with singular guild bank alt:")
						for key, queued in pairs(GBankClassic_Chat.debounceQueues.singularAlt) do
							GBankClassic_Output:Response("  %s: sender=%s, version=%s", key, queued.sender, tostring(queued.version))
						end
					end
				end
			end
		end,
	},
	{
		name = "debugtab",
		help = "create a dedicated chat tab for debug output",
		expert = true,
		handler = function()
			if GBankClassic_Output:CreateDebugTab() then
				GBankClassic_Output:Response("Debug output will now appear in 'GBankClassicDebug' tab.")
				GBankClassic_Output:Response("Use /bank debug to enable debug logging.")
			end
		end,
	},
	{
		name = "hello",
		help = "understand which online guild members use which addon version and know what guild bank data",
		expert = true,
		handler = function()
			GBankClassic_Guild:Hello()
		end,
	},
	{
		name = "roster",
		help = "if officer notes are used to define guild bank alts, use this command to share the roster of guild bank alts with online guild members",
		expert = true,
		handler = function()
			GBankClassic_Guild:AuthorRosterData()
		end,
	},
	{
		name = "versions",
		help = "show addon versions of online guild members",
		expert = true,
		handler = function()
			Chat:PrintVersions()
		end,
	},
	{
		name = "wipe",
		help = "reset your own GBankClassic database",
		expert = true,
		handler = function()
			GBankClassic_Guild:WipeMine()
		end,
	},
	{
		name = "wipeall",
		help = "officer only: reset your own GBankClassic database and that of all online guild members",
		expert = true,
		handler = function()
			GBankClassic_Guild:Wipe()
		end,
	},
	-- Hidden commands (no help text)
	{
		name = "debug",
		handler = function()
			local currentLevel = GBankClassic_Output:GetLevel()
			if currentLevel == LOG_LEVEL.DEBUG then
				-- Restore to pre-debug level
				local restoreLevel = preDebugLogLevel or LOG_LEVEL.INFO
				preDebugLogLevel = nil
				GBankClassic_Output:SetLevel(restoreLevel)
				GBankClassic_Options.db.global.bank["logLevel"] = restoreLevel

				-- Get level name for response message
				local levelName = "Info"
				if restoreLevel == LOG_LEVEL.RESPONSE then
					levelName = "Quiet"
				elseif restoreLevel == LOG_LEVEL.ERROR then
					levelName = "Error"
				elseif restoreLevel == LOG_LEVEL.WARN then
					levelName = "Warn"
				end
				GBankClassic_Output:Response("Debug: off (log level: " .. levelName .. ").")
			else
				-- Save current level before entering debug mode
				preDebugLogLevel = GBankClassic_Options:GetLogLevel()
				GBankClassic_Output:SetLevel(LOG_LEVEL.DEBUG)
				GBankClassic_Options.db.global.bank["logLevel"] = LOG_LEVEL.DEBUG
				GBankClassic_Output:Response("Debug: on (log level: Debug).")
			end
		end,
	},
}

-- Build lookup table for fast command dispatch
local COMMAND_HANDLERS = {}
for _, cmd in ipairs(COMMAND_REGISTRY) do
	COMMAND_HANDLERS[cmd.name] = cmd.handler
end

-- Instructions as multiline strings for readability
local HELP_INSTRUCTIONS = {
	{
		title = "Instructions for setting up a new guild bank:",
		text = [[
1. Log in with the guild bank character, ensuring they are in the guild.
2. Add |cffe6cc80gbank|r to their guild or officer note, then type |cffe6cc80/reload|r.
3. In addon options (Escape -> Options -> Addons -> GBankClassic), click on the |cffe6cc80-|r icon (expand/collapse) to the left of the entry, enable reporting and scanning for the bank character in the |cffe6cc80Bank|r section.
4. Open and close your bank and mailbox.
5. Type |cffe6cc80/bank roster|r and confirm your bank character is included in the roster.
6. Type |cffe6cc80/reload|r. Wait up to 3 minutes (or type |cffe6cc80/bank share|r for immediate sharing) until |cffe6cc80Sharing guild bank data...|r completes.
7. Verify with a guild member (they type |cffe6cc80/bank|r).]],
	},
	{
		title = "Instructions for removing a guild bank:",
		text = [[
1. Log in with an officer or another bank character in the same guild (or a character from a different guild).
2. If the bank character is still in the guild, remove |cffe6cc80gbank|r from their notes.
3. Type |cffe6cc80/bank roster|r and confirm the bank character is no longer listed.
4. Verify with a guild member (they type |cffe6cc80/bank|r).]],
	},
}

function Chat:ChatCommand(input)
	if input == nil or input == "" then
		GBankClassic_UI_Inventory:Toggle()
	else
		local prefix, arg1 = GBankClassic_Core:GetArgs(input, 2)
		local handler = COMMAND_HANDLERS[prefix]
		if handler then
			handler(arg1)
		else
			GBankClassic_Output:Response("Unknown command: %s.", prefix)
			self:ShowHelp()
		end
	end

	return false
end

function Chat:ShowHelp()
	local H = HELP_COLOR.HEADER
	local C = HELP_COLOR.COMMAND
	local R = HELP_COLOR.RESET

	-- Basic commands header
	GBankClassic_Output:Response("\n%sCommands:%s", H, R)
	GBankClassic_Output:Response("%s/bank%s - display the GBankClassic interface", C, R)

	-- Print basic commands
	for _, cmd in ipairs(COMMAND_REGISTRY) do
		if cmd.help and not cmd.expert then
			local usage = cmd.usage and (" " .. cmd.usage) or ""
			GBankClassic_Output:Response("%s/bank %s%s%s - %s", C, cmd.name, usage, R, cmd.help)
		end
	end

	-- Expert commands header
	GBankClassic_Output:Response("\n%sExpert commands:%s", H, R)

	-- Print expert commands
	for _, cmd in ipairs(COMMAND_REGISTRY) do
		if cmd.help and cmd.expert then
			local usage = cmd.usage and (" " .. cmd.usage) or ""
			GBankClassic_Output:Response("%s/bank %s%s%s - %s", C, cmd.name, usage, R, cmd.help)
		end
	end

	-- Print instructions
	for _, instruction in ipairs(HELP_INSTRUCTIONS) do
		GBankClassic_Output:Response("\n%s%s%s", H, instruction.title, R)
		GBankClassic_Output:Response(instruction.text)
	end
end

function Chat:PrintVersions()
	-- Get our own version
	local myVersionData = GBankClassic_Guild:GetVersion()
    local myVersionNumber = myVersionData and myVersionData.addon
	local myPlayer = GBankClassic_Guild:GetNormalizedPlayer()

	-- Collect versions into a sortable list
	local versions = {}

	-- Add ourselves
	table.insert(versions, { name = myPlayer, addonVersion = tonumber(myVersionNumber), seen = time(), isSelf = true })

	-- Add tracked guild members
	for name, info in pairs(self.guildMembersFingerprintData) do
		table.insert(versions, { name = name, addonVersion = tonumber(info.addonVersion), seen = info.seen, isSelf = false })
	end

	-- Sort by version (descending), then by name
	table.sort(versions, function(a, b)
		if (a and a.addonVersion and b and b.addonVersion) and (a.addonVersion ~= b.addonVersion) then
			return a.addonVersion > b.addonVersion
		end

		return a.name < b.name
	end)

	-- Print header
	local count = #versions
	GBankClassic_Output:Response("Addon versions (%d members):", count)

	-- Print each version
	local now = time()
	for _, entry in ipairs(versions) do
		local age = ""
		if not entry.isSelf then
			local seconds = now - entry.seen
			if seconds < 60 then
				age = " (just now)"
			elseif seconds < 3600 then
				age = string.format(" (%dm ago)", math.floor(seconds / 60))
			else
				age = string.format(" (%dh ago)", math.floor(seconds / 3600))
			end
		end
		local marker = entry.isSelf and " (you)" or ""
		GBankClassic_Output:Response("  %s: %s%s%s", entry.name, entry.addonVersion, marker, age)
	end
end

function Chat:RestoreUI()
	if GBankClassic_Options and GBankClassic_Options.db and GBankClassic_Options.db.char then
		local count = GBankClassic_Globals:Count(GBankClassic_Options.db.char.framePositions)
		GBankClassic_Options.db.char.framePositions = {}
		GBankClassic_Output:Response("Cleared %d saved window position(s).", count)
		if GBankClassic_UI_Inventory.isOpen then
			GBankClassic_UI_Inventory:Close()
			GBankClassic_UI_Inventory:Toggle()
		else
			GBankClassic_UI_Inventory:Open()
		end
	else
		GBankClassic_Output:Response("No frame positions to clear.")
	end
end