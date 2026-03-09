GBankClassic_Database = GBankClassic_Database or {}

local Database = GBankClassic_Database

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("LibStub", "GetServerTime")
local LibStub = upvalues.LibStub
local GetServerTime = upvalues.GetServerTime

function Database:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicDB", {
		global = {
			debugCategories = {
				ROSTER = false,
				COMMS = false,
				DELTA = false,
				SYNC = false,
				CHUNK = false,
				DONATION = false,
				WHISPER = false,
				-- REQUESTS = false,
				UI = false,
				PROTOCOL = false,
				DATABASE = false,
				EVENTS = false,
				INVENTORY = false,
				MAIL = false,
				ITEM = false,
				-- FULFILL = false,
				SEARCH = false,
				QUERIES = false,
				REPLIES = false,
			},
		},
	})
end

function Database:Reset(name)
	if not name then
		return
	end

    self.db.factionrealm[name] = {
        name = name,
        roster = {},
        alts = {},
		-- requests = {},
		-- requestsVersion = 0,
		-- requestsTombstones = {},
		-- settings = {
		-- 	maxRequestPercent = 100, -- Default to no limit
		-- },
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

function Database:ResetPlayer(name, player)
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

    GBankClassic_Core:Response("Reset player database")
end

function Database:Load(name)
	if not name then
		return
	end

    local db = self.db.factionrealm[name]

	-- Only reset if there's truly no data (nil). Otherwise initialize missing fields.
	-- This prevents data loss when some fields are missing but others (like requests) exist.
	if db == nil then
        self:Reset(name)
        db = self.db.factionrealm[name]
    else
		-- Initialize missing fields without wiping existing data
		if db.name == nil then
			db.name = name
		end
		if db.roster == nil then
			db.roster = {}
		end
		if db.alts == nil then
			db.alts = {}
		end
    end

	-- Migrate old alt data to ensure slots fields exist
	-- Characters may have bank/bags without slots
	if db.alts then
		for name, alt in pairs(db.alts) do
			if type(alt) == "table" then
				if alt.bank and not alt.bank.slots then
					alt.bank.slots = { count = 0, total = 0 }
					GBankClassic_Output:Debug("DATABASE", "Migrated alt data: initialized bank.slots for %s", name)
				end
				if alt.bags and not alt.bags.slots then
					alt.bags.slots = { count = 0, total = 0 }
					GBankClassic_Output:Debug("DATABASE", "Migrated alt data: initialized bags.slots for %s", name)
				end
				-- Compute inventory hash for alts that don't have one
				-- This enables pull-based protocol for existing alt data
				if not alt.inventoryHash and alt.bank and alt.bags then
					local money = alt.money or 0
					alt.inventoryHash = GBankClassic_DeltaComms:ComputeInventoryHash(alt.bank, alt.bags, money)
				GBankClassic_Output:Debug("DATABASE", "Migrated alt data: computed inventory hash for %s (hash=%d)", name, alt.inventoryHash)
				end
				-- Recalculate aggregated items from bank/bags/mail with corrected aggregate function
				-- This fixes item count duplication without requiring a full scan
				-- Clear and rebuild alt.items on every load to prevent accumulation
				if (alt.bank and alt.bank.items) or (alt.bags and alt.bags.items) or (alt.mail and alt.mail.items) then
					-- Guild bank alt with bank/bags - force reconstruct from sources
					-- Log sample counts before clearing
					if alt.items and #alt.items > 0 then
						local beforeSample = {}
						for i = 1, math.min(5, #alt.items) do
							local item = alt.items[i]
							if item then
								table.insert(beforeSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
							end
						end
						GBankClassic_Output:Debug("DATABASE", "Recalculation of aggregated alt.items (from bank, bags, and mail) starting for guild bank alt %s.", name)
						GBankClassic_Output:Debug("DATABASE", "Sampling (before recalculation) for guild bank alt %s of alt.items: %s.", name, table.concat(beforeSample, ", "))
					end

					-- Don't create stub entries with hash but no content
					if (alt.bank and alt.bank.items and #alt.bank.items > 0) or (alt.bags and alt.bags.items and #alt.bags.items > 0) or (alt.mail and alt.mail.items and #alt.mail.items > 0) then
						-- Only recalc if source data exists
						alt.items = nil
						GBankClassic_Bank:RecalculateAggregatedItems(alt)

						-- Verify recalculation produced valid data
						if alt.items and #alt.items > 0 then
							-- Recompute hash after recalculation
							local money = alt.money or 0
							alt.inventoryHash = GBankClassic_Bank:ComputeInventoryHash(alt.items, money)
							GBankClassic_Output:Debug("DATABASE", "Recomputed inventory hash after recalculation for %s: %d.", name, alt.inventoryHash)
						end
					else
						-- No source data, clear hash and version too
						alt.inventoryHash = nil
						alt.version = nil
					end

					-- Log sample counts after recalculation
					if alt.items and #alt.items > 0 then
						local afterSample = {}
						for i = 1, math.min(5, #alt.items) do
							local item = alt.items[i]
							if item then
								table.insert(afterSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
							end
						end
						GBankClassic_Output:Debug("DATABASE", "Sampling (after recalculation) for guild bank alt %s of alt.items: %s.", name, table.concat(afterSample, ", "))
					end

					-- Recompute inventory hash
					if alt.items then
						local money = alt.money or 0
						local syncHash = GBankClassic_Bank:ComputeInventoryHash(alt.items, money)
						if syncHash ~= alt.inventoryHash then
							alt.inventoryHash = syncHash
							GBankClassic_Output:Debug("DATABASE", "Migrated alt data: corrected inventory hash for %s (hash=%d)", name, syncHash)
						end
					end

					GBankClassic_Output:Debug("DATABASE", "Completed recalculation of aggregated alt.items for guild bank alt %s.", name)
				elseif alt.items then
					-- Synced alt - force deduplicate
					-- Do not merge mail here - alt.items from sync already includes mail from sender's scan
					local aggregated = GBankClassic_Item:Aggregate(alt.items, nil)
					alt.items = {}
					for _, item in pairs(aggregated) do
						table.insert(alt.items, item)
					end
					GBankClassic_Output:Debug("DATABASE", "Forced deduplication for synced guild bank alt %s: %d items", name, #alt.items)
				end
			end
		end
	end

	-- if not db.requests then
	-- 	db.requests = {}
	-- end
	-- if not db.requestsVersion then
	-- 	db.requestsVersion = 0
	-- end
	-- if not db.requestsTombstones then
	-- 	db.requestsTombstones = {}
	-- end

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

-- Save a snapshot of alt data for future delta computation
function Database:SaveSnapshot(name, altName, altData)
	if not name or not altName or not altData then
		return false
	end

	local db = self.db.factionrealm[name]
	if not db or not db.deltaSnapshots then
		return false
	end

	-- Create a deep copy with timestamp
	db.deltaSnapshots[altName] = {
		data = self:DeepCopy(altData),
		timestamp = GetServerTime(),
	}

	return true
end

-- Deep copy function for snapshot creation
function Database:DeepCopy(obj)
	if type(obj) ~= "table" then
		return obj
	end

	local copy = {}
	for k, v in pairs(obj) do
		copy[k] = self:DeepCopy(v)
	end

	return copy
end

-- Update protocol version for a guild member
function Database:UpdatePeerProtocol(name, sender, protocolVersion, supportsDelta)
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

-- Record bytes sent via delta protocol
function Database:RecordDeltaSent(name, bytes)
	if not name or not bytes then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.bytesSentDelta = (db.deltaMetrics.bytesSentDelta or 0) + bytes
	end
end

-- Record successful delta application
function Database:RecordDeltaApplied(name)
	if not name then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.deltasApplied = (db.deltaMetrics.deltasApplied or 0) + 1
	end
end

-- Record failed delta application
function Database:RecordDeltaFailed(name)
	if not name then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.deltasFailed = (db.deltaMetrics.deltasFailed or 0) + 1
	end
end

-- Record delta computation time
function Database:RecordDeltaComputeTime(name, milliseconds)
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
function Database:RecordDeltaApplyTime(name, milliseconds)
	if not name or not milliseconds then
		return
	end

	local db = self.db.factionrealm[name]
	if db and db.deltaMetrics then
		db.deltaMetrics.totalApplyTime = (db.deltaMetrics.totalApplyTime or 0) + milliseconds
		db.deltaMetrics.applyCount = (db.deltaMetrics.applyCount or 0) + 1
	end
end