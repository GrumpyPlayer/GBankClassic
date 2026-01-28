GBankClassic_Database = {}

function GBankClassic_Database:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicDB", {
		global = {
			debugCategories = {
				ROSTER = false,
				COMMS = false,
				DELTA = false,
				SYNC = false,
				CACHE = false,
				WHISPER = false,
				UI = false,
				PROTOCOL = false,
				DATABASE = false,
				EVENTS = false,
			},
			showUncategorizedDebug = true, -- Show uncategorized debug messages by default
		},
	})
end

function GBankClassic_Database:Reset(name)
	if not name then
		return
	end

    self.db.factionrealm[name] = {
        name = name,
        roster = {},
        alts = {},
		deltaSnapshots = {},
		deltaHistory = {},
		guildProtocolVersions = {},
		deltaMetrics = {
			bytesSentDelta = 0,
			bytesSentFull = 0,
			deltasApplied = 0,
			deltasFailed = 0,
			fullSyncFallbacks = 0,
		},
		deltaErrors = {
			lastErrors = {}, -- Recent errors for debugging (max 10)
			failureCounts = {}, -- Track failures per alt
			notifiedAlts = {}, -- Track which alts we've notified about
		},
    }

	GBankClassic_Output:Response("Reset database")
end

function GBankClassic_Database:ResetPlayer(name, player)
	if not name then
		return
	end
	if not player then
		return
	end
    if not self.db.factionrealm[name].alts[player] then
        return
    end

    self.db.factionrealm[name].alts[player] = {}

    GBankClassic_Core:Print("Reset player database")
end

function GBankClassic_Database:Load(name)
	if not name then
		return
	end

    local db = self.db.factionrealm[name]

    if db == nil or db.roster == nil then
        GBankClassic_Database:Reset(name)
        db = self.db.factionrealm[name]
    elseif db.name == nil then
        db.name = name
    end

	if not db.deltaSnapshots then
		db.deltaSnapshots = {}
	end
	if not db.deltaHistory then
		db.deltaHistory = {}
	end
	if not db.guildProtocolVersions then
		db.guildProtocolVersions = {}
	end
	if not db.deltaMetrics then
		db.deltaMetrics = {
			bytesSentDelta = 0,
			bytesSentFull = 0,
			deltasApplied = 0,
			deltasFailed = 0,
			fullSyncFallbacks = 0,
		}
	end
	if not db.deltaErrors then
		db.deltaErrors = {
			lastErrors = {},
			failureCounts = {},
			notifiedAlts = {},
		}
	end

    return db
end

-- Snapshot management functions

-- Save a snapshot of alt data for future delta computation
function GBankClassic_Database:SaveSnapshot(name, altName, altData)
	if not name or not altName or not altData then
		return false
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaSnapshots then
		return false
	end

	-- Create a deep copy with timestamp
	db.deltaSnapshots[altName] = {
		data = GBankClassic_Database:DeepCopy(altData),
		timestamp = GetServerTime(),
	}

	return true
end

-- Retrieve a snapshot of alt data for delta computation
function GBankClassic_Database:GetSnapshot(name, altName)
	if not name or not altName then
		return nil
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaSnapshots then
		return nil
	end

	local snapshot = db.deltaSnapshots[altName]
	if not snapshot then
		return nil
	end

	-- Check if snapshot is still valid (not too old)
	local age = GetServerTime() - (snapshot.timestamp or 0)
	if age > PROTOCOL.DELTA_SNAPSHOT_MAX_AGE then
		-- Snapshot expired, remove it
		db.deltaSnapshots[altName] = nil
		return nil
	end

	-- Validate snapshot structure
	if not self:ValidateSnapshot(snapshot.data) then
		-- Corrupted snapshot, remove it
		db.deltaSnapshots[altName] = nil
		return nil
	end

	return snapshot.data
end

-- Validate snapshot structure
function GBankClassic_Database:ValidateSnapshot(snapshot)
	if not snapshot or type(snapshot) ~= "table" then
		return false
	end

	-- Check required fields
	if not snapshot.version or type(snapshot.version) ~= "number" then
		return false
	end

	-- Validate bank structure if present
	if snapshot.bank then
		if type(snapshot.bank) ~= "table" then
			return false
		end
		if snapshot.bank.items and type(snapshot.bank.items) ~= "table" then
			return false
		end
	end

	-- Validate bags structure if present
	if snapshot.bags then
		if type(snapshot.bags) ~= "table" then
			return false
		end
		if snapshot.bags.items and type(snapshot.bags.items) ~= "table" then
			return false
		end
	end

	return true
