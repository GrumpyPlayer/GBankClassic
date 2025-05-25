GBankClassic_Options = {}

function GBankClassic_Options:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicOptionDB")
    if self.db.char.minimap == nil then
        self.db.char.minimap = {enabled = true}
    end
    if self.db.char.combat == nil then
        self.db.char.combat = {hide = true}
    end
    if self.db.char.bank == nil then
        self.db.char.bank = {}
    end
    if self.db.char.bank['donations'] == nil then
        self.db.char.bank['donations'] = true
    end
    if self.db.global.bank == nil then
        self.db.global.bank = {report = true, shutup = false}
    end

    local options = {
        type = "group",
        ---START CHANGES
        --name = "GBankClassic",
        name = "GBankClassic - Revived",
        ---END CHANGES
        args = {
            ["minimap"] = {
                order = 0,
                type = "toggle",
                name = "Show Minimap Button",
                desc = "Toggles visibility of the minimap button",
                set = function(_, v)
                    self.db.char.minimap["enabled"] = v
                    GBankClassic_UI_Minimap:Toggle()
                end,
                get = function() return self.db.char.minimap["enabled"] end,
            },
            ["combat"] = {
                order = 1,
                type = "toggle",
                name = "Hide During Combat",
                desc = "Toggles visibility of the window during combat",
                set = function(_, v)
                    self.db.char.combat["hide"] = v
                end,
                get = function() return self.db.char.combat["hide"] end,
            },
            ["shutup"] = {
                order = 2,
                type = "toggle",
                name = "Mute addon messages",
                desc = "Stops the addon from sending messages to the chat window",
                set = function(_, v) self.db.global.bank['shutup'] = v end,
                get = function() return self.db.global.bank['shutup'] end
            },
            ["reset"] = {
                order = -1,
                name = "Reset Database",
                type = "execute",
                func = function()
                    local guild = GBankClassic_Guild:GetGuild()
                    if not guild then return end
                    GBankClassic_Guild:Reset(guild)
                end,
            }
        }
    }

    ---START CHANGES
    --LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic", options)
    --LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic", "GBankClassic")
    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived", "GBankClassic - Revived")
    ---END CHANGES
end

function GBankClassic_Options:InitGuild()
    ---START CHANGES
    -- Guild banks shouldn't be required to read the officer note, perhaps we want to use public note
    --if not CanViewOfficerNote() then return end
    ---END CHANGES

    local player = GBankClassic_Guild:GetPlayer()
    if not GBankClassic_Guild:IsBank(player) then return end

    local bankOptions = {
        type = "group",
        name = "Bank",
        args = {
            ["enabled"] = {
                order = 0,
                type = "toggle",
                name = "Enable for " .. player,
                desc = "Enables reporting and scanning for this player",
                set = function(_, v) self.db.char.bank['enabled'] = v end,
                get = function() return self.db.char.bank['enabled'] end
            },
            ["report"] = {
                order = 0,
                type = "toggle",
                name = "Report contributions",
                desc = "Enables contribution reports",
                set = function(_, v) self.db.global.bank['report'] = v end,
                get = function() return self.db.global.bank['report'] end
            },
            ["donations"] = {
                order = 1,
                type = "toggle",
                name = "Enable donations",
                desc = "Displays donation window at mailbox",
                set = function(_, v) self.db.char.bank['donations'] = v end,
                get = function() return self.db.char.bank['donations'] end
            },
            ["reset"] = {
                order = 2,
                name = "Reset Player Database",
                type = "execute",
                func = function()
                    local guild = GBankClassic_Guild:GetGuild()
                    if not guild then return end
                    GBankClassic_Database:ResetPlayer(guild, player)
                end,
            }
        },
    }

    ---START CHANGES
    --LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic/Bank", bankOptions)
    --LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic/Bank", "Bank", "GBankClassic")
    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived/Bank", bankOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived/Bank", "Bank", "GBankClassic - Revived")
    ---END CHANGES
end

function GBankClassic_Options:GetBankEnabled()
    return self.db.char.bank['enabled']
end

function GBankClassic_Options:GetDonationEnabled()
    return self.db.char.bank['donations']
end

function GBankClassic_Options:GetBankReporting()
    return self.db.global.bank['report']
end

function GBankClassic_Options:GetBankVerbosity()
    if self.db.global.bank['shutup'] == nil then
        return false
    end
    return self.db.global.bank['shutup']
end

function GBankClassic_Options:GetMinimapEnabled()
    return self.db.char.minimap["enabled"]
end

function GBankClassic_Options:GetCombatHide()
    return self.db.char.combat["hide"]
end

function GBankClassic_Options:Open()
    -- NOTE: WoW API bug, requires call twice to open to specific category
    ---START CHANGES    
    Settings.OpenToCategory("GBankClassic - Revived")
    ---END CHANGES
end