local addonName, GBCR = ...

GBCR.Database = {}
local Database = GBCR.Database

local Globals = GBCR.Globals
local debugprofilestop = Globals.debugprofilestop
local pairs = Globals.pairs
local select = Globals.select
local string_gsub = Globals.string_gsub
local type = Globals.type

local After = Globals.After
local GetClassColor = Globals.GetClassColor
local GetGuildInfo = Globals.GetGuildInfo
local GetRealmName = Globals.GetRealmName
local shouldYield = Globals.ShouldYield

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD

local Output = GBCR.Output

-- Retrieve the list of guild bank alts on the roster (includes manually defined guild bank alts)
local function getRosterGuildBankAlts(self)
    if not self.savedVariables then
        return nil
    end

    local roster = self.savedVariables.roster
    if roster and roster.alts and #roster.alts > 0 then
        return roster.alts
    end

    return nil
end

-- Helper to generates a unique, connected-realm safe database key (format: "GuildName-HomeRealm")
local function getUniqueKey(guildName)
    if not guildName then
        return nil
    end

    local currentGuild, _, _, guildRealm = GetGuildInfo("player")
    local realm

    if currentGuild == guildName and guildRealm and guildRealm ~= "" then
        realm = guildRealm
    else
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

    GBCR.Output:Response("Your local database for guild bank %s (guild: %s) has been reset.",
                         GBCR.Globals.ColorizeText(select(4, GetClassColor(GBCR.Guild:GetGuildMemberInfo(altName))), altName),
                         GBCR.Globals.ColorizeText(colorGold, guildName))
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
        roster = {alts = {}, version = nil, areOfficerNotesUsed = nil, manualAlts = {}},
        alts = {}
    }
    self.savedVariables = nil

    GBCR.Output:Response("Your local guild bank database (guild: %s) has been reset.",
                         GBCR.Globals.ColorizeText(colorGold, guildName))
end

-- Compress data for compact savedVariables storage
local function compressData(data)
    local serialized = GBCR.Libs.LibSerialize:Serialize(data)
    local compressed = GBCR.Libs.LibDeflate:CompressDeflate(serialized, {level = Constants.LIMITS.COMPRESSION_LEVEL})

    return GBCR.Libs.LibDeflate:EncodeForPrint(compressed)
end

-- Compress data from savedVariables in memory
local function decompressData(encoded)
    local compressed = GBCR.Libs.LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        GBCR.Output:Error("decompressData: DecodeForPrint failed (corrupted saved data?)")

        return nil
    end

    local serialized = GBCR.Libs.LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        GBCR.Output:Error("decompressData: DecompressDeflate failed (corrupted saved data?)")

        return nil
    end

    local ok, items = GBCR.Libs.LibSerialize:Deserialize(serialized)
    if not ok then
        GBCR.Output:Error("decompressData: Deserialize failed: %s", tostring(items))

        return nil
    end

    return items
end

-- Helper to determine if data decompression is needed
local function decompressIfNeeded(alt, compressedField, field, decompressFn)
    if alt[compressedField] and not alt[field] then
        local result = decompressFn(alt[compressedField])
        if result ~= nil then
            alt[field] = result
        else
            GBCR.Output:Error("decompressIfNeeded: permanently skipping corrupted %s field", compressedField)
            alt[compressedField] = nil
        end
    end
end

