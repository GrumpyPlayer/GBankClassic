local addonName, GBCR = ...

GBCR.Options = {}
local Options = GBCR.Options

local Globals = GBCR.Globals
local Settings = Globals.Settings

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD
local logLevels = Constants.LOG_LEVEL
local logLevelDescriptions = Constants.LOG_LEVEL_BY_VALUE

function Options:Init()
    self.db = GBCR.Libs.AceDB:New("GBCR_Options_DB", {
		char = {
			bank = {
				inventoryTracking = true,
				donationsTracking = true,
				reportReceivedDonations = true,
			},
		},
		profile = {
			combat = {
				hide = true,
			},
			minimap = {
				hide = false,
			},
            framePositions = {
				width = 700,
				height = 500,
            },
			logLevel = logLevels.INFO.level,
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
				-- QUERIES = false,
				REPLIES = false,
			},
			sortMode = "default"
		},
	}, true)

	-- Log level configuration
	local values = {}
	local sorting = {}
	for _, info in pairs(logLevels) do
		values[info.level] = info.description
		table.insert(sorting, info.level)
	end
	table.sort(sorting, function(a, b)
		return a > b
	end)

	-- Configuration options
    local options = {
        type = "group",
        name = function()
    		return GBCR.Core.addonHeader
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
                            self.db.profile.minimap.hide = not v
                            GBCR.UI.Minimap:Toggle()
                        end,
                        get = function()
                            return self:GetMinimapEnabled()
                        end,
                    },
                    ["combat"] = {
                        order = 1,
                        type = "toggle",
						width = "full",
                        name = "Hide during combat",
                        desc = "Toggles visibility of the window during combat",
                        set = function(_, v)
                            self.db.profile.combat.hide = v
                        end,
                        get = function()
                            return self:GetCombatHide()
                        end,
                    },
                    ["logLevel"] = {
                        order = 2,
						type = "select",
						style = "radio",
						width = "full",
						name = "Log level",
						desc = "Controls which messages are shown in chat",
						values = values,
						sorting = sorting,
						set = function(_, v)
							self:SetLogLevel(v)
						end,
						get = function()
							return self:GetLogLevel()
						end,
                    },
                    ["reset"] = {
                        order = -1,
                        name = "Reset database",
                        type = "execute",
                        func = function()
                            local guild = GBCR.Guild:GetGuildName()
                            if not guild then
                                return
							end

                            GBCR.Guild:Reset(guild)
                        end,
                    },
                },
            },
			debug = {
				order = 2,
				type = "group",
				name = "Debug",
				disabled = function()
					return not self:IsDebugEnabled()
				end,
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
							self:SetCategoryEnabled("CHUNK", v)
						end,
						get = function()
							return self:IsCategoryEnabled("CHUNK")
						end,
					},
					["comms"] = {
						order = 11,
						type = "toggle",
						width = "full",
						name = "COMMS - All addon communication traffic (high volume)",
						set = function(_, v)
							self:SetCategoryEnabled("COMMS", v)
						end,
						get = function()
							return self:IsCategoryEnabled("COMMS")
						end,
					},
					["database"] = {
						order = 12,
						type = "toggle",
						width = "full",
						name = "DATABASE - Database and SavedVariables operations",
						set = function(_, v)
							self:SetCategoryEnabled("DATABASE", v)
						end,
						get = function()
							return self:IsCategoryEnabled("DATABASE")
						end,
					},
					["donation"] = {
						order = 13,
						type = "toggle",
						width = "full",
						name = "DONATION - Donation ledger operations",
						set = function(_, v)
							self:SetCategoryEnabled("DONATION", v)
						end,
						get = function()
							return self:IsCategoryEnabled("DONATION")
						end,
					},
					["events"] = {
						order = 14,
						type = "toggle",
						width = "full",
						name = "EVENTS - WoW event handling (GUILD_ROSTER_UPDATE, etc.)",
						set = function(_, v)
							self:SetCategoryEnabled("EVENTS", v)
						end,
						get = function()
							return self:IsCategoryEnabled("EVENTS")
						end,
					},
					-- ["fulfill"] = {
					-- 	order = 15,
					-- 	type = "toggle",
					-- 	width = "full",
					-- 	name = "FULFILL - Fulfilling requests",
					-- 	set = function(_, v)
					-- 		self:SetCategoryEnabled("FULFILL", v)
					-- 	end,
					-- 	get = function()
					-- 		return self:IsCategoryEnabled("FULFILL")
					-- 	end,
					-- },
					["inventory"] = {
						order = 16,
						type = "toggle",
						width = "full",
						name = "INVENTORY - Inventory (bank/bag/mail) scanning and tracking",
						set = function(_, v)
							self:SetCategoryEnabled("INVENTORY", v)
						end,
						get = function()
							return self:IsCategoryEnabled("INVENTORY")
						end,
					},
					["item"] = {
						order = 17,
						type = "toggle",
						width = "full",
						name = "ITEM - Item loading, validation, and processing",
						set = function(_, v)
							self:SetCategoryEnabled("ITEM", v)
						end,
						get = function()
							return self:IsCategoryEnabled("ITEM")
						end,
					},
					-- ["mail"] = {
					-- 	order = 18,
					-- 	type = "toggle",
					-- 	width = "full",
					-- 	name = "MAIL - Mail inventory scanning and tracking",
					-- 	set = function(_, v)
					-- 		self:SetCategoryEnabled("MAIL", v)
					-- 	end,
					-- 	get = function()
					-- 		return self:IsCategoryEnabled("MAIL")
					-- 	end,
					-- },
					["protocol"] = {
						order = 19,
						type = "toggle",
						width = "full",
						name = "PROTOCOL - Protocol version negotiation and debouncing",
						set = function(_, v)
							self:SetCategoryEnabled("PROTOCOL", v)
						end,
						get = function()
							return self:IsCategoryEnabled("PROTOCOL")
						end,
					},
					-- ["queries"] = {
					-- 	order = 20,
					-- 	type = "toggle",
					-- 	width = "full",
					-- 	name = "QUERIES - Peer query/response decisions and hash matching",
					-- 	set = function(_, v)
					-- 		self:SetCategoryEnabled("QUERIES", v)
					-- 	end,
					-- 	get = function()
					-- 		return self:IsCategoryEnabled("QUERIES")
					-- 	end,
					-- },
					["replies"] = {
						order = 21,
						type = "toggle",
						width = "full",
						name = "REPLIES - Output from addon communication replies (such as /bank hello)",
						set = function(_, v)
							self:SetCategoryEnabled("REPLIES", v)
						end,
						get = function()
							return self:IsCategoryEnabled("REPLIES")
						end,
					},
					-- ["requests"] = {
					-- 	order = 22,
					-- 	type = "toggle",
					-- 	width = "full",
					-- 	name = "REQUESTS - Request system activity and updates",
					-- 	set = function(_, v)
					-- 		self:SetCategoryEnabled("REQUESTS", v)
					-- 	end,
					-- 	get = function()
					-- 		return self:IsCategoryEnabled("REQUESTS")
					-- 	end,
					-- },
					["roster"] = {
						order = 23,
						type = "toggle",
						width = "full",
						name = "ROSTER - Guild roster updates, online/offline tracking",
						set = function(_, v)
							self:SetCategoryEnabled("ROSTER", v)
						end,
						get = function()
							return self:IsCategoryEnabled("ROSTER")
						end,
					},
					["search"] = {
						order = 24,
						type = "toggle",
						width = "full",
						name = "SEARCH - Search operations",
						set = function(_, v)
							self:SetCategoryEnabled("SEARCH", v)
						end,
						get = function()
							return self:IsCategoryEnabled("SEARCH")
						end,
					},
					["sync"] = {
						order = 25,
						type = "toggle",
						width = "full",
						name = "SYNC - Data synchronization operations",
						set = function(_, v)
							self:SetCategoryEnabled("SYNC", v)
						end,
						get = function()
							return self:IsCategoryEnabled("SYNC")
						end,
					},
					["ui"] = {
						order = 26,
						type = "toggle",
						width = "full",
						name = "UI - Interface operations (window opens/closes)",
						set = function(_, v)
							self:SetCategoryEnabled("UI", v)
						end,
						get = function()
							return self:IsCategoryEnabled("UI")
						end,
					},
					["whisper"] = {
						order = 27,
						type = "toggle",
						width = "full",
						name = "WHISPER - Whisper sends, skips, and online checks",
						set = function(_, v)
							self:SetCategoryEnabled("WHISPER", v)
						end,
						get = function()
							return self:IsCategoryEnabled("WHISPER")
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
							self:EnableAllCategories()
							GBCR.Output:Response("All debug categories enabled.")
						end,
					},
					["disableAll"] = {
						order = 32,
						type = "execute",
						name = "Disable all categories",
						func = function()
							self:DisableAllCategories()
							GBCR.Output:Response("All debug categories disabled.")
						end,
					},
					["spacer2"] = {
						order = 40,
						type = "description",
						name = " ",
					},
				},
			},
			profiles = GBCR.Libs.AceDBOptions:GetOptionsTable(self.db),
        },
    }

	-- Register configuration options with AceConfig
    GBCR.Libs.AceConfig:RegisterOptionsTable("GBankClassic - Revived", options)
    GBCR.Libs.AceConfigDialog:AddToBlizOptions("GBankClassic - Revived", "GBankClassic - Revived")

	-- Register callbacks for configuration profiles
	self.db.RegisterCallback(GBCR, "OnProfileChanged", function(event, db, newProfileName)
		GBCR.Output:Response("Switched to profile %s.", GBCR.Globals:Colorize(colorGold, newProfileName))
	end)
	self.db.RegisterCallback(GBCR, "OnProfileCopied", function(event, db, sourceProfileName)
		GBCR.Output:Response("Copied profile from %s.", GBCR.Globals:Colorize(colorGold, sourceProfileName))
	end)
	self.db.RegisterCallback(GBCR, "OnProfileReset", function(event, db)
		GBCR.Output:Response("Profile reset to defaults.")
	end)
	self.db.RegisterCallback(GBCR, "OnProfileDeleted", function(event, db, deletedProfile)
		GBCR.Output:Response("Profile %s deleted.", GBCR.Globals:Colorize(colorGold, deletedProfile))
	end)
