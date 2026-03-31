local addonName, GBCR = ...

GBCR.Protocol = {}
local Protocol = GBCR.Protocol

local Globals = GBCR.Globals
local strsplit = Globals.strsplit
local wipe = Globals.wipe
local IsInRaid = Globals.IsInRaid
local IsInInstance = Globals.IsInInstance
local GetTime = Globals.GetTime
local GetServerTime = Globals.GetServerTime
local GetItemInfo = Globals.GetItemInfo
local After = Globals.After
local Item = Globals.Item
local GetClassColor = Globals.GetClassColor
local Enum = Globals.Enum

local Constants = GBCR.Constants
local colorYellow = Constants.COLORS.YELLOW
local colorBlue = Constants.COLORS.BLUE
local colorWhite = Constants.COLORS.WHITE
local colorGold = Constants.COLORS.GOLD
local prefixDescriptions = Constants.COMM_PREFIX_DESCRIPTIONS

function Protocol:Init()
    self.isAddonOutdated = false
	self.guildMembersFingerprintData = {}
	self.lastRosterSync = nil

    self.pendingSendCount = 0

    -- Item link reconstruction
    self.itemReconstructQueue = {} -- Queue system for batched item reconstruction
    self.pendingAsyncLoads = 0 -- Track number of pending async loads
    self.isProcessingQueue = false

    -- Message debouncing
	self.debounceConfig = {
		enabled = true,
		intervals = {
			["gbc-fp-share"] = 3.0,
			["gbc-data-share"] = 2.5,
			["gbc-roster-share"] = 2.0,
		},
	}
	self.debounceQueues = {
		multipleAlts = {},					-- For gbc-fp-share: [altName] = { version, sender, queuedAt }
		singularAlt = {},					-- For other messages: [key] = { version, sender, data, message, queuedAt }
	}
	self.debounceTimers = {
		multipleAlts = nil,          		-- Single timer for gbc-fp-share processing
		singularAlt = {},       			-- Per-key timers for other messages
	}

	-- Fingerprint
	GBCR.Addon:RegisterComm("gbc-fp-share", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
	GBCR.Addon:RegisterComm("gbc-fp-query", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- Guild bank alt data
	GBCR.Addon:RegisterComm("gbc-data-share", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
	GBCR.Addon:RegisterComm("gbc-data-query", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- Roster data
	GBCR.Addon:RegisterComm("gbc-roster-share", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
	GBCR.Addon:RegisterComm("gbc-roster-query", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

    -- Hello
    GBCR.Addon:RegisterComm("gbc-h", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBCR.Addon:RegisterComm("gbc-hr", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)

    -- Share
    GBCR.Addon:RegisterComm("gbc-s", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBCR.Addon:RegisterComm("gbc-sr", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)

    -- Wipe
    GBCR.Addon:RegisterComm("gbc-w", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBCR.Addon:RegisterComm("gbc-wr", function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)
end

--- =========================================== ---
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
function Protocol:IsAltDataAllowed(sender, claimedNorm)
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
function Protocol:CancelAllDebounceTimers()
    if self.debounceTimers and self.debounceTimers.multipleAlts then
        GBCR.Addon:CancelTimer(self.debounceTimers.multipleAlts)
        self.debounceTimers.multipleAlts = nil
    end

    if self.debounceTimers and self.debounceTimers.singularAlt then
        for _, timer in pairs(self.debounceTimers.singularAlt) do
            GBCR.Addon:CancelTimer(timer)
        end
        wipe(self.debounceTimers.singularAlt)
    end

    if self.debounceQueues then
        wipe(self.debounceQueues.multipleAlts)
        wipe(self.debounceQueues.singularAlt)
    end
end

-- Generate debounce key for messages with a singular guild bank alt
function Protocol:GetDebounceKey(prefix, data)
    if prefix == "gbc-data-share" and data[2] then
		return "gbc-data-share:" .. GBCR.Guild:FindGuildMemberByUid(data[2])
    elseif prefix == "gbc-roster-share" then
		return "gbc-roster-share"
    end

    return prefix
end

-- Extract version from the payload of messages with a singular guild bank alt
function Protocol:ExtractVersionFromSingularGuildBankAltPayload(prefix, data)
    if prefix == "gbc-fp-share" then
        return nil -- Extracted in QueueDebouncedMessageWithMultipleGuildBankAlts
	elseif prefix == "gbc-data-share" then
		return data[3]
	elseif prefix == "gbc-roster-share" and data.roster then
		return data.roster.version
    end

    return nil, nil
end

-- Check if incoming is better than existing
function Protocol:ShouldReplaceQueuedData(existing, newVersion)
    if not existing then
        return true
    end

    if newVersion and existing.version then
        return newVersion > existing.version
    elseif newVersion and not existing.version then
        return true
    end

    -- Fallback: last-wins
    return true
end

-- Queue debounced message containing data for multiple guild bank alts (gbc-fp-share)
function Protocol:QueueDebouncedMessageWithMultipleGuildBankAlts(sender, payload)
    if not self.debounceConfig.enabled then
		self:ProcessFingerprint(payload, sender)

        return true
    end

    -- Cancel existing timer to extend quiet window
    if self.debounceTimers.multipleAlts then
        GBCR.Addon:CancelTimer(self.debounceTimers.multipleAlts)
        self.debounceTimers.multipleAlts = nil
    end

    local incomingData = self:ParseFingerprintPayload(payload)

    local incomingAddonVersionNumber = incomingData.addonVersionNumber
    local incomingIsGuildBankAlt = incomingData.isGuildBankAlt
    local incomingAlts = incomingData.alts
    local incomingRosterVersionTimestamp = incomingData.rosterVersionTimestamp

    -- Track sender metadata
    self:TrackSenderMetadata(sender, incomingAddonVersionNumber, incomingIsGuildBankAlt, incomingRosterVersionTimestamp)

    -- For each alt in payload, track best sender across all senders
	local queued = false
    for altName, altInfo in pairs(incomingAlts) do
        local altNorm = GBCR.Guild:NormalizeName(altName) or altName
        local isSelf = altName == GBCR.Guild:GetNormalizedPlayer()
        if not isSelf then
            local incomingVersion = type(altInfo) == "table" and altInfo.version or altInfo
            local existing = self.debounceQueues.multipleAlts[altNorm]

            if self:ShouldReplaceQueuedData(existing, incomingVersion) then
                self.debounceQueues.multipleAlts[altNorm] = {
                    version = incomingVersion,
                    sender = sender,
                    queuedAt = GetServerTime(),
                }
                GBCR.Output:Debug("PROTOCOL", "Best sender for %s is now %s (incomingVersion=%s)", GBCR.Output:ColorPlayerName(altNorm), GBCR.Output:ColorPlayerName(sender), tostring(incomingVersion))
                queued = true
            end
        end
    end

    -- Schedule processing after quiet period
	if queued then
		local interval = self.debounceConfig.intervals["gbc-fp-share"] or 3.0
		self.debounceTimers.multipleAlts = GBCR.Addon:ScheduleTimer(function()
			Protocol:ProcessDebouncedMessageWithMultipleGuildBankAlts()
		end, interval)

		GBCR.Output:Debug("PROTOCOL", "Queued processing of guild bank alt data from %s for %d guild bank alts (processing in %.1fs)", GBCR.Output:ColorPlayerName(sender), Globals:Count(incomingAlts or {}), interval)
	end

    return true
end

-- Process debounced message containing data for multiple guild bank alts
function Protocol:ProcessDebouncedMessageWithMultipleGuildBankAlts()
    self.debounceTimers.multipleAlts = nil

    GBCR.Output:Debug("PROTOCOL", "Processing debounced guild bank alt data (alts=%d)", Globals:Count(self.debounceQueues.multipleAlts))

    local queryCount = self:ProcessFingerprintAltData(self.debounceQueues.multipleAlts)
	local pluralQueries = (queryCount ~= 1 and "s" or "")
	GBCR.Output:Debug("PROTOCOL", "Queried data for %d guild bank alt%s from best sources.", queryCount, pluralQueries)

    wipe(self.debounceQueues.multipleAlts)
end

-- Queue debounced message containing data for a singular guild bank alt (gbc-data-share or gbc-roster-share)
function Protocol:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data)
    if not self.debounceConfig.enabled then
        return false
    end

    local key = self:GetDebounceKey(prefix, data)
    local version = self:ExtractVersionFromSingularGuildBankAltPayload(prefix, data)
    local interval = self.debounceConfig.intervals[key] or self.debounceConfig.intervals[prefix] or 2.0
    local existing = self.debounceQueues.singularAlt[key]

    -- Check if we should replace existing queued data
    if not self:ShouldReplaceQueuedData(existing, version) then
        GBCR.Output:Debug("PROTOCOL", "Discarded older %s for key `%s` (queued version=%d vs incoming version=%d)", prefix, key, existing and existing.version or 0, version or 0)

		return true
    end

    -- Cancel existing timer
    if self.debounceTimers.singularAlt[key] then
        GBCR.Addon:CancelTimer(self.debounceTimers.singularAlt[key])
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
        queuedAt = GetServerTime(),
    }

    -- Schedule processing
    self.debounceTimers.singularAlt[key] = GBCR.Addon:ScheduleTimer(function()
        Protocol:ProcessDebouncedMessageWithSingularGuildBankAlt(key)
    end, interval)

    GBCR.Output:Debug("PROTOCOL", "Queued processing of %s (version=%s, processing in %.1fs)", key, tostring(version), interval)

    return true
end

-- Process debounced message containing data for a singular guild bank alt
function Protocol:ProcessDebouncedMessageWithSingularGuildBankAlt(key)
    local queued = self.debounceQueues.singularAlt[key]
    if not queued then return end

    -- Clear queue and timer
    self.debounceQueues.singularAlt[key] = nil
    self.debounceTimers.singularAlt[key] = nil

    GBCR.Output:Debug("PROTOCOL", "Processing debounced queue for %s (version=%s)", key, tostring(queued.version))

    -- Route to appropriate handler
    if queued.prefix == "gbc-data-share" then
		self:ProcessGuildBankAltData(queued.data, queued.sender)
    elseif queued.prefix == "gbc-roster-share" then
		self:ProcessRosterData(queued.data, queued.sender)
    end
end

-- Centralized sync function for both /sync command and UI opening
function Protocol:PerformSync()
	local now = GetServerTime()
	local last = self.lastSync or 0
	if now - last > 30 then
		self.lastSync = now
        self:SendFingerprint("ALERT")
        GBCR.Guild:RequestMissingGuildBankAltData()
        -- GBCR.Guild:QueryRequestsIndex(nil, "ALERT")
	end
end

-- Process the alt version from a fingerprint broadcast (gbc-fp-share)
function Protocol:ProcessFingerprintAltData(fingerprintAltData, sender)
	local queryCount = 0
    local ourPlayer = GBCR.Guild:GetNormalizedPlayer()

	for altName, altData in pairs(fingerprintAltData) do
        if altName ~= ourPlayer then
			local shouldQuery = false
			local ourAlt = GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts and GBCR.Database.savedVariables.alts[altName]
			local ourVersion = type(ourAlt) == "table" and ourAlt.version
			local incomingVersion = type(altData) == "table" and altData.version or 0

			GBCR.Output:Debug("PROTOCOL", "Evaluating fingerprint from %s for %s (incomingVersion=%d, ourVersion=%s)", GBCR.Output:ColorPlayerName(sender or altData.sender), GBCR.Output:ColorPlayerName(altName), tostring(incomingVersion), tostring(ourVersion))

			if not ourVersion or incomingVersion > ourVersion then
				shouldQuery = true
				GBCR.Output:Debug("PROTOCOL", "Query decision for %s: incoming version is newer, query", GBCR.Output:ColorPlayerName(altName))
			else
				GBCR.Output:Debug("PROTOCOL", "Query decision for %s: incoming version is same or older, don't query", GBCR.Output:ColorPlayerName(altName))
			end

			if shouldQuery then
				self:QueryForGuildBankAltData(sender or altData.sender, altName)
				queryCount = queryCount + 1
			end
		end
	end

	return queryCount
end

-- Process fingerprint broadcast (gbc-fp-share)
function Protocol:ProcessFingerprint(payload, sender)
    local incomingData = self:ParseFingerprintPayload(payload)

    local incomingAddonVersionNumber = incomingData.addonVersionNumber
    local incomingAreOfficerNotesUsedToDefineGuildBankAlts = incomingData.areOfficerNotesUsedToDefineGuildBankAlts
    local incomingIsGuildBankAlt = incomingData.isGuildBankAlt
    local incomingAlts = incomingData.alts
    local incomingRosterVersionTimestamp = incomingData.rosterVersionTimestamp

    -- Track sender metadata
    self:TrackSenderMetadata(sender, incomingAddonVersionNumber or 0, incomingIsGuildBankAlt or false, incomingRosterVersionTimestamp or 0)

    if incomingAreOfficerNotesUsedToDefineGuildBankAlts and incomingAreOfficerNotesUsedToDefineGuildBankAlts ~= GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts then
        GBCR.Guild.areOfficerNotesUsedToDefineGuildBankAlts = incomingAreOfficerNotesUsedToDefineGuildBankAlts
    end

	local altCount = incomingAlts and Globals:Count(incomingAlts)
	GBCR.Output:Debug("PROTOCOL", GBCR.Output:ColorPlayerName(sender), GBCR.Globals:Colorize(colorBlue, "shares"), "fingerprint", string.format("(%d guild bank alts)", altCount))

	local guildName = GBCR.Guild:GetGuildName()
	local rosterVersionTimestamp = GBCR.Database.savedVariables and GBCR.Database.savedVariables.roster and GBCR.Database.savedVariables.roster.version
	if guildName and rosterVersionTimestamp then
		if incomingRosterVersionTimestamp then
			if rosterVersionTimestamp == nil or incomingRosterVersionTimestamp > rosterVersionTimestamp then
				GBCR.Guild:QueryForRosterData(sender, incomingRosterVersionTimestamp)
			end
		end

		if incomingAlts then
			local queryCount = self:ProcessFingerprintAltData(incomingAlts, sender)
			local pluralQueries = (queryCount ~= 1 and "s" or "")
			GBCR.Output:Debug("PROTOCOL", "Queried data for %d guild bank alt%s.", queryCount, pluralQueries)
		end
	end
end

-- Process roster data (gbc-roster-share)
function Protocol:ProcessRosterData(data, sender)
    local isSenderAuthority = GBCR.Guild.guildMembersCache and GBCR.Guild.guildMembersCache[sender] and GBCR.Guild.guildMembersCache[sender].isAuthority
    if isSenderAuthority then
        GBCR.Output:Debug("PROTOCOL", GBCR.Output:ColorPlayerName(sender), GBCR.Globals:Colorize(colorBlue, "shares"), "roster data: we accept it")
        self:ConsumePendingSync("roster", sender)
        GBCR.Database.savedVariables.roster = data.roster
    end
end

-- Process guild bank alt data (gbc-data-share)
function Protocol:ProcessGuildBankAltData(data, sender)
    local altName = GBCR.Guild:FindGuildMemberByUid(data[2])

    local allowed = self:IsAltDataAllowed(sender, altName)
    if self:ConsumePendingSync("alt", sender, altName) then
        allowed = true
    end

    local status = allowed and self:ReceiveData(data, sender) or Constants.ADOPTION_STATUS.UNAUTHORIZED
    GBCR.Output:Debug("PROTOCOL", GBCR.Output:ColorPlayerName(sender), GBCR.Globals:Colorize(colorBlue, "shares"), "bank data about", GBCR.Output:ColorPlayerName(altName) .. ": we", allowed and "accept it" or "do not accept it", formatSyncStatus(status))

    if allowed and status == Constants.ADOPTION_STATUS.ADOPTED then
        GBCR.Output:Info("Received data for %s from %s.", GBCR.Output:ColorPlayerName(altName), GBCR.Output:ColorPlayerName(sender))
        GBCR.UI:QueueUIRefresh()
	elseif allowed then
		GBCR.Output:Debug("PROTOCOL", "Ignoring data for %s from %s (reason: %s).", GBCR.Output:ColorPlayerName(altName), GBCR.Output:ColorPlayerName(sender), status)
	else
		return
    end
end

-- Main communication handler
function Protocol:OnCommReceived(prefix, message, distribution, sender)
	local prefixDesc = prefixDescriptions[prefix] or "(Unknown)"
	local player = GBCR.Guild:GetNormalizedPlayer()
	sender = GBCR.Guild:NormalizeName(sender) or sender

	if not GBCR.Guild.player and not GBCR.Core.addonVersionNumber then
		GBCR.Output:Debug("COMMS", "<", "(ignoring)", prefix, prefixDesc, "(not ready yet)")

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("COMMS", "<", "(suppressing)", prefix, prefixDesc, "from", GBCR.Output:ColorPlayerName(sender), "(in instance or raid)")

		return
	end

	if player == sender then
		GBCR.Output:Debug("COMMS", "<", "(ignoring)", prefix, prefixDesc, "(our own)")

		return
	end

	local success, data = GBCR.Core:DeSerializePayload(message)
	if not success then
		GBCR.Output:Debug("COMMS", "<", "(error)", prefix, prefixDesc, "from", GBCR.Output:ColorPlayerName(sender), "(failed to deserialize, error=" .. tostring(data) .. ")")

        return
	end

    if GBCR.Options:IsDebugEnabled() then
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
		GBCR.Output:Debug("COMMS", "<", prefix, prefixDesc, "via", string.upper(distribution), "from", sender, "(" .. (#message or 0) .. " bytes" .. (data.type and ", type=" .. tostring(data and data.type) or "") ..")", "payload:", payload)
	else
		GBCR.Output:Debug("COMMS", "<", prefix, prefixDesc, "via", string.upper(distribution), "from", GBCR.Output:ColorPlayerName(sender), "(" .. (#message or 0) .. " bytes" .. (data.type and ", type=" .. tostring(data and data.type) or "") ..")")
	end

	if prefix == "gbc-fp-share" then
		if self:QueueDebouncedMessageWithMultipleGuildBankAlts(sender, data) then
			return
		end

		-- Fallback to immediate processing if queuing failed
		self:ProcessFingerprint(data, sender)

		return
	end

	if prefix == "gbc-data-share" then
		if self:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data) then
			return
		end

		-- Fallback to immediate processing if queuing failed
		self:ProcessGuildBankAltData(data, sender)
	end

	if prefix == "gbc-data-query" then -- See self:QueryForGuildBankAltData
		local altName = data.name
		local hasData = GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts and GBCR.Database.savedVariables.alts[altName] ~= nil
		local isStillAGuildBankAlt = GBCR.Guild:IsGuildBankAlt(altName) or false

		if sender == altName then
			GBCR.Output:Debug("PROTOCOL", GBCR.Output:ColorPlayerName(sender), GBCR.Globals:Colorize(colorYellow, "queries"), "guild bank alt data for themselves: ignored")

			return
		end

		GBCR.Output:Debug("PROTOCOL", GBCR.Output:ColorPlayerName(sender), GBCR.Globals:Colorize(colorYellow, "queries"), "guild bank alt data for", GBCR.Output:ColorPlayerName(altName), "")

		if hasData and isStillAGuildBankAlt then
			self:SendData(altName, sender)
		end
	end

	if prefix == "gbc-roster-share" then
		if self:QueueDebouncedMessageWithSingularGuildBankAlt(prefix, message, distribution, sender, data) then
			return
		end

		-- Fallback to immediate processing if queuing failed
		self:ProcessRosterData(data, sender)
	end

	if prefix == "gbc-roster-query" then -- See self:QueryForRosterData
		if (data.player and data.player == player) or not data.player then
			GBCR.Output:Debug("PROTOCOL", GBCR.Output:ColorPlayerName(sender), GBCR.Globals:Colorize(colorYellow, "queries"), "roster data")

			local currentTime = GetServerTime()
			if self.lastRosterSync == nil or currentTime - self.lastRosterSync > 300 then
				self.lastRosterSync = currentTime
				GBCR.Guild:SendRoster(sender)
			end
		end
	end

	if prefix == "gbc-h" then
		self:Hello("reply")
	end

	if prefix == "gbc-hr" then
		local message = tostring(data)
		local versionStr = string.match(message, "version (%d+)")
		if versionStr then
			local incomingAddonVersionNumber = tonumber(versionStr)
			self.guildMembersFingerprintData[sender] = {
				addonVersionNumber = incomingAddonVersionNumber,
				seen = GetServerTime()
			}
			GBCR.Output:Debug("ROSTER", "Parsed version %s for %s from hello reply", incomingAddonVersionNumber, GBCR.Output:ColorPlayerName(sender))

			-- Addon version check
			if incomingAddonVersionNumber > GBCR.Core.addonVersionNumber then
				if not self.isAddonOutdated then
					-- Only make the callout once per session
					self.isAddonOutdated = true
					GBCR.Output:Response("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived")
					GBCR.Core:LoadMetadata()
				end
			end
		end

		if GBCR.Options:IsDebugEnabled() then
			if self.printVersionsTimer then
				GBCR.Addon:CancelTimer(self.printVersionsTimer)
				self.printVersionsTimer = nil
			end
			self.printVersionsTimer = GBCR.Addon:ScheduleTimer(function()
				GBCR.Chat:PrintVersions()
			end, 15)
		end
	end

	if prefix == "gbc-s" then
		Protocol:Share("reply")
	end

	if prefix == "gbc-w" then
		Protocol:Wipe("reply")
	end
end

--- =========================================== ---
--- FINGERPRINT (gbc-fp-share and gbc-fp-query) ---

--- CRAFT:

function Protocol:CraftFingerprintPayload()
    local db = GBCR.Database.savedVariables
    if not db then
        GBCR.Output:Debug("SYNC", "CraftFingerprintPayload: missing database")
        return {}
    end

    local rosterAlts = GBCR.Guild:GetRosterGuildBankAlts()
    if not rosterAlts or #rosterAlts == 0 then
        GBCR.Output:Debug("SYNC", "CraftFingerprintPayload: empty roster")
        return {}
    end

    local Guild = GBCR.Guild
    local membersCache = Guild.guildMembersCache
    local Output = GBCR.Output
    local altsData = db.alts

    local alts = {}
    for altName, altData in pairs(altsData) do
        if not Guild:IsGuildBankAlt(altName) then
            GBCR.Output:Debug("SYNC", "CraftFingerprintPayload: excluding %s (not in roster)", altName)
        elseif not self:HasAltContent(altData, altName) and not altData.itemsHash then
            GBCR.Output:Debug("SYNC", "CraftFingerprintPayload: excluding %s (no content)", altName)
        elseif type(altData) == "table" and altData.version then
            local member = membersCache[altName]
            if member and member.playerUid then
                local version = tonumber(altData.version) or 0
                GBCR.Output:Debug("SYNC", "CraftFingerprintPayload: including %s (version=%d)", altName, version)

                alts[#alts + 1] = { member.playerUid, version }
            end
        end
    end

    -- Sort in-place
    table.sort(alts, function(a, b)
        return a[2] < b[2]
    end)

    local baseVersion = (#alts > 0) and alts[1][2] or 0

    local payload = {
        GBCR.Core.addonVersionNumber,
        Guild.areOfficerNotesUsedToDefineGuildBankAlts,
        baseVersion,
        GBCR.Guild:IsGuildBankAlt(GBCR.Guild:GetNormalizedPlayer())
    }

    local pos = 5
    local prev = baseVersion

    for i = 1, #alts do
        local uid = alts[i][1]
        local version = alts[i][2]

        payload[pos] = uid
        payload[pos + 1] = version - prev

        prev = version
        pos = pos + 2
    end

    local rosterVersion = db.roster and db.roster.version
    payload[pos] = rosterVersion or -1

    return payload
end

function Protocol:ParseFingerprintPayload(payload)
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
            alts[name] = { version = version }
        end

        prev = version
        pos = pos + 2
    end

    local rosterRaw = payload[pos]
    local rosterVersionTimestamp = rosterRaw ~= -1 and rosterRaw or nil

    return { addonVersionNumber = addonVersionNumber, areOfficerNotesUsedToDefineGuildBankAlts = areOfficerNotesUsedToDefineGuildBankAlts, isGuildBankAlt = isGuildBankAlt, alts = alts, rosterVersionTimestamp = rosterVersionTimestamp }
end

--- SEND:

function Protocol:SendFingerprint(priority)
	local guild = GBCR.Guild:GetGuildName()
	if not guild then
        GBCR.Output:Debug("PROTOCOL", "SendFingerprint early exit because of missing guild information")

		return
	end

	local version = self:CraftFingerprintPayload()
	if #version == 0 then
        GBCR.Output:Debug("PROTOCOL", "SendFingerprint early exit because of missing fingerprint data")

		return
	end

	local data = GBCR.Core:SerializePayload(version)
	GBCR.Core:SendCommMessage("gbc-fp-share", data, "Guild", nil, priority or "NORMAL")
end

--- RECEIVE:

--- =========================================== ---
--- DATA (gbc-data-share and gbc-data-query) ---

--- CRAFT:

function Protocol:StripItemLinks(items)
	if not items then
		return nil
	end

	local stripped = {}
	for _, item in ipairs(items) do
		local strippedItem = {
			itemId = item.itemId,
			itemCount = item.itemCount
		}
		-- Preserve itemLink (weapons/armor)
		if item.itemLink and GBCR.Inventory:NeedsLink(item.itemLink) then
			strippedItem.itemLink = item.itemLink
		end

		table.insert(stripped, strippedItem)
	end

	return stripped
end

function Protocol:CraftDataPayload(altName, altData)
	if not altData then
		return nil
	end

	if not altData.version or altData.version == 0 then
		return
	end

	local countOfItems = altData.items and #altData.items or 0
	if countOfItems == 0 and altData.money == 0 then
		return
	end

    local Guild = GBCR.Guild

	local addonVersion = GBCR.Core.addonVersionNumber
	local version = altData.version
	local money = altData.money
	local ledger = {}
	for key, value in pairs(altData.ledger or {}) do
		table.insert(ledger, { key, value })
	end
	local items = self:StripItemLinks(altData.items) or {}
	local requests = altData.requests or {}

	-- Sort inputs to guarantee positive deltas
	table.sort(items, function(a, b)
        return tonumber(a.itemId) < tonumber(b.itemId)
    end)
	table.sort(requests, function(a, b)
        return tonumber(a.requestId) < tonumber(b.requestId)
    end)

	-- Build directory of unique player GUIDs
	local guidDict, guidIndex = {}, {}
	local function getGuidIndex(g)
		if not guidIndex[g] then
			guidIndex[g] = #guidDict + 1
			table.insert(guidDict, g)
		end

		return guidIndex[g]
	end

    -- Register all donatedBy GUIDs in the dictionary
    for i = 1, #ledger do
		getGuidIndex(Guild.guildMembersCache[ledger[i][1]].playerUid)
    end

    -- Register all requestedBy GUIDs in the dictionary
    for i = 1, #requests do
        getGuidIndex(Guild.guildMembersCache[requests[i].requestedBy].playerUid)
    end

	-- Start building the single, massive flat array as payload
	local payload = { addonVersion, Guild.guildMembersCache[altName].playerUid, version, money }
   	local position = 5

   -- GUID dictionary for the ledger and requests
   payload[position] = #guidDict; position = position + 1
   for i = 1, #guidDict do
      payload[position] = guidDict[i]; position = position + 1
   end

	-- Ledger
	payload[position] = #ledger; position = position + 1
    for i = 1, #ledger do
        local r = ledger[i]
        payload[position] = getGuidIndex(Guild.guildMembersCache[r[1]].playerUid); position = position + 1
        payload[position] = tonumber(r[2]) or 1; position = position + 1
    end

	-- Items
	payload[position] = #items; position = position + 1

	local prevID = 0
	for i = 1, #items do
		local item = items[i]
		local itemId = tonumber(item.itemId)
		local itemCount = tonumber(item.itemCount) or 1

		-- Delta encode
		payload[position] = itemId - prevID; position = position + 1
		prevID = itemId

		-- Check for enchant/suffix data
		local hasExtra = false
		local enchant, suffix = 0, 0

		if item.itemLink and item.itemLink ~= "" then
			local p1, p2, p3 = strsplit(":", GBCR.Inventory:GetItemKey(item.itemLink))
			enchant = tonumber(p2) or 0
			suffix = tonumber(p3) or 0
			if enchant ~= 0 or suffix ~= 0 then
				hasExtra = true
			end
		end

		if hasExtra then
			payload[position] = -itemCount; position = position + 1
			payload[position] = enchant; position = position + 1
			payload[position] = suffix; position = position + 1
		else
			payload[position] = itemCount; position = position + 1
		end
	end

   -- Requests
   payload[position] = #requests; position = position + 1
   local prevReqID = 0
   for i = 1, #requests do
      local r = requests[i]
      local id = tonumber(r[1])

      payload[position] = id - prevReqID; position = position + 1
      prevReqID = id

      payload[position] = getGuidIndex(Guild.guildMembersCache[r[2]].playerUid); position = position + 1
      payload[position] = tonumber(r[3]) or 1; position = position + 1
   end

	return payload
end

function Protocol:ParseDataPayload(payload)
    local Guild = GBCR.Guild

    local addonVersionNumber = payload[1]
    local altName = Guild:FindGuildMemberByUid(payload[2])
	local version = payload[3]
	local money = payload[4]
    local position = 5

    -- GUID dictionary for the ledger and requests
	local guidDict = {}
    local numGuids = payload[position]; position = position + 1
    for i = 1, numGuids do
        guidDict[i] = payload[position]; position = position + 1
    end

	-- Ledger
    local ledger = {}
    local numLedgerEntries = payload[position]; position = position + 1
    for i = 1, numLedgerEntries do
        local guidIdx = payload[position]; position = position + 1
        local donation = payload[position]; position = position + 1

        -- ledger[i] = { donatedBy = guidDict[guidIdx], donationValue = donation }
        ledger[Guild:FindGuildMemberByUid(guidDict[guidIdx])] = donation
    end

    -- Items
    local items = {}
    local numItems = payload[position]; position = position + 1
    local currentItemId = 0
    for i = 1, numItems do
        local delta = payload[position]; position = position + 1
        currentItemId = currentItemId + delta

        local rawCount = payload[position]; position = position + 1
        local itemCount = rawCount
        local itemString

        if rawCount < 0 then
            itemCount = -rawCount
            local enchant = payload[position]; position = position + 1
            local suffix = payload[position]; position = position + 1
            itemString = string.format("%d:%d:%d", currentItemId, enchant, suffix)
        end

        items[i] = { itemId = currentItemId, itemCount = itemCount, itemString = itemString }
    end

    -- Requests
    local requests = {}
    local numRequests = payload[position]; position = position + 1
    local currentReqID = 0
    for i = 1, numRequests do
        local delta = payload[position]; position = position + 1
        currentReqID = currentReqID + delta

        local guidIdx = payload[position]; position = position + 1
        local count = payload[position]; position = position + 1

        requests[i] = { requestId = currentReqID, requestedBy = Guild:FindGuildMemberByUid(guidDict[guidIdx]), requestedCount = count }
    end

    return { addonVersionNumber = addonVersionNumber, altName = altName, version = version, money = money, numLedgerEntries = numLedgerEntries, ledger = ledger, numItems = numItems, items = items, numRequests = numRequests, requests = requests }
end

--- SEND:

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

-- Create a per-send callback with its own stats tracking
function Protocol:CreateOnChunkSentCallback(altName, destination)
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
		local isSuccess = (sendResult == Enum.SendAddonMessageResult.Success or sendResult == true or sendResult == nil)
		local isThrottled = (sendResult == Enum.SendAddonMessageResult.AddonMessageThrottle or sendResult == Enum.SendAddonMessageResult.ChannelThrottle)
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
			GBCR.Output:Debug("CHUNK","Chunk %d/%d failed (%s). ", sendStats.chunksSent, totalChunks, resultStr, "Aborting send due to failure")
			sendStats.abort = true

			return
		end

		-- Show progress at start
		if sendStats.chunksSent == 1 then
			GBCR.Output:Debug("CHUNK", "Sharing data: %d bytes in ~%d chunks...", totalBytes, totalChunks)
		end

		-- Completion summary
		if bytesSent >= totalBytes then
			local elapsed = GetTime() - (sendStats.startTime or GetTime())
			local summary = string.format("Send complete: %d chunks, %d bytes in %.1fs", sendStats.chunksSent, totalBytes, elapsed)
			if sendStats.failures > 0 or sendStats.throttled > 0 then
				summary = summary .. string.format(" | failures: %d, throttled: %d", sendStats.failures, sendStats.throttled)
			end

			GBCR.Output:Debug("CHUNK", summary)
			if altName == GBCR.Guild:GetNormalizedPlayer() then
				GBCR.Output:Response("Finished sending your latest data%s.", destination and string.format(" to %s", GBCR.Output:ColorPlayerName(destination)) or " to the guild")
			else
				GBCR.Output:Info("Finished sending data for %s%s.", GBCR.Output:ColorPlayerName(altName), destination and string.format(" to %s", GBCR.Output:ColorPlayerName(destination)))
			end

			-- Decrement peer send queue counter
            -- TODO: make use of Constants.LIMITS.MAX_PENDING_SENDS
			if Protocol.pendingSendCount > 0 then
				Protocol.pendingSendCount = Protocol.pendingSendCount - 1
				GBCR.Output:Debug("CHUNK", "Send completed, queue now: %d/%d", Protocol.pendingSendCount, Constants.LIMITS.MAX_PENDING_SENDS)
			end

			-- Warn on failures
			if sendStats.failures > 0 then
				GBCR.Output:Debug("CHUNK", "WARNING: %d send failures occurred!", sendStats.failures)
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

function Protocol:SendData(name, target)
	if not name then
		return
	end

    if not GBCR.Database.savedVariables or not GBCR.Database.savedVariables.name then
        GBCR.Output:Debug("SYNC", "SendData: early exit because GBCR.Database.savedVariables was not loaded for %s", name)

        return
    end

    if not GBCR.Database.savedVariables.alts then
        GBCR.Output:Debug("SYNC", "SendData: early exit because GBCR.Database.savedVariables.alts table does not exist for %s", name)

        return
    end

	local norm = GBCR.Guild:NormalizeName(name) or name
    local currentAlt = GBCR.Database.savedVariables.alts[norm]
    if not currentAlt then
        GBCR.Output:Debug("SYNC", "SendData: early exit because no data exists for guild bank alt %s (norm=%s)", name, norm)

         return
     end

    if not self:HasAltData(currentAlt) then
        GBCR.Output:Debug("SYNC", "SendData: early exit because no valid data exists for guild bank alt %s", norm)

        return
    end

	local channel = target and "WHISPER" or "GUILD"
    local dest = target or nil
	local itemsCount = currentAlt.items and #currentAlt.items or 0
	GBCR.Output:Debug("SYNC", "SendData: sending %d items for guild bank alt %s to %s", itemsCount, norm, dest or "guild")

	local onChunkSent = Protocol:CreateOnChunkSentCallback(norm, dest)
	local craftedPayload = Protocol:CraftDataPayload(norm, currentAlt)

	if not craftedPayload then
		GBCR.Output:Debug("SYNC", "SendData: skipped sending guild bank alt %s to %s, no valid payload", norm, dest or "guild")

		return
	end

	local data = GBCR.Core:SerializePayload(craftedPayload)
	if channel == "WHISPER" and dest then
		GBCR.Core:SendWhisper("gbc-data-share", data, dest, "NORMAL", onChunkSent)
	else
		GBCR.Core:SendCommMessage("gbc-data-share", data, "Guild", nil, "BULK", onChunkSent)
	end

	GBCR.Output:Debug("SYNC", "SendData: sent full data for %s (%d bytes)", norm, string.len(data or ""))
end

--- RECEIVE:

function Protocol:ReceiveData(incomingData, sender)
	if not GBCR.Database.savedVariables then
        GBCR.Output:Debug("SYNC", "ReceiveData: early exit because GBCR.Database.savedVariables was not loaded")

		return Constants.ADOPTION_STATUS.IGNORED
	end

    local parsedPayload = self:ParseDataPayload(incomingData)

    local incomingAddonVersionNumber = parsedPayload.incomingAddonVersionNumber
    local incomingAltName = parsedPayload.altName
    local incomingVersion = parsedPayload.version
    local incomingMoney = parsedPayload.money
    local incomingNumLedgerEntries = parsedPayload.numLedgerEntries
    local incomingLedger = parsedPayload.ledger
    local incomingNumItems = parsedPayload.numItems
    local incomingItems = parsedPayload.items
    local incomingNumRequests = parsedPayload.numRequests
    local incomingRequests = parsedPayload.requests

    -- Track sender metadata
    self:TrackSenderMetadata(sender, incomingAddonVersionNumber or nil, nil, nil)

	GBCR.Output:Debug("SYNC", "ReceiveData: processing %d items for %s", incomingNumItems, incomingAltName)

	local playerNorm = GBCR.Guild:GetNormalizedPlayer()
	local isOwnData = playerNorm == incomingAltName
	if isOwnData then
		GBCR.Output:Debug("SYNC", "ReceiveData: rejected data about ourselves")

		return Constants.ADOPTION_STATUS.UNAUTHORIZED
	end

	local existing = GBCR.Database.savedVariables.alts[incomingAltName]
	local existingVersion = existing and existing.version or nil
	if incomingVersion and existingVersion then
		if incomingVersion <= existingVersion then
			GBCR.Output:Debug("SYNC", "ReceiveData: rejecting %s (incomingVersion=%d <= existingVersion=%d)", incomingAltName, incomingVersion, existingVersion)

			return Constants.ADOPTION_STATUS.STALE
		end
	end

	if GBCR.Guild.hasRequested then
		if GBCR.Guild.requestCount == nil then
			GBCR.Guild.requestCount = 0
		else
			GBCR.Guild.requestCount = GBCR.Guild.requestCount - 1
		end
		if GBCR.Guild.requestCount == 0 then
			GBCR.Guild.hasRequested = false
		end
	end

	if not GBCR.Database.savedVariables.alts then
		GBCR.Database.savedVariables.alts = {}
	end
	GBCR.Database.savedVariables.alts[incomingAltName].version = incomingVersion
	GBCR.Database.savedVariables.alts[incomingAltName].money = incomingMoney
	GBCR.Database.savedVariables.alts[incomingAltName].ledger = incomingLedger
	GBCR.Database.savedVariables.alts[incomingAltName].items = incomingItems
	GBCR.Database.savedVariables.alts[incomingAltName].requests = incomingRequests
	GBCR.Output:Debug("SYNC", "ReceiveData: accepted and saved guild bank alt data for %s", incomingAltName)

    GBCR.UI.Inventory.searchDataBuilt = false

	if incomingItems then
		self:ReconstructItemLinks(incomingItems)
	end

	return Constants.ADOPTION_STATUS.ADOPTED
end

--- =========================================== ---
--- DATA (gbc-data-share and gbc-data-query) ---

--- CRAFT:

--- SEND:

-- Query for guild bank alt to specific target or entire guild since GBCR.Guild:RequestMissingGuildBankAltData() provides no target
function Protocol:QueryForGuildBankAltData(target, altName)
	if not GBCR.Guild:IsQueryAllowed() then
		return
	end

	if not target then
		local guildBankAlt = nil
		for member, _ in pairs(GBCR.Guild:GetOnlineGuildBankAlts()) do
			if GBCR.Guild:IsGuildBankAlt(member) and member ~= GBCR.Guild:GetNormalizedPlayer() then
				if not guildBankAlt then
					guildBankAlt = member
					break
				end
			end
		end

		local onlinePeer = nil
		if not guildBankAlt then
			for guildMember in pairs(Protocol.guildMembersFingerprintData or {}) do
				if guildMember ~= GBCR.Guild:GetNormalizedPlayer() and GBCR.Guild:IsPlayerOnlineMember(guildMember) then
					if not onlinePeer then
						onlinePeer = guildMember
						break
					end
				end
			end
		end

		target = guildBankAlt or onlinePeer
	end

	GBCR.Output:Debug("SYNC", "Querying %s for %s", target and GBCR.Output:ColorPlayerName(target) or "guild", GBCR.Output:ColorPlayerName(altName))
	local payload = { name = altName, requester = GBCR.Guild:GetNormalizedPlayer() }
	local data = GBCR.Core:SerializePayload(payload)
	if target and GBCR.Core:SendWhisper("gbc-data-query", data, target, "NORMAL") then
		self:MarkPendingSync("alt", target, altName)

		return
	end

	-- Fallback: broadcast to the guild
	GBCR.Core:SendCommMessage("gbc-data-query", data, "GUILD", nil, "NORMAL")
	self:MarkPendingSync("alt", "guild", altName)
end

--- RECEIVE:

--- =========================================== ---
--- ROSTER (gbc-roster-share and gbc-roster-query) ---

--- CRAFT:

--- SEND:

function Protocol:SendRoster(target)
	if not GBCR.Database.savedVariables or not GBCR.Database.savedVariables.roster or not GBCR.Database.savedVariables.roster.alts then
		GBCR.Output:Debug("ROSTER", "SendRoster: skipped, no roster data available")

		return
	end

	local payload = { roster = GBCR.Database.savedVariables.roster }
	local data = GBCR.Core:SerializePayload(payload)
	if target and GBCR.Core:SendWhisper("gbc-roster-share", data, target, "BULK") then
		return
	end

	-- Fallback: broadcast to the guild
	GBCR.Core:SendCommMessage("gbc-roster-share", data, "Guild", nil, "BULK")
end

-- Create and send latest version of the roster after enabling a new guild bank alt or /bank roster
function Protocol:AuthorRosterData()
	if GBCR.Guild.isAnyoneAuthority then
	 	GBCR.Output:Response("All guild members can view officer notes and have an accurate roster of guild bank alts.")

		return
	end

    local rosterGuildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
	if not GBCR.Guild.isAnyoneAuthority and GBCR.Guild.canWeViewOfficerNotes then
		self:SendRoster()
		if rosterGuildBankAlts then
			local characterNames = {}
			for i = 1, #rosterGuildBankAlts do
				local guildBankAltName = rosterGuildBankAlts[i]
				table.insert(characterNames, guildBankAltName)
			end
			if #characterNames > 0 then
				GBCR.Output:Response("Sent updated roster containing the follow banks: " .. table.concat(characterNames, ", ") .. ".")
			else
				GBCR.Output:Response("Sent empty roster.")
			end
		else
			GBCR.Output:Response("Sent empty roster.")
		end
	else
		GBCR.Output:Response("You lack permissions to share the roster. Only players that can view officer notes are permitted.")

		return
	end
end

--- RECEIVE:

-- Query for roster data
function Protocol:QueryForRosterData(target, incomingRosterVersion)
	if not Protocol:IsQueryAllowed() then
		return
	end

	self:MarkPendingSync("roster", target)

	GBCR.Output:Debug("SYNC", "Querying %s for roster (incomingRosterVersion=%d)", GBCR.Output:ColorPlayerName(target), incomingRosterVersion)

	local payload = { version = incomingRosterVersion }
	local data = GBCR.Core:SerializePayload(payload)
	if target and GBCR.Core:SendWhisper("gbc-roster-query", data, target, "NORMAL") then
		self:MarkPendingSync("roster", target)

		return
	end

	-- Fallback: broadcast to the guild
	GBCR.Core:SendCommMessage("gbc-roster-query", data, "Guild", nil, "NORMAL")
	self:MarkPendingSync("roster", "guild")
end

--- =========================================== ---
--- HELLO (gbc-h and gbc-r) ---

--- CRAFT:

--- SEND:

-- /bank hello, or upon receipt of "gbc-h" (type = "reply")
-- Broadcast "gbc-h" to guild
-- Print output to ourselves
function Protocol:Hello(type)
	local currentData = GBCR.Database.savedVariables
    if not currentData then
        return
    end

    local currentPlayer = GBCR.Guild:GetNormalizedPlayer()
    local playerClass = GBCR.Guild:GetGuildMemberInfo(currentPlayer)
    local _, _, _, classColor = GetClassColor(playerClass)
    local helloParts = { "Hi! ", GBCR.Globals:Colorize(classColor, currentPlayer), " is using version ", GBCR.Globals:Colorize(colorGold, GBCR.Core.addonVersionNumber), "." }
    local rosterCount = Globals:Count(currentData.roster)
    local altsCount = Globals:Count(currentData.alts)

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
            if v and v.items and Globals:Count(v.items) > 0 then
                table.insert(guildBankList, k)
            end
        end
        local guildBankAlts = #guildBankList > 0 and " (" .. table.concat(guildBankList, ", ") .. ")" or ""

        local pluralRosterAlts = (rosterList ~= 1 and "s" or "")
        local pluralGuildBankAlts = (guildBankList ~= 1 and "s" or "")
        if currentData.roster.alts then
            table.insert(helloParts, "\n")
            table.insert(helloParts, "I know about " .. GBCR.Globals:Colorize(colorGold, #rosterList) .. " guild bank alt" .. pluralRosterAlts .. rosterAlts .. " on the roster.")
            table.insert(helloParts, "\n")
            table.insert(helloParts, "I have guild bank data from " .. GBCR.Globals:Colorize(colorGold, #guildBankList) .. " alt" .. pluralGuildBankAlts .. guildBankAlts .. ".")
        end
    else
        table.insert(helloParts, " I know about " .. GBCR.Globals:Colorize(colorGold, 0) .. " guild bank alts on the roster, and have guild bank data from " .. GBCR.Globals:Colorize(colorGold, 0) .. " alts.")
    end

    local hello = table.concat(helloParts)
    local data = GBCR.Core:SerializePayload(hello)
    if type ~= "reply" then
        GBCR.Output:Info(hello)
        GBCR.Core:SendCommMessage("gbc-h", data, "Guild", nil, "BULK")
    else
        GBCR.Core:SendCommMessage("gbc-hr", data, "Guild", nil, "BULK")
    end
end

--- RECEIVE:

--- =========================================== ---
--- SHARE (gbc-s and gbc-sr) ---

--- CRAFT:

--- SEND:

-- /bank share + after Bank:Scan() + Events:OnShareTimer() every 3 minutes (TIMER_INTERVALS.VERSION_BROADCAST) + once every 30 seconds if UI inventory is empty
function Protocol:Share(type)
    local guildName = GBCR.Guild:GetGuildName()
	if not guildName then
		return
	end

	if GBCR.Database.savedVariables and GBCR.Database.savedVariables.name == guildName then
		local normPlayer = GBCR.Guild:GetNormalizedPlayer()
		local share = "I'm sharing my bank data. Share yours please."

		if not GBCR.Database.savedVariables.alts[normPlayer] then
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
		-- 	version timestamp
		self:SendFingerprint()

		local data = GBCR.Core:SerializePayload(share)
		if type ~= "reply" then
			GBCR.Core:SendCommMessage("gbc-s", data, "Guild", nil, "NORMAL")
		else
			GBCR.Core:SendCommMessage("gbc-sr", data, "Guild", nil, "NORMAL")
		end
	end
end

--- RECEIVE:

--- =========================================== ---
--- WIPE (gbc-w and gbc-wr) ---

--- CRAFT:

--- SEND:

-- Wipe every online members' data: /bank wipeall (only by officers)
function Protocol:Wipe(type)
    local guild = GBCR.Guild:GetGuildName()
	if not guild and not GBCR.Guild.canWeEditOfficerNote then
		return
	end

    local wipe = "I wiped all addon data from " .. guild .. "."
    GBCR.Guild:Reset(guild)

	local data = GBCR.Core:SerializePayload(wipe)
    if type ~= "reply" then
        GBCR.Core:SendCommMessage("gbc-w", data, "Guild", nil, "BULK")
    else
        GBCR.Core:SendCommMessage("gbc-wr", data, "Guild", nil, "BULK")
    end
end

--- RECEIVE:

--- =========================================== ---
--- === SYNC ===

function Protocol:MarkPendingSync(syncType, sender, name)
	if not syncType or not sender then
		return
	end

	local now = GetServerTime()
	local normSender = GBCR.Guild:NormalizeName(sender) or sender
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
		local normName = GBCR.Guild:NormalizeName(name) or name
		if self.pendingSync.alts and normName and not self.pendingSync.alts[normName] then
			self.pendingSync.alts[normName] = {}
		end
		if self.pendingSync.alts and normName and normSender and self.pendingSync.alts[normName] then
			self.pendingSync.alts[normName][normSender] = now
		end
	end
end

function Protocol:ConsumePendingSync(syncType, sender, name)
	if not syncType or not sender then
		return false
	end

	if not self.pendingSync then
		return false
	end

	local now = GetServerTime()
	local normSender = GBCR.Guild:NormalizeName(sender) or sender

	if syncType == "roster" then
		local roster = self.pendingSync.roster
		local versionTimestamp = roster and roster[normSender]
		if versionTimestamp and now - versionTimestamp <= Constants.TIMER_INTERVALS.VERSION_BROADCAST then
			roster[normSender] = nil

			return true
		end
		if versionTimestamp then
			roster[normSender] = nil
		end

		return false
	end

	if syncType == "alt" and name then
		local normName = GBCR.Guild:NormalizeName(name) or name
		local alts = self.pendingSync.alts and self.pendingSync.alts[normName]
		local versionTimestamp = alts and alts[normSender]
		if versionTimestamp and now - versionTimestamp <= Constants.TIMER_INTERVALS.VERSION_BROADCAST then
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

--- =========================================== ---
--- === ITEM RECNSTRUCTION ===

local function createTemporaryItemLink(encoded)
    if not encoded or encoded == "" then return nil end

    local fields = GBCR.Inventory:SplitItemString(encoded)

    local itemId = fields[1]
    if not itemId then return nil end

    local enchant = fields[2] or "0"
    local suffix = fields[3] or "0"

    local itemString = string.format("item:%d:%s:0:0:0:0:%s:0:0:0:0:0:0", itemId, enchant, suffix)
    local temporaryLink = string.format(GBCR.Globals:Colorize(colorWhite, "|H%s|h[item:%d]|h"), itemString, itemId)

    return temporaryLink
end

function Protocol:ProcessItemQueue()
	if #self.itemReconstructQueue == 0 then
		self.isProcessingQueue = false

		return
	end

	-- Process a batch of items
	local processCount = math.min(Constants.LIMITS.BATCH_SIZE, #self.itemReconstructQueue)

	for i = 1, processCount do
		local item = table.remove(self.itemReconstructQueue, 1)
		if item and item.itemId and not item.itemLink then
			local itemLink = select(2, GetItemInfo(item.itemId))
			if itemLink and not item.itemString then
				item.itemLink = itemLink
			else
				if self.pendingAsyncLoads < Constants.LIMITS.MAX_CONCURRENT_ASYNC then
					self.pendingAsyncLoads = self.pendingAsyncLoads + 1
					local itemObj, tempItemLink
                    if item.itemString then
                        tempItemLink = createTemporaryItemLink(item.itemString)
                        itemObj = Item:CreateFromItemLink(tempItemLink)
                    else
                        itemObj = Item:CreateFromItemID(item.itemId)
                    end
					GBCR.Output:Debug("ITEM", "Loading item %d: itemObj=%s", item.itemId or -1, tostring(itemObj))

					if itemObj then
						GBCR.Output:Debug("ITEM", "Item %d passed validation, calling ContinueOnItemLoad", item.itemId)
						local success, err = pcall(function()
							itemObj:ContinueOnItemLoad(function()
								self.pendingAsyncLoads = self.pendingAsyncLoads - 1
                                local name, link
                                if tempItemLink then
                                    name, link = GetItemInfo(tempItemLink)
                                else
                                    name, link = GetItemInfo(item.itemId)
                                end
                                if name and link then
                                    item.itemLink = link
                                    item.itemString = nil
								end
							end)
						end)
						if not success then
							GBCR.Output:Debug("ITEM", "ContinueOnItemLoad crashed for item %d: %s", item.itemId, tostring(err))
							self.pendingAsyncLoads = self.pendingAsyncLoads - 1
						end
					else
						GBCR.Output:Debug("ITEM", "Item %d failed validation, skipping", item.itemId or -1)
						self.pendingAsyncLoads = self.pendingAsyncLoads - 1
					end
				else
					table.insert(self.itemReconstructQueue, item)
				end
			end
		end
	end

    GBCR.UI:QueueUIRefresh()

	if #self.itemReconstructQueue > 0 then
		After(Constants.TIMER_INTERVALS.BATCH_DELAY, function()
            self:ProcessItemQueue()
        end)
	else
		self.isProcessingQueue = false
	end
end

-- Reconstruct single itemLink (immediate, synchronous only)
function Protocol:ReconstructItemLink(item)
	if not item or not item.itemId or item.itemLink then
		return
	end

	-- Try synchronous reconstruction from cache only
	local itemLink = select(2, GetItemInfo(item.itemId))
	if itemLink then
		item.itemLink = itemLink
	end
end

-- Reconstruct itemLink fields after receiving data
-- Calls GetItemInfo() to recreate links from itemId
-- Queued/batched to prevent stuttering
function Protocol:ReconstructItemLinks(items)
	if not items then
		return
	end

	-- Add all items without links to queue for async loading
	-- Items already in cache will load synchronously and won't need async
	for _, item in ipairs(items) do
		if item and item.itemId and not item.itemLink then
			table.insert(self.itemReconstructQueue, item)
		end
	end

	-- Start processing queue if not already running
	if not self.isProcessingQueue and #self.itemReconstructQueue > 0 then
		self.isProcessingQueue = true
		Protocol:ProcessItemQueue()
	end
end

--- =========================================== ---
--- ===

function Protocol:HasAltData(alt)
	if not alt or type(alt) ~= "table" then
		return false
	end

	if alt.version and alt.version > 0 then
		return true
	end

	return false
end

function Protocol:HasAltContent(alt, altName)
	if not alt or type(alt) ~= "table" then
		GBCR.Output:Debug("SYNC", "Type check for %s: not a table", altName or (alt and alt.name) or "unknown")

		return false
	end

	local hasItems = alt.items and next(alt.items)
    local result = hasItems
    GBCR.Output:Debug("SYNC", "Content check for %s: items=%s (%d) => %s", altName or alt.name or "unknown", tostring(hasItems and "Y" or "N"), alt.items and #alt.items or 0, tostring(result))

	return result
end

--- =========================================== ---
--- ===

function Protocol:TrackSenderMetadata(sender, incomingAddonVersionNumber, incomingIsGuildBankAlt, incomingRosterVersionTimestamp)
    if incomingAddonVersionNumber then
        self.guildMembersFingerprintData[sender] = {
            addonVersionNumber = incomingAddonVersionNumber,
            seen = GetServerTime()
        }
        if incomingIsGuildBankAlt then
            self.guildMembersFingerprintData[sender].isGuildBankAlt = incomingIsGuildBankAlt
        end
        if incomingRosterVersionTimestamp then
            self.guildMembersFingerprintData[sender].rosterVersionTimestamp = incomingRosterVersionTimestamp
        end
		GBCR.Output:Debug("ROSTER", "Tracking member %s with addon version %s (isGuildBankAlt=%s, rosterVersionTimestamp=%s)", GBCR.Output:ColorPlayerName(sender), tostring(incomingAddonVersionNumber), tostring(incomingIsGuildBankAlt), tostring(incomingRosterVersionTimestamp))

		-- Addon version check
		if incomingAddonVersionNumber > GBCR.Core.addonVersionNumber then
			if not self.isAddonOutdated then
				-- Only make the callout once per session
				self.isAddonOutdated = true
				GBCR.Output:Response("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived")
				GBCR.Core:LoadMetadata()
			end
		end
    end
end