-- Load all guild bank alt data for the current guild from saved variables
local function loadGuild(self, guildName)
    GBCR.Output:Debug("DATABASE", "Loading guild bank database from saved variables for %s", tostring(guildName))

    if not guildName then
        return nil
    end

    local uniqueKey, realmName = getUniqueKey(guildName)

    self.db.global.guilds = self.db.global.guilds or {}
    local db = self.db.global.guilds[uniqueKey]

    if db == nil then
        resetGuildDatabase(self, guildName)
        db = self.db.global.guilds[uniqueKey]
    else
        db.guildName = db.guildName or guildName
        db.realm = db.realm or realmName
        db.roster = db.roster or {}
        db.alts = db.alts or {}
        if db.networkMeta then
            local lastVer = db.networkMeta.lastSharedVersion or 0
            db.networkMeta = {lastSharedVersion = lastVer}
        else
            db.networkMeta = {}
        end
    end

    if db and db.alts then
        local protocol = GBCR.Protocol

        local altNames = {}
        local altCount = 0
        for altName, alt in pairs(db.alts) do
            if type(alt) == "table" and
                (alt.items or alt.itemsCompressed or alt.ledger or alt.ledgerCompressed or alt.cache or alt.cacheCompressed) then
                altCount = altCount + 1
                altNames[altCount] = altName
            end
        end

        GBCR.Database.loadGeneration = (GBCR.Database.loadGeneration or 0) + 1
        local myGen = GBCR.Database.loadGeneration
        local altIndex = 1

        local function processAltsLoop()
            if myGen ~= GBCR.Database.loadGeneration then
                Output:Debug("DATABASE", "Async maintenance aborted (stale generation %d)", myGen)

                return
            end

            local startTime = debugprofilestop()
            local iterations = 0

            while altIndex <= altCount do
                iterations = iterations + 1
                local altName = altNames[altIndex]
                local alt = db.alts[altName]

                if not alt then
                    altIndex = altIndex + 1
                else
                    decompressIfNeeded(alt, "cacheCompressed", "cache", decompressData)
                    decompressIfNeeded(alt, "itemsCompressed", "items", decompressData)
                    decompressIfNeeded(alt, "ledgerCompressed", "ledger", decompressData)

                    protocol:ReconstructItemLinks(alt.items)
                    altIndex = altIndex + 1
                end

                if shouldYield(startTime, iterations, 1, 10) then
                    After(0, processAltsLoop)

                    return
                end
            end

            local missedAlts = {}
            for altName, alt in pairs(db.alts) do
                if type(alt) == "table" and alt.itemsCompressed and not alt.items then
                    missedAlts[#missedAlts + 1] = altName
                end
            end

            if #missedAlts > 0 then
                Output:Debug("DATABASE", "processAltsLoop: %d guild bank alts arrived mid-run, scheduling secondary pass",
                             #missedAlts)

                local missedAlt = 1

                local function secondaryPass()
                    local startTimeSecondaryPass = debugprofilestop()
                    local iterationsSecondaryPass = 0

                    while missedAlt <= #missedAlts do
                        iterationsSecondaryPass = iterationsSecondaryPass + 1
                        local altName = missedAlts[missedAlt]
                        local alt = db.alts[altName]
                        missedAlt = missedAlt + 1

                        if alt then
                            decompressIfNeeded(alt, "itemsCompressed", "items", decompressData)
                            protocol:ReconstructItemLinks(alt.items)
                        end

                        if shouldYield(startTimeSecondaryPass, iterationsSecondaryPass, 1, 5) then
                            After(0, secondaryPass)

                            return
                        end
                    end

                    GBCR.UI.Inventory:MarkAllDirty()
                    GBCR.UI:QueueUIRefresh()
                end

                After(0, secondaryPass)
            end

            if myGen ~= GBCR.Database.loadGeneration then
                return
            end

            GBCR.UI.Inventory:MarkAllDirty()
            GBCR.UI:QueueUIRefresh()
            Output:Debug("DATABASE", "Async maintenance complete for %d alts (gen %d)", altCount, myGen)
        end

        if altCount > 0 then
            After(0, processAltsLoop)
        end
    end

    return db
end

-- Persist savedVariables for easy use by the addon
local function init(self)
    self.savedVariables = nil
    self.db = GBCR.db
end

-- Export functions for other modules
Database.GetRosterGuildBankAlts = getRosterGuildBankAlts
Database.ResetGuildBankAlt = resetGuildBankAlt
Database.ResetGuildDatabase = resetGuildDatabase
Database.CompressData = compressData
Database.DecompressData = decompressData
Database.Load = loadGuild
Database.Init = init
