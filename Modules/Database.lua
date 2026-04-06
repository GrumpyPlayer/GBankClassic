local addonName, GBCR = ...

GBCR.Database = {}
local Database = GBCR.Database

local Globals = GBCR.Globals
local pairs = Globals.pairs
local select = Globals.select
local type = Globals.type
local string_gsub = Globals.string_gsub

local GetClassColor = Globals.GetClassColor
local GetGuildInfo = Globals.GetGuildInfo
local GetRealmName = Globals.GetRealmName

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD

local Output = GBCR.Output

-- Helper to generates a unique, connected-realm safe database key
-- Format: "GuildName-HomeRealm"
local function getUniqueKey(guildName)
    if not guildName then
		return nil
	end

    local currentGuild, _, _, guildRealm = GetGuildInfo("player")
    local realm

    if currentGuild == guildName and guildRealm and guildRealm ~= "" then
        realm = guildRealm
    else
        -- Fallback to local realm if the API returns nil (standard for non-connected realms)
        realm = GetRealmName()
    end

    realm = string_gsub(realm or "", "%s+", "")

    return guildName .. "-" .. realm, realm
end

-- Wipe local guild bank alt data for a specific guild bank alt
local function resetGuildBankAlt(self, guildName, altName)
	local uniqueKey = getUniqueKey(guildName)
    if not uniqueKey or not altName then
        return
    end

    local db = self.db.global.guilds[uniqueKey]
    if not db or not db.alts[altName] then
        return
    end

    db.alts[altName] = {}

    GBCR.Core:Response("Your local database for %s (guild: %s) has been emptied.", GBCR.Globals:Colorize(select(4, GetClassColor(GBCR.Guild:GetGuildMemberInfo(altName))), altName), GBCR.Globals:Colorize(colorGold, guildName))
end

-- Wipe all local guild bank alt data in saved variables for the specified guild
local function resetGuildDatabase(self, guildName)
	local uniqueKey, realmName = getUniqueKey(guildName)
    if not uniqueKey then
        return
    end

    self.db.global.guilds[uniqueKey] = {
        guildName = guildName,
        realm = realmName,
        roster = {},
        alts = {}
    }
    self.savedVariables = nil

	GBCR.Output:Response("Your local database for guild %s has been emptied.", GBCR.Globals:Colorize(colorGold, guildName))
end

-- Load all guild bank alt data for the current guild from saved variables
local function loadGuild(self, guildName)
	if not guildName then
		return nil
	end

	local uniqueKey, realmName = getUniqueKey(guildName)

    self.db.global.guilds = self.db.global.guilds or {}
    local db = self.db.global.guilds[uniqueKey]

	-- Initialization
	if db == nil then
        resetGuildDatabase(self, guildName)
        db = self.db.factionrealm[guildName]
    else
        -- Initialize missing fields without wiping existing data
        db.guildName = db.guildName or guildName
		db.realm = db.realm or realmName
        db.roster = db.roster or {}
        db.alts = db.alts or {}
    end

	-- Data maintenance
	if db.alts then
		local inventory = GBCR.Inventory
		local protocol = GBCR.Protocol

		local maintenanceState = { linkKeyCache = {} }

		for altName, alt in pairs(db.alts) do
			if type(alt) == "table" and alt.items then
                maintenanceState.items = {}
                maintenanceState.byKey = {}

                inventory:AggregateInto(maintenanceState, alt.items)

                alt.items = maintenanceState.items

				Output:Debug("DATABASE", "Forced deduplication for guild bank alt %s: %d items", altName, #alt.items)

				if not alt.itemsHash and #alt.items > 0 then
					alt.itemsHash = inventory:ComputeItemsHash(alt.items, alt.money or 0)
					Output:Debug("DATABASE", "Recomputed items hash after recalculation for %s: %d", altName, alt.itemsHash)
				end

				protocol:ReconstructItemLinks(alt.items)
			end
		end
	end

	self.savedVariables = db

    return db
end

-- Persist savedVariables for easy use by the addon
local function init(self)
	self.savedVariables = nil

    self.db = GBCR.db
end

-- Export functions for other modules
Database.ResetGuildBankAlt = resetGuildBankAlt
Database.ResetGuildDatabase = resetGuildDatabase
Database.Load = loadGuild
Database.Init = init