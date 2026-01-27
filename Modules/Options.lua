GBankClassic_Options = {}

function GBankClassic_Options:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicOptionDB")
    self.db.char = self.db.char or {}
    self.db.char.minimap = self.db.char.minimap or { enabled = true }
    self.db.char.combat = self.db.char.combat or { hide = true }
    self.db.char.bank = self.db.char.bank or { donations = true }
    self.db.char.bank['donations'] = (self.db.char.bank['donations'] == nil) and true or self.db.char.bank['donations']
    self.db.global = self.db.global or {}
    self.db.global.bank = self.db.global.bank or { report = true, shutup = false, prefer_direct_all = false }

    local options = {
        type = "group",
        name = "GBankClassic - Revived",
        args = {
            ["minimap"] = {
                order = 0,
                type = "toggle",
                name = "Show minimap button",
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
                name = "Hide during combat",
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
                set = function(_, v)
                    self.db.global.bank['shutup'] = v
                end,
                get = function() return self.db.global.bank['shutup'] end
            },
            ["prefer_direct"] = {
                order = 3,
                type = "toggle",
                name = "Prefer direct-only",
                desc = "When enabled, this account will refuse relayed alt/roster payloads and prefer direct updates from banks/GMs/officers",
                set = function(_, v)
                    self.db.global.bank['prefer_direct_all'] = v
                end,
                get = function() return self.db.global.bank['prefer_direct_all'] end
            },
            ["reset"] = {
                order = -1,
                name = "Reset database",
                type = "execute",
                func = function()
                    local guild = GBankClassic_Guild:GetGuild()
                    if not guild then return end
                    GBankClassic_Guild:Reset(guild)
                end,
            }
        }
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived", "GBankClassic - Revived")
end

function GBankClassic_Options:InitGuild()
    local player = GBankClassic_Guild:GetPlayer()
    if not GBankClassic_Guild:IsBank(player) then 
        return
    end

    if self.db and self.db.char and self.db.char.bank and self.db.char.bank['enabled'] == nil then
        self.db.char.bank['enabled'] = true
        GBankClassic_Guild:AuthorRosterData()
    end

    local bankOptions = {
        type = "group",
        name = function()
            local player = GBankClassic_Guild:GetPlayer()
            if GBankClassic_Guild:IsBank(player) then
                return "Bank"
            end
            return "Error"
        end,
        hidden = function()
            local player = GBankClassic_Guild:GetPlayer()
            return not GBankClassic_Guild:IsBank(player)
        end,
        args = {
            ["enabled"] = {
                order = 0,
                type = "toggle",
                name = "Enable for " .. player,
                desc = "Enables reporting and scanning for this player",
                set = function(_, v) 
                    self.db.char.bank['enabled'] = v 
                    if v == true then
                        GBankClassic_Guild:AuthorRosterData()
                    end
                end,
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
                name = "Reset player database",
                type = "execute",
                func = function()
                    local guild = GBankClassic_Guild:GetGuild()
                    if not guild then return end
                    local player = GBankClassic_Guild:GetPlayer()
                    GBankClassic_Database:ResetPlayer(guild, player)
                end,
            },
            ["error"] = {
                order = 3,
                type = "description",
                name = "This panel is only available to bank alts.",
                desc = "This panel is only available to bank alts.",
                hidden = function()
                    local player = GBankClassic_Guild:GetPlayer()
                    return GBankClassic_Guild:IsBank(player)
                end,
            },
        },
    }
    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived/Bank", bankOptions)
    if self.optionsAdded then return end
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived/Bank", "Bank", "GBankClassic - Revived")
    self.optionsAdded = true
end

function GBankClassic_Options:GetBankEnabled()
    if not self.db or not self.db.char or not self.db.char.bank then return false end
    return self.db.char.bank['enabled']
end

function GBankClassic_Options:GetDonationEnabled()
    if not self.db or not self.db.char or not self.db.char.bank then return false end
    return self.db.char.bank['donations']
end

function GBankClassic_Options:GetBankReporting()
    if not self.db or not self.db.global or not self.db.global.bank then return true end
    return self.db.global.bank['report']
end

function GBankClassic_Options:GetBankVerbosity()
    if not self.db or not self.db.global or not self.db.global.bank then return false end
    if self.db.global.bank['shutup'] == nil then
        return false
    end
    return self.db.global.bank['shutup']
end

function GBankClassic_Options:GetPreferDirect()
    if not self.db or not self.db.global or not self.db.global.bank then return false end
    if self.db.global.bank['prefer_direct_all'] == nil then return false end
    return self.db.global.bank['prefer_direct_all']
end

function GBankClassic_Options:GetMinimapEnabled()
    if not self.db or not self.db.char or not self.db.char.minimap then return true end
    return self.db.char.minimap["enabled"]
end

function GBankClassic_Options:GetCombatHide()
    if not self.db or not self.db.char or not self.db.char.combat then return true end
    return self.db.char.combat["hide"]
end

function GBankClassic_Options:Open()
    Settings.OpenToCategory("GBankClassic - Revived")
end