end

-- Get the age of a snapshot in seconds
function GBankClassic_Database:GetSnapshotAge(name, altName)
	if not name or not altName then
		return nil
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaSnapshots then
		return nil
	end

	local snapshot = db.deltaSnapshots[altName]
	if not snapshot or not snapshot.timestamp then
		return nil
	end

	return GetServerTime() - snapshot.timestamp
end

-- Clean up old snapshots (older than DELTA_SNAPSHOT_MAX_AGE)
function GBankClassic_Database:CleanupOldSnapshots(name)
	if not name then
		return 0
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaSnapshots then
		return 0
	end

	local currentTime = GetServerTime()
	local removed = 0
	for altName, snapshot in pairs(db.deltaSnapshots) do
		if snapshot and snapshot.timestamp then
			local age = currentTime - snapshot.timestamp
			if age > PROTOCOL.DELTA_SNAPSHOT_MAX_AGE then
				db.deltaSnapshots[altName] = nil
				removed = removed + 1
			end
		else
			-- Malformed snapshot, remove it
			db.deltaSnapshots[altName] = nil
			removed = removed + 1
		end
	end

	return removed
end

-- Deep copy function for snapshot creation
function GBankClassic_Database:DeepCopy(obj)
	if type(obj) ~= "table" then
		return obj
	end

	local copy = {}
	for k, v in pairs(obj) do
		copy[k] = self:DeepCopy(v)
	end

	return copy
end

-- Delta history management

-- Save a delta to history for potential chain replay
function GBankClassic_Database:SaveDeltaHistory(name, altName, baseVersion, version, delta)
	if not name or not altName or not baseVersion or not version or not delta then
		return false
	end

	local db = self.db.factionrealm[name]
	if not db then
		return false
	end

	-- Initialize deltaHistory if needed
	if not db.deltaHistory then
		db.deltaHistory = {}
	end
	if not db.deltaHistory[altName] then
		db.deltaHistory[altName] = {}
	end

	-- Add delta to history
	table.insert(db.deltaHistory[altName], {
		baseVersion = baseVersion,
		version = version,
		delta = self:DeepCopy(delta), -- Deep copy to prevent mutation
		timestamp = GetServerTime()
	})

	-- Enforce max count limit (keep most recent)
	local maxCount = PROTOCOL.DELTA_HISTORY_MAX_COUNT or 10
	while #db.deltaHistory[altName] > maxCount do
		table.remove(db.deltaHistory[altName], 1) -- Remove oldest
	end

	return true
end

-- Get delta history for an alt within a version range
function GBankClassic_Database:GetDeltaHistory(name, altName, fromVersion, toVersion)
	if not name or not altName then
		return nil
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaHistory or not db.deltaHistory[altName] then
		return nil
	end

	-- Build chain of deltas from fromVersion to toVersion
	local chain = {}
	local currentVersion = fromVersion

	for _, deltaEntry in ipairs(db.deltaHistory[altName]) do
		if deltaEntry.baseVersion == currentVersion and deltaEntry.version <= toVersion then
			table.insert(chain, {
				baseVersion = deltaEntry.baseVersion,
				version = deltaEntry.version,
				delta = deltaEntry.delta
			})
			currentVersion = deltaEntry.version

			-- Stop if we've reached the target
			if currentVersion == toVersion then
				break
			end
		end
	end

	-- Return nil if we couldn't build a complete chain
	if currentVersion ~= toVersion then
		return nil
	end

	return chain
end

-- Clean up old delta history (older than DELTA_HISTORY_MAX_AGE)
function GBankClassic_Database:CleanupDeltaHistory(name)
	if not name then
		return 0
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaHistory then
		return 0
	end

	local currentTime = GetServerTime()
	local maxAge = PROTOCOL.DELTA_HISTORY_MAX_AGE or 3600
	local totalRemoved = 0
	for altName, history in pairs(db.deltaHistory) do
		if type(history) == "table" then
			-- Remove old entries
			local i = 1
			while i <= #history do
				if history[i] and history[i].timestamp then
					local age = currentTime - history[i].timestamp
					if age > maxAge then
						table.remove(history, i)
						totalRemoved = totalRemoved + 1
					else
						i = i + 1
					end
				else
					-- Malformed entry
					table.remove(history, i)
					totalRemoved = totalRemoved + 1
				end
			end

			-- Remove empty histories
			if #history == 0 then
				db.deltaHistory[altName] = nil
			end
		end
	end

	return totalRemoved
