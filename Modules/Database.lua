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

	-- Data migration
	if db.alts then
		for name, alt in pairs(db.alts) do
			if type(alt) == "table" then
				-- Clear and rebuild items from bank, bags, and mail if legacy data exists
				if (alt.bank and alt.bank.items and #alt.bank.items > 0) or (alt.bags and alt.bags.items and #alt.bags.items > 0) or (alt.mail and alt.mail.items and #alt.mail.items > 0) then
					alt.items = nil
					GBankClassic_Bank:RecalculateAggregatedItems(alt.bank, alt.bags, alt.mail, alt)
					alt.bank = nil
					alt.bags = nil
					alt.mail = nil
				else
					alt.inventoryHash = nil
					alt.version = nil
				end

				-- Ensure items is always fully aggregated and then recompute the hash
				if alt.items then
					local aggregated = GBankClassic_Item:Aggregate(alt.items, nil)
					alt.items = {}
					for _, item in pairs(aggregated) do
						table.insert(alt.items, item)
					end
					GBankClassic_Output:Debug("DATABASE", "Forced deduplication for guild bank alt %s: %d items.", name, #alt.items)

					local money = alt.money or 0
					alt.inventoryHash = GBankClassic_DeltaComms:ComputeInventoryHash(alt.items, nil, nil, money)
					alt.improvedInventoryHash = GBankClassic_Bank:ComputeImprovedInventoryHash(alt.items, money)
					GBankClassic_Output:Debug("DATABASE", "Recomputed inventory hash after recalculation for %s: %d.", name, alt.inventoryHash)
					GBankClassic_Output:Debug("DATABASE", "Recomputed improved inventory hash after recalculation for %s: %d.", name, alt.improvedInventoryHash)

					GBankClassic_Guild:ReconstructItemLinks(alt.items)
					GBankClassic_UI_Search:BuildSearchData()
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