end

function Options:InitGuildBankAltOptions()
    local player = GBCR.Guild:GetNormalizedPlayer()
    if not GBCR.Guild:IsGuildBankAlt(player) then
        return
    end

	-- Configuration options for guild bank alts
    local guildBankAltOptions = {
        type = "group",
		name = "Bank",
        hidden = function()
            return not GBCR.Guild:IsGuildBankAlt(player)
        end,
        args = {
            ["inventoryTracking"] = {
                order = 0,
                type = "toggle",
				width = "full",
                name = "Enable for " .. player,
                desc = "Enables inventory (bank, bags, and mailbox) scanning and sharing for this player",
                set = function(_, v)
                    self.db.char.bank.inventoryTracking = v
                    if v == true then
                        GBCR.Protocol:AuthorRosterData()
                    end
                end,
                get = function()
                    return self:GetInventoryTrackingEnabled()
                end,
            },
            ["donationsTracking"] = {
                order = 1,
                type = "toggle",
				width = "full",
                name = "Enable donation tracking",
                desc = "Enables tracking and sharing of donations by other guild members sent to you via the mailbox",
                set = function(_, v)
                    self.db.char.bank.donationsTracking = v
                end,
                get = function()
                    return self:GetDonationsTrackingEnabled()
                end,
            },
            ["reportReceivedDonations"] = {
                order = 2,
                type = "toggle",
				width = "full",
                name = "Report received donations",
                desc = "Display a message when donations by other guild members are processed (by taking items and money sent via mail)",
                set = function(_, v)
                    self.db.char.bank.reportReceivedDonations = v
				end,
                get = function()
                    return self:GetDonationReportingEnabled()
                end,
            },
            ["reset"] = {
                order = 3,
                name = "Reset player database",
                type = "execute",
                func = function()
                    local guild = GBCR.Guild:GetGuildName()
                    if not guild then
                        return
                    end

                    GBCR.Database:ResetPlayer(guild, player)
                end,
            },
            ["error"] = {
                order = 4,
                type = "description",
                name = string.format("This panel is only available to guild bank alts (guild members with %s in either their public or officer note that they themselves can read).", GBCR.Globals:Colorize(colorGold, "gbank")),
                hidden = function()
                    return GBCR.Guild:IsGuildBankAlt(player)
                end,
            },
        },
    }

	-- Register configuration options for guild bank alts with AceConfig
    GBCR.Libs.AceConfig:RegisterOptionsTable("GBankClassic - Revived/Bank", guildBankAltOptions)
	if self.optionsAdded then
		return
	end
    GBCR.Libs.AceConfigDialog:AddToBlizOptions("GBankClassic - Revived/Bank", "Bank", "GBankClassic - Revived")
	self.optionsAdded = true

	-- Send an update version of the roster after enabling a new guild bank alt
	GBCR.Protocol:AuthorRosterData()
