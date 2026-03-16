GBankClassic_Chat = GBankClassic_Chat or {}

local Chat = GBankClassic_Chat
local preDebugLogLevel = nil

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("time", "debugprofilestop")
local time = upvalues.time
local debugprofilestop = upvalues.debugprofilestop
local upvalues = Globals.GetUpvalues("GetClassColor", "IsInRaid", "IsInInstance", "GetServerTime", "GetAddOnMetadata")
local GetClassColor = upvalues.GetClassColor
local IsInRaid = upvalues.IsInRaid
local IsInInstance = upvalues.IsInInstance
local GetServerTime = upvalues.GetServerTime
local GetAddOnMetadata = upvalues.GetAddOnMetadata

function Chat:Init()
	GBankClassic_Output:Debug("PROTOCOL", "GBankClassic_Chat:Init() starting")
    GBankClassic_Core:RegisterChatCommand("bank", function(input)
        return self:ChatCommand(input)
    end)

    self.isAddonOutdated = false
	self.guildMembersAddonVersion = {}
	self.onlineGuildBankAlts = {}
	self.lastRosterSync = nil
	self.lastGuildBankAltSync = {}
	self.syncQueue = {}
	self.isSyncing = false
	self.pendingMessages = {}

    -- Data
	GBankClassic_Core:RegisterComm("gbank-d", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)

	-- Fingerprint
	GBankClassic_Core:RegisterComm("gbank-dv2", function(prefix, message, distribution, sender)
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

    -- State summary
	GBankClassic_Core:RegisterComm("gbank-state", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
    -- No change
	GBankClassic_Core:RegisterComm("gbank-nochange", function(prefix, message, distribution, sender)
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

	--[[
	-- Request-specific message handlers
	GBankClassic_Core:RegisterComm("gbank-rm", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
	GBankClassic_Core:RegisterComm("gbank-rq", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
	GBankClassic_Core:RegisterComm("gbank-rd", function(prefix, message, distribution, sender)
		self:OnCommReceived(prefix, message, distribution, sender)
	end)
	]]--
end

-- Centralized sync function for both /sync command and UI opening
function Chat:PerformSync()
	GBankClassic_Guild:ShareAllGuildBankAltData("ALERT")
	GBankClassic_Guild:RequestMissingGuildBankAltData()
	-- GBankClassic_Guild:QueryRequestsIndex(nil, "ALERT")
end

local SHARES_COLOR = "|cff80bfffshares|r"
local QUERIES_COLOR = "|cffffff00queries|r"

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

-- Only accept alt data if guild bank alt is in fact a guild bank alt in the current guild bank alt roster
function Chat:IsAltDataAllowed(sender, claimedNorm)
	-- Check if claimed alt is in the current guild's bank alt roster
	if not GBankClassic_Guild:IsGuildBankAlt(claimedNorm) then
		GBankClassic_Output:Debug("PROTOCOL", "Rejecting alt data for %s: not a guild bank alt in current guild bank alt roster", claimedNorm)

		return false
	end

	return true
end

-- Process fingerprint broadcast (gbank-dv2)
function Chat:ProcessVersionBroadcast(prefix, data, sender, message, distribution)
	-- Show what data we received
	local altCount = data.alts and GBankClassic_Globals:Count(data.alts)
	GBankClassic_Output:Debug("PROTOCOL", "%s from %s: has data.alts=%s, alts count=%d", prefix, sender, tostring(data.alts ~= nil), altCount)

	local current_data = GBankClassic_Guild:GetVersion()
	if current_data then
		if data.name then
			if current_data.name ~= data.name then
				return
			end
		end
		if data.addon then
			-- Track this user's addon version
			if not self.guildMembersAddonVersion then
				self.guildMembersAddonVersion = {}
			end
			self.guildMembersAddonVersion[sender] = {
				version = data.addon,
				seen = time(),
			}

			-- Track online guild bank alts for pull-based protocol
			if data.isGuildBankAlt then
				if not self.onlineGuildBankAlts then
					self.onlineGuildBankAlts = {}
				end
				self.onlineGuildBankAlts[sender] = {
					seen = time(),
					version = data.addon,
				}
				GBankClassic_Output:Debug("ROSTER", "Tracked online guild bank alt: %s", sender)
			end

			-- Track protocol capabilities
			local protocolVersion = data.protocol_version or 1
			GBankClassic_Database:UpdatePeerProtocol(current_data.name, sender, protocolVersion)

			if current_data.addon and data.addon > current_data.addon then
				if not self.isAddonOutdated then
					-- Only make the callout once per session
					self.isAddonOutdated = true
					GBankClassic_Output:Info("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived")
				end
			end
		end
		if data.roster then
			if current_data.roster == nil or data.roster > current_data.roster then
				GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), "has fresher roster data, querying.")
				GBankClassic_Guild:QueryRoster(sender, data.roster)
			end
		end
		if data.alts then
			GBankClassic_Output:Debug("PROTOCOL", "Processing %d alts from %s", altCount, sender)
			for k, v in pairs(data.alts) do
				local kNorm = GBankClassic_Guild:NormalizeName(k) or k
				local ourAlt = (GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[kNorm]) or current_data.alts[kNorm]

				-- Handle both old format (number) and new format (table with version+hash)
				-- See Guild:GetVersion() to understand what is a part of data.alts (v)
				local theirVersion = type(v) == "table" and v.version or v
				local theirHash = type(v) == "table" and v.hash or nil
				local ourVersion = type(ourAlt) == "table" and ourAlt.version or nil
				local ourHash = type(ourAlt) == "table" and ourAlt.inventoryHash or nil

				-- Always log hash comparisons
				if theirHash then
					GBankClassic_Output:Debug("PROTOCOL", "Received %s from %s: theirVer=%d, theirHash=%d, ourVer=%s, ourHash=%s", kNorm, sender, theirVersion, theirHash, ourVersion and tostring(ourVersion) or "nil", ourHash and tostring(ourHash) or "nil")
				end

				-- Don't query if we are the sender ourselves
				local ourPlayer = GBankClassic_Guild:GetNormalizedPlayer()
				local senderNorm = GBankClassic_Guild:NormalizeName(sender) or sender
				local weAreSender = (ourPlayer == senderNorm)

				-- Log the sender check
				GBankClassic_Output:Debug("PROTOCOL", "Sender check for %s: ourPlayer=%s, senderNorm=%s, weAreSender=%s", kNorm, ourPlayer, senderNorm, tostring(weAreSender))

				if not weAreSender then
					-- We're not the sender, so we can query about any alt including the sender
					local shouldQuery = false
					-- Log query decision path
					GBankClassic_Output:Debug("PROTOCOL", "Query evaluation for %s", kNorm)

					-- Hash-based comparison (most accurate)
					if theirHash then
						if not ourHash then
							-- They have data, we don't - query
							shouldQuery = true
							GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), "has bank data for", self:ColorPlayerName(kNorm) .. " (we have none), querying.")
							GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: we don't have data, query", kNorm)
						elseif theirHash ~= ourHash then
							-- Hash differs - we need an update
							shouldQuery = true
							local reason = (theirHash ~= ourHash) and "inventory" or "mail"
							GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), "has different " .. reason .. " for", self:ColorPlayerName(kNorm) .. " (hash mismatch), querying.")
							GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: %s hash differs, query (ourHash=%d, theirHash=%d)", kNorm, reason, ourHash, theirHash)
						else
							GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: hash matches our content, don't query", kNorm)
						end
					elseif not ourVersion or theirVersion > ourVersion then
						-- No hash available, fall back to version comparison
						shouldQuery = true
						GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), "has fresher bank data about", self:ColorPlayerName(kNorm) .. ", querying.")
						GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: their version is newer, query", kNorm)
					else
						GBankClassic_Output:Debug("PROTOCOL", "Query decision for %s: their version is same or older, don't query", kNorm)
					end

					if shouldQuery then
						GBankClassic_Output:Debug("PROTOCOL", "Querying %s from %s (reason: version broadcast mismatch)", kNorm, sender)
						GBankClassic_Guild:QueryAltPullBased(kNorm)
					end
				end
			end
		end
	end