end

-- Protocol version tracking

-- Update protocol version for a guild member
function GBankClassic_Database:UpdatePeerProtocol(name, sender, protocolVersion, supportsDelta)
	if not name or not sender then
		return false
	end

	local db = self.db.factionrealm[name]
	if not db or not db.guildProtocolVersions then
		return false
	end

	db.guildProtocolVersions[sender] = {
		version = protocolVersion or 1,
		supportsDelta = supportsDelta or false,
		lastSeen = GetServerTime(),
	}

	return true
end

-- Get protocol version for a guild member
function GBankClassic_Database:GetPeerProtocol(name, sender)
	if not name or not sender then
		return nil
	end

	local db = self.db.factionrealm[name]
	if not db or not db.guildProtocolVersions then
		return nil
	end

	return db.guildProtocolVersions[sender]
end

-- Calculate percentage of online guild members supporting delta
function GBankClassic_Database:GetGuildDeltaSupport(name)
	if not name then
		return 0
	end

	local db = self.db.factionrealm[name]
	if not db or not db.guildProtocolVersions then
		return 0
	end

	local total = 0
	local supporting = 0
	local currentTime = GetServerTime()

	-- Only count members seen in last 10 minutes (considered online)
	for _, info in pairs(db.guildProtocolVersions) do
		if info and info.lastSeen and (currentTime - info.lastSeen) < 600 then
			total = total + 1
			if info.supportsDelta then
				supporting = supporting + 1
			end
		end
	end

	if total == 0 then
		return 0
	end

	return supporting / total
end

-- Delta metrics

-- Record bytes sent via delta protocol
function GBankClassic_Database:RecordDeltaSent(name, bytes)
	if not name or not bytes then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.bytesSentDelta = (db.deltaMetrics.bytesSentDelta or 0) + bytes
	end
end

-- Record bytes sent via full sync protocol
function GBankClassic_Database:RecordFullSyncSent(name, bytes)
	if not name or not bytes then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.bytesSentFull = (db.deltaMetrics.bytesSentFull or 0) + bytes
	end
end

-- Record successful delta application
function GBankClassic_Database:RecordDeltaApplied(name)
	if not name then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.deltasApplied = (db.deltaMetrics.deltasApplied or 0) + 1
	end
end

-- Record failed delta application
function GBankClassic_Database:RecordDeltaFailed(name)
	if not name then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.deltasFailed = (db.deltaMetrics.deltasFailed or 0) + 1
	end
end

-- Record delta computation time
function GBankClassic_Database:RecordDeltaComputeTime(name, milliseconds)
	if not name or not milliseconds then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.totalComputeTime = (db.deltaMetrics.totalComputeTime or 0) + milliseconds
		db.deltaMetrics.computeCount = (db.deltaMetrics.computeCount or 0) + 1
	end
end

-- Record delta application time
function GBankClassic_Database:RecordDeltaApplyTime(name, milliseconds)
	if not name or not milliseconds then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.totalApplyTime = (db.deltaMetrics.totalApplyTime or 0) + milliseconds
		db.deltaMetrics.applyCount = (db.deltaMetrics.applyCount or 0) + 1
	end
end

-- Reset delta metrics (for testing or cleanup)
function GBankClassic_Database:ResetDeltaMetrics(name)
	if not name then
		return false
	end

	local db = self.db.factionrealm[name]
	if not db then
		return false
	end

	db.deltaMetrics = {
		bytesSentDelta = 0,
		bytesSentFull = 0,
		deltasApplied = 0,
		deltasFailed = 0,
		fullSyncFallbacks = 0,
		totalComputeTime = 0,
		computeCount = 0,
		totalApplyTime = 0,
		applyCount = 0,
	}

	return true
end

-- Record fallback to full sync
function GBankClassic_Database:RecordFullSyncFallback(name)
	if not name then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.fullSyncFallbacks = (db.deltaMetrics.fullSyncFallbacks or 0) + 1
	end
end

-- Get delta metrics
function GBankClassic_Database:GetDeltaMetrics(name)
	if not name then
		return nil
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaMetrics then
		return nil
	end

	return db.deltaMetrics
end