end

function Options:GetOptionsDB()
	return self.db
end

function Options:GetInventoryTrackingEnabled()
    return self.db.char.bank.inventoryTracking
end

function Options:GetDonationsTrackingEnabled()
    return self.db.char.bank.donationsTracking
end

function Options:GetDonationReportingEnabled()
    return self.db.char.bank.reportReceivedDonations
end

function Options:GetCombatHide()
    return self.db.profile.combat.hide
end

function Options:GetMinimapEnabled()
    return not self.db.profile.minimap.hide
end

function Options:GetFramePositions()
	return self.db.profile.framePositions
end

function Options:GetLogLevel()
	return self.db.profile.logLevel or logLevels.INFO.level
end

function Options:IsDebugEnabled()
    return self:GetLogLevel() == logLevels.DEBUG.level
end

function Options:SetLogLevel(level)
	self.db.profile.logLevel = level
	GBCR.Output:Response("Log level set to: " .. string.lower(logLevelDescriptions[level].description))
    GBCR.Libs.AceConfig:NotifyChange("GBankClassic")
end

function Options:IsCategoryEnabled(category)
	return self.db.profile.debugCategories[category] == true
end

function Options:SetCategoryEnabled(category, enabled)
	self.db.profile.debugCategories[category] = enabled
end

function Options:EnableAllCategories()
	for category, _ in pairs(Constants.DEBUG_CATEGORY) do
		self.db.profile.debugCategories[category] = true
	end
end

function Options:DisableAllCategories()
	for category, _ in pairs(Constants.DEBUG_CATEGORY) do
		self.db.profile.debugCategories[category] = false
	end
end

function Options:GetSortMode()
	return self.db.profile.sortMode or self.db.default.profile.sortMode
end

function Options:SetSortMode(mode)
	self.db.profile.sortMode = mode
end

function Options:Open()
    Settings.OpenToCategory("GBankClassic - Revived")
end