end

function Chat:OnCommReceived(prefix, message, distribution, sender)
	local prefixDesc = COMM_PREFIX_DESCRIPTIONS[prefix] or "(Unknown)"
	local player = GBankClassic_Guild:GetNormalizedPlayer()
	sender = GBankClassic_Guild:NormalizeName(sender) or sender

	GBankClassic_Output:DebugComm("Received: %s via %s from %s (%d bytes)", prefix, string.upper(distribution), sender, #message)

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("PROTOCOL", "> (ignoring)", prefix, prefixDesc, "from", self:ColorPlayerName(sender), "(in instance or raid)")

		return
	end

	if player == sender then
		GBankClassic_Output:Debug("PROTOCOL", "> (ignoring)", prefix, prefixDesc, "(our own)")

		return
	end

	local success, data = GBankClassic_Core:DeserializeWithChecksum(message)
	if not success then
		GBankClassic_Output:Debug("PROTOCOL", "> (error)", prefix, prefixDesc, "from", self:ColorPlayerName(sender), "(failed to deserialize, error=" .. tostring(data) .. ")")

        return
	end

	GBankClassic_Output:Debug("PROTOCOL", ">", self:ColorPlayerName(sender), ">", prefix, prefixDesc, data.type and ", type=" .. tostring(data and data.type) or "")

	if prefix == "gbank-dv2" then
		local altCount = data and data.alts and GBankClassic_Globals:Count(data.alts)
		GBankClassic_Output:Debug("PROTOCOL", "%s from %s: success=%s, has data=%s, has data.alts=%s, altCount=%d", prefix, sender, tostring(success), tostring(data ~= nil), tostring(data and data.alts ~= nil), altCount)
		self:ProcessVersionBroadcast(prefix, data, sender, message, distribution)

		return
	end

	if prefix == "gbank-r" then
		-- Check if this is a pull-based request (has type == "alt-request")
		if data.type == "alt-request" then
			-- Pull-based request flow - respond with gbank-rr acknowledgment
			local altName = data.name

			GBankClassic_Output:DebugComm("Received pull-based alt-request from %s for alt %s", sender, altName)
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), QUERIES_COLOR, "pull-based request for", self:ColorPlayerName(altName))

			-- Check if we have this alt
			local isGuildBankAlt = player and GBankClassic_Guild:IsGuildBankAlt(player) or false
			local hasData = GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[altName] ~= nil

			-- Respond to pull-based requests
			if hasData then
				if (isGuildBankAlt and player == altName) or not GBankClassic_Guild:IsPlayerOnlineGuildBankAlt(altName) then
					local ack = {
						type = "alt-request-reply",
						name = altName,
						isGuildBankAlt = isGuildBankAlt,
						hasData = hasData,
					}
					local ackData = GBankClassic_Core:SerializeWithChecksum(ack)
					GBankClassic_Output:DebugComm("Sending acknowledgement: gbank-rr via whisper to %s (isGuildBankAlt=%s, hasData=%s)", sender, tostring(isGuildBankAlt), tostring(hasData))
					if not GBankClassic_Core:SendWhisper("gbank-rr", ackData, sender, "NORMAL") then
						return
					end
					GBankClassic_Output:Debug("SYNC", "<", "Sent gbank-rr to", self:ColorPlayerName(sender), string.format("(isGuildBankAlt=%s, hasData=%s)", tostring(isGuildBankAlt), tostring(hasData)))
				end
			else
				-- Don't respond if we don't have the data
				GBankClassic_Output:Debug("SYNC", "Ignoring pull-based request (no data for %s)", altName)
			end

			return
		end

		--[[
		-- Legacy request handling
		if data.player then
			-- Use REQUESTS category for request-related queries, SYNC for alt queries
			local isRequestQuery = data.type and string.find(data.type, "^requests") ~= nil
			local category = isRequestQuery and "REQUESTS" or "SYNC"
			GBankClassic_Output:Debug(category, ">", self:ColorPlayerName(sender), QUERIES_COLOR, isRequestQuery and "Requests:" or "Sync:", data.type, data.name and self:ColorPlayerName(GBankClassic_Guild:NormalizeName(data.name)) or "")

			-- Request data is guild-wide, anyone can respond (player="*")
			if data.type == "requests" then
				local matches = (data.player == "*" or data.player == player)
				GBankClassic_Output:DebugComm("Handler check: type=requests, player=%s, myName=%s, matches=%s", tostring(data.player), tostring(player), tostring(matches))
				if matches then
					GBankClassic_Output:DebugComm("Responding to requests query")
					GBankClassic_Guild:SendRequestsSnapshot(sender)
				end
			end
			if data.type == "requests-index" then
				local matches = (data.player == "*" or data.player == player)
				if matches then
					-- If hashes match, querier already has exactly what we have - stay silent
					local myHash = GBankClassic_Guild:GetRequestsHash()
					local querierHash = tonumber(data.hash) or 0
					if querierHash == 0 or myHash ~= querierHash then
						GBankClassic_Output:DebugComm("Responding to requests-index query (hash mismatch: mine=%d theirs=%d)", myHash, querierHash)
						GBankClassic_Guild:SendRequestsIndex(sender)
					else
						GBankClassic_Output:DebugComm("Skipping (hash match %d, querier already in sync)", myHash)
					end
				end
			end
			if data.type == "requests-by-id" then
				local matches = (data.player == "*" or data.player == player)
				if matches then
					GBankClassic_Output:DebugComm("Responding to requests-by-id query")
					GBankClassic_Guild:SendRequestsById(sender, data.ids)
				end
			end
			if data.type == "requests-log" then
				-- Legacy query type - respond with full snapshot
				local matches = (data.player == "*" or data.player == player)
				if matches then
					GBankClassic_Output:DebugComm("Responding with snapshot (log queries deprecated)")
					GBankClassic_Guild:SendRequestsSnapshot(sender)
				end
			end
		end
		]]--

		-- Alt and roster queries are per-player, only respond if query is for us
		if data.player and data.player == player then
			-- Roster query: keep because some players may be unable to know about guild bank alts defined in officer notes
			if data.type == "roster" then
				local time = GetServerTime()
				if self.lastRosterSync == nil or time - self.lastRosterSync > 300 then
					self.lastRosterSync = time
					GBankClassic_Guild:SendRosterData()
				end
			end

			if data.type == "alt" then
				local nameNorm = GBankClassic_Guild:NormalizeName(data.name)
				table.insert(self.syncQueue, nameNorm)
				if not self.isSyncing then
					self:ProcessQueue()
				end
			end
		end
	end

	-- Pull-based request reply handler (gbank-rr)
	if prefix == "gbank-rr" then
		if data.type == "alt-request-reply" then
			local altName = data.name
			local isGuildBankAlt = data.isGuildBankAlt or false
			local hasData = data.hasData or false

			GBankClassic_Output:DebugComm("Received acknowledgment: gbank-rr from %s for alt %s (isGuildBankAlt=%s, hasData=%s)", sender, altName, tostring(isGuildBankAlt), tostring(hasData))
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), QUERIES_COLOR, string.format("acknowledged request for %s (altName=%s, hasData=%s)", self:ColorPlayerName(altName), tostring(isGuildBankAlt), tostring(hasData)))

			-- If sender has the data, send our state summary to them
			if hasData then
				GBankClassic_Output:DebugComm("Calling SendStateSummary for %s to %s", altName, sender)
				GBankClassic_Guild:SendStateSummary(altName, sender)
			else
				GBankClassic_Output:DebugComm("Not sending state summary (hasData=false)")
			end
		end
	end

	-- State summary handler (gbank-state)
	if prefix == "gbank-state" then
		if data.type == "state-summary" then
			local altName = data.name
			local summary = data.summary

			GBankClassic_Output:DebugComm("Received state summary from %s for alt %s (hash=%s, version=%s)", sender, altName, tostring(summary and summary.hash), tostring(summary and summary.version))
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), QUERIES_COLOR, string.format("received state summary for %s", self:ColorPlayerName(altName)))

			-- Compute and send response
			GBankClassic_Output:DebugComm("Calling RespondToStateSummary for %s from %s", altName, sender)
			GBankClassic_Guild:RespondToStateSummary(altName, summary, sender)
		end
	end

	-- No-change handler (gbank-nochange)
	if prefix == "gbank-nochange" then
		if data.type == "no-change" then
			local altName = data.name
			local version = data.version or 0

			GBankClassic_Output:DebugComm("Received no-change from %s for alt %s (version=%d)", sender, altName, version)
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), QUERIES_COLOR, string.format("no changes for %s (v%d)", self:ColorPlayerName(altName), version))

			-- If the responder sends corrected hash values, apply them
			local norm = GBankClassic_Guild:NormalizeName(altName)
			local correctedHash = data.hash
			if correctedHash and correctedHash ~= 0 and GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts then
				local localAlt = GBankClassic_Guild.Info.alts[norm]
				if localAlt then
					local oldInvHash = localAlt.inventoryHash
					if oldInvHash ~= correctedHash then
						localAlt.inventoryHash = correctedHash
						GBankClassic_Output:Debug("SYNC", "Hash correction: %s inventoryHash %s→%d (from %s)", norm, tostring(oldInvHash), correctedHash, sender)
					end
				end
			end

			-- Mark sync as complete
			GBankClassic_Guild:ConsumePendingSync("alt", sender, altName)
			if GBankClassic_Guild.hasRequested then
				if GBankClassic_Guild.requestCount == nil then
					GBankClassic_Guild.requestCount = 0
				else
					GBankClassic_Guild.requestCount = GBankClassic_Guild.requestCount - 1
				end
				if GBankClassic_Guild.requestCount == 0 then
					GBankClassic_Guild.hasRequested = false
					GBankClassic_Output:Info("Sync completed.")
				end
			end
		end
	end

	--[[
	if prefix == "gbank-rm" then
		GBankClassic_Output:DebugComm("%s received from %s: type=%s", prefix, sender, tostring(data.type))
		
		-- -- Critical debug for request mutations
		-- if data.type == "requests-log" then
		-- 	GBankClassic_Output:Debug("SYNC", "%s requests-log received from %s, about to call ReceiveRequestMutations", prefix, sender)
		-- end

		if data.type == "roster" then
			-- Only accept roster updates from a sender that is marked as a bank in guild notes, or from the guild master
			-- TODO: also accept from players that can view guild notes
			local allowed = (GBankClassic_Guild and GBankClassic_Guild.SenderHasGbankNote and GBankClassic_Guild:SenderHasGbankNote(sender)) or GBankClassic_Guild:SenderIsGM(sender)
			if GBankClassic_Guild:ConsumePendingSync("roster", sender) then
				allowed = true
			end
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), SHARES_COLOR, "roster data. We", allowed and "accept it." or "do not accept it.")
		end

		if data.type == "requests" then
			local status = GBankClassic_Guild:ReceiveRequestsData(data)
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "requests snapshot. We accept it by default.", formatSyncStatus(status))
		end
		if data.type == "requests-index" then
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "requests index. We accept it by default.")
			GBankClassic_Guild:ReceiveRequestsIndex(data, sender)
		end
		if data.type == "requests-by-id" then
			local status = GBankClassic_Guild:ReceiveRequestsById(data)
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "requests by-id data. We accept it by default.", formatSyncStatus(status))
		end
		if data.type == "requests-log" then
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "request mutations. We accept by default.")
			GBankClassic_Guild:ReceiveRequestMutations(data, sender)
		end
		if data.type == "alt" then
			-- Only accept alt data if the sender matches the claimed alt name
			local claimed = data.name
			local claimedNorm = GBankClassic_Guild:NormalizeName(claimed) or claimed
			local allowed = self:IsAltDataAllowed(sender, claimedNorm)
			if GBankClassic_Guild:ConsumePendingSync("alt", sender, claimedNorm) then
				allowed = true
			end
			local status = allowed and GBankClassic_Guild:ReceiveAltData(claimedNorm, data.alt, sender) or ADOPTION_STATUS.UNAUTHORIZED
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), SHARES_COLOR, "bank data (link-less) about", self:ColorPlayerName(claimedNorm) .. ". We", allowed and "accept it." or "do not accept it.", formatSyncStatus(status))
			if allowed then
				-- ReceiveAltData already applied/rejected; refresh UI if open
				if status == ADOPTION_STATUS.ADOPTED and GBankClassic_UI_Inventory and GBankClassic_UI_Inventory.isOpen then
					GBankClassic_UI_Inventory:DrawContent()
					GBankClassic_UI_Inventory:RefreshCurrentTab()
				end
			else
				-- Ignore spoofed alt data
				return
			end
		end
	end
	]]--

	-- Full sync with links
	if prefix == "gbank-d" then
		if data.type == "alt" then
			-- Only accept alt data if the sender matches the claimed alt name
			local claimed = data.name
			local claimedNorm = GBankClassic_Guild:NormalizeName(claimed)

			GBankClassic_Output:DebugComm("Receive data: gbank-d from %s for alt %s (%d bytes)", sender, claimedNorm, #message)

			local allowed = self:IsAltDataAllowed(sender, claimedNorm)
			if GBankClassic_Guild:ConsumePendingSync("alt", sender, claimedNorm) then
				allowed = true
			end
			local status = allowed and GBankClassic_Guild:ReceiveAltData(claimedNorm, data.alt, sender) or ADOPTION_STATUS.UNAUTHORIZED
			GBankClassic_Output:Debug("SYNC", ">", self:ColorPlayerName(sender), SHARES_COLOR, "bank data (link-less) about", self:ColorPlayerName(claimedNorm) .. ". We", allowed and "accept it." or "do not accept it.", formatSyncStatus(status))
			if allowed then
				-- Show completion message based on status
				if status == ADOPTION_STATUS.ADOPTED then
					local itemCount = #data.alt.items
    				local pluralItems = (itemCount ~= 1 and "s" or "")
					GBankClassic_Output:Info("Received data for %s from %s (%d item%s).", self:ColorPlayerName(claimedNorm), self:ColorPlayerName(sender), itemCount, pluralItems)
				else
					GBankClassic_Output:Info("Ignoring data for %s from %s (reason: %s).", self:ColorPlayerName(claimedNorm), self:ColorPlayerName(sender), status)
				end

				-- ReceiveAltData already applied/rejected; refresh UI if open
				if status == ADOPTION_STATUS.ADOPTED then
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
			else
				-- Ignore spoofed alt data
				return
			end
		end
	end

	--[[
	-- Request-specific query handler (gbank-rq)
	-- This is the dedicated prefix for request queries, replacing gbank-r with type="requests*"
	if prefix == "gbank-rq" then
		GBankClassic_Output:DebugComm("gbank-rq type = %s from %s", tostring(data.type), sender)
		GBankClassic_Output:Debug( "REQUESTS", ">", self:ColorPlayerName(sender), QUERIES_COLOR, "request query:", data.type or "unknown")

		-- Request data is guild-wide, anyone can respond (player="*")
		if data.type == "requests" then
			local matches = (data.player == "*" or data.player == player)
			GBankClassic_Output:DebugComm("Handler check: type=requests, player=%s, myName=%s, matches=%s", tostring(data.player), tostring(player), tostring(matches))
			if matches then
				GBankClassic_Output:DebugComm("Responding to requests query")
				GBankClassic_Guild:SendRequestsSnapshot(sender)
			end
		end
		if data.type == "requests-index" then
			local matches = (data.player == "*" or data.player == player)
			if matches then
				-- If hashes match, querier already has exactly what we have - stay silent
				local myHash = GBankClassic_Guild:GetRequestsHash()
				local querierHash = tonumber(data.hash) or 0
				if querierHash == 0 or myHash ~= querierHash then
					GBankClassic_Output:DebugComm("Responding to requests-index query (hash mismatch: mine=%d theirs=%d)", myHash, querierHash)
					GBankClassic_Guild:SendRequestsIndex(sender)
				else
					GBankClassic_Output:DebugComm("Skipping (hash match %d, querier already in sync)", myHash)
				end
			end
		end
		if data.type == "requests-by-id" then
			local matches = (data.player == "*" or data.player == player)
			if matches then
				GBankClassic_Output:DebugComm("Responding to requests-by-id query")
				GBankClassic_Guild:SendRequestsById(sender, data.ids)
			end
		end
	end

	-- Request-specific data handler (gbank-rd)
	-- This is the dedicated prefix for request data
	if prefix == "gbank-rd" then
		GBankClassic_Output:DebugComm("gbank-rd received from %s: type=%s", sender, tostring(data.type))

		if data.type == "requests" then
			local status = GBankClassic_Guild:ReceiveRequestsData(data)
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "requests snapshot.", formatSyncStatus(status))
		end
		if data.type == "requests-index" then
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "requests index.")
			GBankClassic_Guild:ReceiveRequestsIndex(data, sender)
		end
		if data.type == "requests-by-id" then
			local status = GBankClassic_Guild:ReceiveRequestsById(data)
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "requests by-id data.", formatSyncStatus(status))
		end
		if data.type == "requests-log" then
			GBankClassic_Output:Debug("REQUESTS", ">", self:ColorPlayerName(sender), SHARES_COLOR, "request mutations.")
			GBankClassic_Guild:ReceiveRequestMutations(data, sender)
		end
	end
	]]--

	-- Hello
	if prefix == "gbank-h" then
		GBankClassic_Guild:Hello("reply")
	end
	if prefix == "gbank-hr" then
		GBankClassic_Output:Debug("QUERIES", "gbank-hr", data)
	end

	-- Share
	if prefix == "gbank-s" then
		GBankClassic_Guild:Share("reply")
	end
	if prefix == "gbank-sr" then
		GBankClassic_Output:Debug("QUERIES", "gbank-sr", data)
	end

	-- Wipe all
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
			GBankClassic_Output:Response("GBankClassic version:", version)
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
		name = "debugtab",
		help = "create a dedicated chat tab for debug output",
		expert = true,
		handler = function()
			if GBankClassic_Output:CreateDebugTab() then
				GBankClassic_Output:Response("Debug output will now appear in 'GBankClassicDebug' tab")
				GBankClassic_Output:Response("Use /bank debug to enable debug logging")
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
	-- {
	-- 	name = "persistcheck",
	-- 	help = "check current request persistence state",
	-- 	expert = true,
	-- 	handler = function()
	-- 		if not GBankClassic_Guild or not GBankClassic_Guild.Info then
	-- 			GBankClassic_Output:Response("Guild info not loaded")

	-- 			return
	-- 		end

	-- 		local logCount = #(GBankClassic_Guild.Info.requestLog or {})
	-- 		local appliedCount = 0
	-- 		local appliedActors = {}
	-- 		if GBankClassic_Guild.Info.requestLogApplied then
	-- 			for actor, seq in pairs(GBankClassic_Guild.Info.requestLogApplied) do
	-- 				appliedCount = appliedCount + 1
	-- 				table.insert(appliedActors, string.format("%s=%d", actor, seq))
	-- 			end
	-- 		end
	-- 		local requestCount = #(GBankClassic_Guild.Info.requests or {})
	-- 		local seqCount = GBankClassic_Guild.Info.requestLogSeq and GBankClassic_Globals:Count(GBankClassic_Guild.Info.requestLogSeq) or 0

	-- 		GBankClassic_Output:Response("=== Request persistence state ===")
	-- 		GBankClassic_Output:Response("requests: %d items", requestCount)
	-- 		GBankClassic_Output:Response("requestLog: %d entries", logCount)
	-- 		GBankClassic_Output:Response("requestLogApplied: %d actors", appliedCount)
	-- 		if appliedCount > 0 then
	-- 			GBankClassic_Output:Response("  %s", table.concat(appliedActors, ", "))
	-- 		end
	-- 		GBankClassic_Output:Response("requestLogSeq: %d actors", seqCount)

	-- 		-- Check if data is referencing SavedVariables
	-- 		local db = GBankClassic_Database and GBankClassic_Database.db
	-- 		if db and db.faction then
	-- 			local guildName = GBankClassic_Guild:GetGuildName()
	-- 			if guildName and db.faction[guildName] then
	-- 				local isSameRef = (GBankClassic_Guild.Info == db.faction[guildName])
	-- 				GBankClassic_Output:Response("Guild.Info %s SavedVariables reference", isSameRef and "is" or "is not")
	-- 			end
	-- 		end
	-- 	end,
	-- },
	-- {
	-- 	name = "requestlog",
	-- 	usage = "[N|all]",
	-- 	help = "print the request log, optionally limited to N entries",
	-- 	expert = true,
	-- 	handler = function(arg1)
	-- 		GBankClassic_Guild:PrintRequestLog(arg1)
	-- 	end,
	-- },
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
				GBankClassic_Output:Response("Debug: off (log level: " .. levelName .. ")")
			else
				-- Save current level before entering debug mode
				preDebugLogLevel = GBankClassic_Options:GetLogLevel()
				GBankClassic_Output:SetLevel(LOG_LEVEL.DEBUG)
				GBankClassic_Options.db.global.bank["logLevel"] = LOG_LEVEL.DEBUG
				GBankClassic_Output:Response("Debug: on (log level: Debug)")
			end
		end,
	}
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
			GBankClassic_Output:Response("Unknown command: ", prefix)
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

