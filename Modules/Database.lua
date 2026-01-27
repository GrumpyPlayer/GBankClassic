GBankClassic_Database = {}

function GBankClassic_Database:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicDB")
end

function GBankClassic_Database:Reset(name)
    if not name then return end

    self.db.factionrealm[name] = {
        name = name,
        roster = {},
        alts = {},
    }
end

function GBankClassic_Database:ResetPlayer(name, player)
    if not name then return end
    if not player then return end
    if not self.db.factionrealm[name].alts[player] then return end

    self.db.factionrealm[name].alts[player] = {}

    GBankClassic_Core:Print("Reset player database")
end

function GBankClassic_Database:Load(name)
    if not name then return end

    local db = self.db.factionrealm[name]

    if db == nil or db.roster == nil then
        GBankClassic_Database:Reset(name)
        db = self.db.factionrealm[name]
    elseif db.name == nil then
        db.name = name
    end

    return db
end
