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
		guildProtocolVersions = {},
    }

	GBankClassic_Output:Response("Local database for %s has been emptied.", name)
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

    GBankClassic_Core:Response("Local database for %s (guild: %s) has been emptied.", player, name)
end

function Database:Load(name)
	if not name then
		return
	end

    local db = self.db.factionrealm[name]

	-- Only reset if there's truly no data (nil), otherwise initialize missing fields
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
		for altName, alt in pairs(db.alts) do
			if type(alt) == "table" then
				-- Clear and rebuild items from bank, bags, and mail if legacy data exists
				if (alt.bank and alt.bank.items and #alt.bank.items > 0) or (alt.bags and alt.bags.items and #alt.bags.items > 0) or (alt.mail and alt.mail.items and #alt.mail.items > 0) then
					alt.items = nil
					GBankClassic_Bank:RecalculateAggregatedItems(alt.bank and alt.bank.items or nil, alt.bags and alt.bags.items or nil, alt.mail and alt.mail.items or nil, alt)
					alt.bank = nil
					alt.bags = nil
					alt.mail = nil
				end

				-- Ensure items is always fully aggregated and then recompute the hash and reconstruct item links
				if alt.items then
					local money = alt.money or 0

					local aggregated = GBankClassic_Item:Aggregate(alt.items, nil)
					alt.items = {}
					for _, item in pairs(aggregated) do
						table.insert(alt.items, item)
					end
					GBankClassic_Output:Debug("DATABASE", "Forced deduplication for guild bank alt %s: %d items", altName, #alt.items)

					-- Wipe hashes and version timestamp if there are no items
					if #alt.items == 0 then
						alt.inventoryHash = nil
						alt.improvedInventoryHash = nil
						alt.version = nil
					end

					-- Only recalculate the new hash if it does not already exist and if there is at least 1 item
					local oldImprovedInventoryHash = alt.improvedInventoryHash
					if not oldImprovedInventoryHash and #alt.items > 0 then
						alt.improvedInventoryHash = GBankClassic_Bank:ComputeImprovedInventoryHash(alt.items, money)
						GBankClassic_Output:Debug("DATABASE", "Recomputed improved inventory hash after recalculation for %s: %d", altName, alt.improvedInventoryHash)
					end

					GBankClassic_Guild:ReconstructItemLinks(alt.items)
				end
			end
		end
	end

	if not db.guildProtocolVersions then
		db.guildProtocolVersions = {}
	end

	-- Empty unused legacy delta tables
	db.deltaSnapshots = nil
	db.deltaHistory = nil
	db.deltaMetrics = nil
	db.deltaErrors = nil

    return db
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
function Database:UpdatePeerProtocol(name, sender, protocolVersion)
	if not name or not sender then
		return false
	end

	local db = self.db.factionrealm[name]
	if not db or not db.guildProtocolVersions then
		return false
	end

	db.guildProtocolVersions[sender] = {
		version = protocolVersion or 1,
		lastSeen = GetServerTime(),
	}

	return true
end