function Chat:ProcessQueue()
	if IsInRaid() then
		return
	end

    if #self.syncQueue == 0 then
        self.isSyncing = false

        return
    end

    self.isSyncing = true
	local startTime = debugprofilestop()
    local time = GetServerTime()

	local name = table.remove(self.syncQueue)
	if not self.lastGuildBankAltSync[name] or time - self.lastGuildBankAltSync[name] > 180 then
		self.lastGuildBankAltSync[name] = time
		GBankClassic_Guild:SendAltData(name)
	end
	local duration = debugprofilestop() - startTime
	GBankClassic_Output:Debug("EVENTS", "ProcessQueue took %.2fms (name=%s, queue=%d)", duration, tostring(name), #self.syncQueue)

	if #self.syncQueue > 0 then
		self:ReprocessQueue()
	end
end

function Chat:ReprocessQueue()
	if self.reprocessTimer then
		return
	end
	self.reprocessTimer = GBankClassic_Core:ScheduleTimer(function(...)
		self.reprocessTimer = nil
        self:OnTimer()
    end, TIMER_INTERVALS.ALT_DATA_QUEUE_RETRY)
end

function Chat:OnTimer()
    self:ProcessQueue()
end

function Chat:PrintVersions()
	-- Get our own version
	local myVersion = GetAddOnMetadata("GBankClassic", "Version") or "unknown"
	local myPlayer = GBankClassic_Guild:GetNormalizedPlayer()

	-- Collect versions into a sortable list
	local versions = {}

	-- Add ourselves
	table.insert(versions, { name = myPlayer, version = myVersion, seen = time(), isSelf = true })

	-- Add tracked guild members
	for name, info in pairs(self.guildMembersAddonVersion) do
		table.insert(versions, { name = name, version = tostring(info.version), seen = info.seen, isSelf = false })
	end

	-- Sort by version (descending), then by name
	table.sort(versions, function(a, b)
		if a.version ~= b.version then
			return a.version > b.version
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
		GBankClassic_Output:Response("  %s: %s%s%s", entry.name, entry.version, marker, age)
	end
end

function Chat:RestoreUI()
	if GBankClassic_Options and GBankClassic_Options.db and GBankClassic_Options.db.char then
		local count = GBankClassic_Globals:Count(GBankClassic_Options.db.char.framePositions)
		GBankClassic_Options.db.char.framePositions = {}
		GBankClassic_Output:Response("Cleared %d saved window position(s)", count)
		if GBankClassic_UI_Inventory.isOpen then
			GBankClassic_UI_Inventory:Close()
			GBankClassic_UI_Inventory:Toggle()
		else
			GBankClassic_UI_Inventory:Open()
		end
	else
		GBankClassic_Output:Response("No frame positions to clear")
	end
end