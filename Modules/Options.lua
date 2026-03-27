GBankClassic_Options = GBankClassic_Options or {}

local Options = GBankClassic_Options

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("LibStub")
local LibStub = upvalues.LibStub
local upvalues = Globals.GetUpvalues("Settings")
local Settings = upvalues.Settings

function Options:Init()
    self.db = LibStub("AceDB-3.0"):New("GBankClassicOptionDB")
    self.db.char = self.db.char or {}
    self.db.char.minimap = self.db.char.minimap or { enabled = true }
    self.db.char.combat = self.db.char.combat or { hide = true }
    self.db.char.bank = self.db.char.bank or { donations = true }
    self.db.char.bank['donations'] = (self.db.char.bank['donations'] == nil) and true or self.db.char.bank['donations']
    self.db.char.framePositions = self.db.char.framePositions or {}
    self.db.global = self.db.global or {}
    self.db.global.bank = self.db.global.bank or { report = true, logLevel = LOG_LEVEL.INFO, commDebug = false }
	self.db.global.bank["report"] = self.db.global.bank["report"] or true
	self.db.global.bank["logLevel"] = self.db.global.bank["logLevel"] or LOG_LEVEL.INFO
	self.db.global.bank["commDebug"] = self.db.global.bank["commDebug"] or false

	-- Migrate from old shutup toggle to new logLevel
	if self.db.global.bank["shutup"] ~= nil then
		if self.db.global.bank["shutup"] == true then
			self.db.global.bank["logLevel"] = LOG_LEVEL.RESPONSE
		end
		self.db.global.bank["shutup"] = nil
	end

    -- Initialize
	GBankClassic_Output:SetLevel(self.db.global.bank["logLevel"])
	GBankClassic_Output:SetCommDebug(self.db.global.bank["commDebug"])

    local options = {
        type = "group",
        name = function()
    		return GBankClassic_Core.addonHeader
		end,
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
                    ["reset"] = {
                        order = -1,
                        name = "Reset database",
                        type = "execute",
                        func = function()
                            local guild = GBankClassic_Guild:GetGuildName()
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
					["chunk"] = {
						order = 10,
						type = "toggle",
						width = "full",
						name = "CHUNK - Data synchronization operations specific to chunk sending",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("CHUNK", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("CHUNK")
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
					["database"] = {
						order = 12,
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
					["donation"] = {
						order = 13,
						type = "toggle",
						width = "full",
						name = "DONATION - Donation ledger operations",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("DONATION", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("DONATION")
						end,
					},
					["events"] = {
						order = 14,
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
					-- ["fulfill"] = {
					-- 	order = 15,
					-- 	type = "toggle",
					-- 	width = "full",
					-- 	name = "FULFILL - Fulfilling requests",
					-- 	set = function(_, v)
					-- 		GBankClassic_Output:SetCategoryEnabled("FULFILL", v)
					-- 	end,
					-- 	get = function()
					-- 		return GBankClassic_Output:IsCategoryEnabled("FULFILL")
					-- 	end,
					-- },
					["inventory"] = {
						order = 16,
						type = "toggle",
						width = "full",
						name = "INVENTORY - Inventory (bank/bag/mail) scanning and tracking",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("INVENTORY", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("INVENTORY")
						end,
					},
					["item"] = {
						order = 17,
						type = "toggle",
						width = "full",
						name = "ITEM - Item loading, validation, and processing",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("ITEM", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("ITEM")
						end,
					},
					["mail"] = {
						order = 18,
						type = "toggle",
						width = "full",
						name = "MAIL - Mail inventory scanning and tracking",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("MAIL", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("MAIL")
						end,
					},
					["protocol"] = {
						order = 19,
						type = "toggle",
						width = "full",
						name = "PROTOCOL - Protocol version negotiation and debouncing",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("PROTOCOL", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("PROTOCOL")
						end,
					},
					["queries"] = {
						order = 20,
						type = "toggle",
						width = "full",
						name = "QUERIES - Peer query/response decisions and hash matching",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("QUERIES", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("QUERIES")
						end,
					},
					["replies"] = {
						order = 21,
						type = "toggle",
						width = "full",
						name = "REPLIES - Output from addon communication replies (such as /bank hello)",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("REPLIES", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("REPLIES")
						end,
					},
					-- ["requests"] = {
					-- 	order = 22,
					-- 	type = "toggle",
					-- 	width = "full",
					-- 	name = "REQUESTS - Request system activity and updates",
					-- 	set = function(_, v)
					-- 		GBankClassic_Output:SetCategoryEnabled("REQUESTS", v)
					-- 	end,
					-- 	get = function()
					-- 		return GBankClassic_Output:IsCategoryEnabled("REQUESTS")
					-- 	end,
					-- },
					["roster"] = {
						order = 23,
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
					["search"] = {
						order = 24,
						type = "toggle",
						width = "full",
						name = "SEARCH - Search operations",
						set = function(_, v)
							GBankClassic_Output:SetCategoryEnabled("SEARCH", v)
						end,
						get = function()
							return GBankClassic_Output:IsCategoryEnabled("SEARCH")
						end,
					},
					["sync"] = {
						order = 25,
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
					["ui"] = {
						order = 26,
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
					["whisper"] = {
						order = 27,
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
							GBankClassic_Output:Response("All debug categories enabled.")
						end,
					},
					["disableAll"] = {
						order = 32,
						type = "execute",
						name = "Disable all categories",
						func = function()
							GBankClassic_Output:DisableAllCategories()
							GBankClassic_Output:Response("All debug categories disabled.")
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

function Options:InitGuild()
    local player = GBankClassic_Guild:GetNormalizedPlayer()
    if not GBankClassic_Guild:IsGuildBankAlt(player) then 
        return
    end

    if self.db and self.db.char and self.db.char.bank and self.db.char.bank["enabled"] == nil then
        self.db.char.bank["enabled"] = true

		-- Send an update version of the roster after enabling a new guild bank alt
        GBankClassic_Guild:AuthorRosterData()
    end

    local bankOptions = {
        type = "group",
		name = "Bank",
        hidden = function()
            return not GBankClassic_Guild:IsGuildBankAlt(player)
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
						-- Send an update version of the roster after enabling a new guild bank alt
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
                    local guild = GBankClassic_Guild:GetGuildName()
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
                    return GBankClassic_Guild:IsGuildBankAlt(player)
                end,
            },
        },
    }
    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived/Bank", bankOptions)

    if self.optionsAdded then
		return
	end

    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived/Bank", "Bank", "GBankClassic - Revived")
    self.optionsAdded = true
end

function Options:GetBankEnabled()
    return self.db.char.bank["enabled"]
end

function Options:GetDonationEnabled()
    return self.db.char.bank["donations"]
end

function Options:GetBankReporting()
    return self.db.global.bank["report"]
end

function Options:GetLogLevel()
	return self.db.global.bank["logLevel"] or LOG_LEVEL.INFO
end

function Options:GetMinimapEnabled()
    return self.db.char.minimap["enabled"]
end

function Options:GetCombatHide()
    return self.db.char.combat["hide"]
end

function Options:Open()
    Settings.OpenToCategory("GBankClassic - Revived")
end