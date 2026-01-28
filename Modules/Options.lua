GBankClassic_Options = {}

function GBankClassic_Options:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicOptionDB")
    self.db.char = self.db.char or {}
    self.db.char.minimap = self.db.char.minimap or { enabled = true }
    self.db.char.combat = self.db.char.combat or { hide = true }
    self.db.char.bank = self.db.char.bank or { donations = true }
    self.db.char.framePositions = self.db.char.framePositions or { }
    self.db.char.bank['donations'] = (self.db.char.bank['donations'] == nil) and true or self.db.char.bank['donations']
    self.db.global = self.db.global or {}
    self.db.global.bank = self.db.global.bank or { report = true, logLevel = LOG_LEVEL.INFO, commDebug = false, muteSyncProgress = false }
	self.db.global.bank["logLevel"] = self.db.global.bank["logLevel"] or LOG_LEVEL.INFO
	self.db.global.bank["commDebug"] = self.db.global.bank["commDebug"] or false
	self.db.global.bank["muteSyncProgress"] = self.db.global.bank["muteSyncProgress"] or false

    -- Initialize logger with saved level
	GBankClassic_Output:SetLevel(self.db.global.bank["logLevel"])
	-- Initialize comm debug with saved setting
	GBankClassic_Output:SetCommDebug(self.db.global.bank["commDebug"])

    local options = {
        type = "group",
        name = "GBankClassic - Revived",
		childGroups = "tab",
        args = {
			general = {
				order = 1,
				type = "group",
				name = "General",
				args = {
                    ["minimap"] = {
                        order = 0,
                        type = "toggle",
						width = "full",
                        name = "Show minimap button",
                        desc = "Toggles visibility of the minimap button",
                        set = function(_, v)
                            self.db.char.minimap["enabled"] = v
                            GBankClassic_UI_Minimap:Toggle()
                        end,
                        get = function()
                            return self.db.char.minimap["enabled"]
                        end,
                    },
                    ["combat"] = {
                        order = 1,
                        type = "toggle",
						width = "full",
                        name = "Hide during combat",
                        desc = "Toggles visibility of the window during combat",
                        set = function(_, v)
                            self.db.char.combat["hide"] = v
                        end,
                        get = function()
                            return self.db.char.combat["hide"]
                        end,
                    },
                    ["logLevel"] = {
                        order = 2,
						type = "select",
						style = "radio",
						width = "full",
						name = "Log level",
						desc = "Controls which messages are shown in chat",
						values = {
							[LOG_LEVEL.RESPONSE] = "Quiet (only respond to /bank commands)",
							[LOG_LEVEL.ERROR] = "Errors and above",
							[LOG_LEVEL.WARN] = "Warnings and above",
							[LOG_LEVEL.INFO] = "Info and above (default)",
							[LOG_LEVEL.DEBUG] = "Debug (show everything)",
						},
						sorting = { LOG_LEVEL.RESPONSE, LOG_LEVEL.ERROR, LOG_LEVEL.WARN, LOG_LEVEL.INFO, LOG_LEVEL.DEBUG },
						set = function(_, v)
							self.db.global.bank["logLevel"] = v
							GBankClassic_Output:SetLevel(v)
						end,
						get = function()
							return self.db.global.bank["logLevel"]
						end,
                    },
					["muteSyncProgress"] = {
						order = 2.6,
						type = "toggle",
						width = "full",
						name = "Mute sync progress messages",
						desc = "Hides 'Sharing guild bank data...' and 'Send complete...' messages during data sync",
						set = function(_, v)
							self.db.global.bank["muteSyncProgress"] = v
						end,
						get = function()
							return self.db.global.bank["muteSyncProgress"]
						end,
					},
                    ["reset"] = {
                        order = -1,
                        name = "Reset database",
                        type = "execute",
                        func = function()
                            local guild = GBankClassic_Guild:GetGuild()
                            if not guild then
                                return
							end
                            GBankClassic_Guild:Reset(guild)
                        end,
                    },
                },
            },
			debug = {
				order = 2,
				type = "group",
				name = "Debug",
				args = {
					["debugHeader"] = {
						order = 0,
						type = "header",
						name = "Debug categories",
					},
					["debugDesc"] = {
						order = 1,
						type = "description",
						name = "Enable specific debug categories to filter output. Categories are only active when log level is set to 'Debug'.",
					},
					["showUncategorized"] = {
						order = 2,
						type = "toggle",
						width = "full",
						name = "Show uncategorized debug messages",
						desc = "Show debug messages that don't have a category assigned. Disable this to only see categorized messages.",
						set = function(_, v)
							GBankClassic_Database.db.global.showUncategorizedDebug = v
						end,
						get = function()
							return GBankClassic_Database.db.global.showUncategorizedDebug
						end,
					},
					["spacer1"] = {
						order = 9,
						type = "description",
						name = " ",
					},
					["roster"] = {
						order = 10,
						type = "toggle",
						width = "full",
						name = "ROSTER - Guild roster updates, online/offline tracking",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("ROSTER", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("ROSTER")
						end,
					},
					["comms"] = {
						order = 11,
						type = "toggle",
						width = "full",
						name = "COMMS - All addon communication traffic (high volume)",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("COMMS", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("COMMS")
						end,
					},
					["delta"] = {
						order = 12,
						type = "toggle",
						width = "full",
						name = "DELTA - Delta sync operations and computations",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("DELTA", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("DELTA")
						end,
					},
					["sync"] = {
						order = 13,
						type = "toggle",
						width = "full",
						name = "SYNC - Data synchronization operations",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("SYNC", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("SYNC")
						end,
					},
					["cache"] = {
						order = 14,
						type = "toggle",
						width = "full",
						name = "CACHE - Cache operations (guild roster cache, etc.)",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("CACHE", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("CACHE")
						end,
					},
					["whisper"] = {
						order = 15,
						type = "toggle",
						width = "full",
						name = "WHISPER - Whisper sends, skips, and online checks",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("WHISPER", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("WHISPER")
						end,
					},
					["ui"] = {
						order = 17,
						type = "toggle",
						width = "full",
						name = "UI - Interface operations (window opens/closes)",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("UI", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("UI")
						end,
					},
					["protocol"] = {
						order = 18,
						type = "toggle",
						width = "full",
						name = "PROTOCOL - Protocol version negotiation",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("PROTOCOL", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("PROTOCOL")
						end,
					},
					["database"] = {
						order = 19,
						type = "toggle",
						width = "full",
						name = "DATABASE - Database and SavedVariables operations",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("DATABASE", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("DATABASE")
						end,
					},
					["events"] = {
						order = 20,
						type = "toggle",
						width = "full",
						name = "EVENTS - WoW event handling (GUILD_ROSTER_UPDATE, etc.)",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("EVENTS", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("EVENTS")
						end,
					},
					["spacer"] = {
						order = 30,
						type = "description",
						name = " ",
					},
					["enableAll"] = {
						order = 31,
						type = "execute",
						name = "Enable all categories",
						func = function()
							GBankClassic_Output:EnableAllCategories()
							GBankClassic_Output:Info("All debug categories enabled")
						end,
					},
					["disableAll"] = {
						order = 32,
						type = "execute",
						name = "Disable all categories",
						func = function()
							GBankClassic_Output:DisableAllCategories()
							GBankClassic_Output:Info("All debug categories disabled")
						end,
					},
					["spacer2"] = {
						order = 40,
						type = "description",
						name = " ",
					},
				},
			},
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived", "GBankClassic - Revived")
end

function GBankClassic_Options:InitGuild()
    local player = GBankClassic_Guild:GetPlayer()
    if not GBankClassic_Guild:IsBank(player) then 
        return
    end

    if self.db and self.db.char and self.db.char.bank and self.db.char.bank["enabled"] == nil then
        self.db.char.bank["enabled"] = true
        GBankClassic_Guild:AuthorRosterData()
    end

    local bankOptions = {
        type = "group",
		name = "Bank",
        hidden = function()
            local player = GBankClassic_Guild:GetPlayer()
            return not GBankClassic_Guild:IsBank(player)
        end,
        args = {
            ["enabled"] = {
                order = 0,
                type = "toggle",
				width = "full",
                name = "Enable for " .. player,
                desc = "Enables reporting and scanning for this player",
                set = function(_, v) 
                    self.db.char.bank["enabled"] = v 
                    if v == true then
                        GBankClassic_Guild:AuthorRosterData()
                    end
                end,
                get = function()
                    return self.db.char.bank["enabled"]
                end,
            },
            ["report"] = {
                order = 1,
                type = "toggle",
				width = "full",
                name = "Report contributions",
                desc = "Enables contribution reports",
                set = function(_, v)
                    self.db.global.bank["report"] = v
				end,
                get = function()
                    return self.db.global.bank["report"]
                end,
            },
            ["donations"] = {
                order = 2,
                type = "toggle",
				width = "full",
                name = "Enable donations",
                desc = "Displays donation window at mailbox",
                set = function(_, v)
                    self.db.char.bank["donations"] = v
                end,
                get = function()
                    return self.db.char.bank["donations"]
                end,
            },
            ["reset"] = {
                order = 3,
                name = "Reset player database",
                type = "execute",
                func = function()
                    local guild = GBankClassic_Guild:GetGuild()
                    if not guild then
                        return
                    end
                    GBankClassic_Database:ResetPlayer(guild, player)
                end,
            },
            ["error"] = {
                order = 4,
                type = "description",
                name = "This panel is only available to bank alts.",
                desc = "This panel is only available to bank alts.",
                hidden = function()
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
    return self.db.char.bank["enabled"]
end

function GBankClassic_Options:GetDonationEnabled()
    return self.db.char.bank["donations"]
end

function GBankClassic_Options:GetBankReporting()
    return self.db.global.bank["report"]
end

function GBankClassic_Options:GetLogLevel()
	return self.db.global.bank["logLevel"] or LOG_LEVEL.INFO
end

function GBankClassic_Options:GetMinimapEnabled()
    return self.db.char.minimap["enabled"]
end

function GBankClassic_Options:GetCombatHide()
    return self.db.char.combat["hide"]
end

function GBankClassic_Options:IsSyncProgressMuted()
	return self.db.global.bank["muteSyncProgress"] or false
end

function GBankClassic_Options:Open()
    Settings.OpenToCategory("GBankClassic - Revived")
end