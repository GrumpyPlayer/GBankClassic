local addonName, GBCR = ...

GBCR.Database = {}
local Database = GBCR.Database

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD

function Database:Init()
	self.savedVariables = nil

    self.db = GBCR.Libs.AceDB:New("GBankClassicDB", {})
end

function Database:Reset(name)
	if not name then
		return
	end

    self.db.factionrealm[name] = {
        name = name,
        roster = {},
        alts = {}
    }
	self.savedVariables = nil

	GBCR.Output:Response("Your local database for guild %s has been emptied.", GBCR.Globals:Colorize(colorGold, name))
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

    GBCR.Core:Response("Local database for %s (guild: %s) has been emptied.", player, name)
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

	-- Data maintenance
	if db.alts then
		for altName, alt in pairs(db.alts) do
			if type(alt) == "table" then
				if alt.items then
					local aggregated = GBCR.Inventory:Aggregate(alt.items, nil)
					alt.items = {}
					for _, item in pairs(aggregated) do
						table.insert(alt.items, item)
					end
					GBCR.Output:Debug("DATABASE", "Forced deduplication for guild bank alt %s: %d items", altName, #alt.items)

					-- Only recalculate the new hash if it does not already exist and if there is at least 1 item
					local previousItemsHash = alt.itemsHash
					if not previousItemsHash and #alt.items > 0 then
						alt.itemsHash = GBCR.Inventory:ComputeItemsHash(alt.items, alt.money or 0)
						GBCR.Output:Debug("DATABASE", "Recomputed items hash after recalculation for %s: %d", altName, alt.itemsHash)
					end

					GBCR.Protocol:ReconstructItemLinks(alt.items)
				end
			end
		end
	end

	-- Empty unused legacy delta tables
	db.deltaSnapshots = nil
	db.deltaHistory = nil
	db.deltaMetrics = nil
	db.deltaErrors = nil
	db.guildProtocolVersions = nil

    return db
end