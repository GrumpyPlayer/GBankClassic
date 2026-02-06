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
	-- self.db.global.requests = self.db.global.requests or { maxRequestPercent = 100}
	-- self.db.global.requests["maxRequestPercent"] = self.db.global.requests["maxRequestPercent"] or 100
	
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
					["chunk"] = {
						order = 14,
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
					["donation"] = {
						order = 15,
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
					["whisper"] = {
						order = 16,
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
					-- ["requests"] = {
					-- 	order = 17,
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
					["ui"] = {
						order = 18,
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
						order = 19,
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
						order = 20,
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
						order = 21,
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
					["inventory"] = {
						order = 22,
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
					["mail"] = {
						order = 23,
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
					["item"] = {
						order = 24,
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
					-- ["fulfill"] = {
					-- 	order = 25,
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
					["search"] = {
						order = 26,
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
			-- requests = {
			-- 	order = 3,
			-- 	type = "group",
			-- 	name = "Requests",
			-- 	hidden = function()
			-- 		-- Only show to officers
			-- 		return not CanViewOfficerNote()
			-- 	end,
			-- 	args = {
			-- 		["requestsHeader"] = {
			-- 			order = 0,
			-- 			type = "header",
			-- 			name = "Request settings",
			-- 		},
			-- 		["requestsDesc"] = {
			-- 			order = 1,
			-- 			type = "description",
			-- 			name = "Configure how item requests work to help manage bank inventory fairly.",
			-- 		},
			-- 		["maxRequestPercent"] = {
			-- 			order = 2,
			-- 			type = "range",
			-- 			width = "full",
			-- 			name = "Maximum request amount",
			-- 			desc = "Limit how much of available inventory can be requested at once. Set to 100% to allow requesting everything. Lower values help share inventory among multiple guild members.\n\nExample: At 50%, if bank has 100 Copper Ore, members can request up to 50.\n\nNote: Single items (like gear) can always be requested even at low percentages.",
			-- 			min = 1,
			-- 			max = 100,
			-- 			step = 1,
			-- 			get = function()
			-- 				return Options:GetMaxRequestPercent()
			-- 			end,
			-- 			set = function(_, v)
			-- 				-- Write to guild-synced settings (propagates to all clients)
			-- 				if GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.settings then
			-- 					GBankClassic_Guild.Info.settings.maxRequestPercent = v
			-- 					-- Broadcast settings change to guild
			-- 					if GBankClassic_Guild.SendRequestsData then
			-- 						GBankClassic_Guild:SendRequestsData()
			-- 					end
			-- 				end
			-- 				-- Also write to local settings as backup
			-- 				self.db.global.requests.maxRequestPercent = v
			-- 				GBankClassic_Output:Info("Maximum request amount set to %d%% (syncing to guild...)", v)
			-- 			end,
			-- 		},
			-- 		["exampleGroup"] = {
			-- 			order = 3,
			-- 			type = "group",
			-- 			inline = true,
			-- 			name = "Example calculations",
			-- 			args = {
			-- 				["example1"] = {
			-- 					order = 1,
			-- 					type = "description",
			-- 					fontSize = "medium",
			-- 					name = function()
			-- 						local pct = self.db.global.requests.maxRequestPercent or 100
			-- 						local available = 100
			-- 						local maxRequest = math.max(1, math.floor(available * pct / 100))

			-- 						return string.format("|cff00ff00Current setting: %d%%|r\n\nIf bank has %d items available:\n  Max: |cffffd700%d items|r", pct, available, maxRequest)
			-- 					end,
			-- 				},
			-- 				["example2"] = {
			-- 					order = 2,
			-- 					type = "description",
			-- 					fontSize = "medium",
			-- 					name = function()
			-- 						local pct = self.db.global.requests.maxRequestPercent or 100
			-- 						local available = 1
			-- 						local maxRequest = math.max(1, math.floor(available * pct / 100))

			-- 						return string.format("If bank has %d item available (gear/single):\n  Max: |cffffd700%d item|r", available, maxRequest)
			-- 					end,
			-- 				},
			-- 			},
			-- 		},
			-- 	},
			-- },
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("GBankClassic - Revived", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("GBankClassic - Revived", "GBankClassic - Revived")
end

function Options:InitGuild()
    local player = GBankClassic_Guild:GetPlayer()
    if not GBankClassic_Guild:IsBank(player) then 
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

-- function Options:GetMaxRequestPercent()
-- 	-- Read from guild-synced settings first (officer-configured, syncs to all clients)
-- 	if GBankClassic_Guild and GBankClassic_Guild.Info and GBankClassic_Guild.Info.settings then
-- 		return GBankClassic_Guild.Info.settings.maxRequestPercent or 100
-- 	end
-- 	-- Fall back to local setting if guild data not loaded yet
-- 	if not self.db or not self.db.global or not self.db.global.requests then
-- 		return 100
-- 	end

-- 	return self.db.global.requests.maxRequestPercent or 100
-- end

function Options:Open()
    Settings.OpenToCategory("GBankClassic - Revived")
end