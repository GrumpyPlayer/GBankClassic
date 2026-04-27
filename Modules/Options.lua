local addonName, GBCR = ...

GBCR.Options = {}
local Options = GBCR.Options

local Globals = GBCR.Globals
local date = Globals.date
local pairs = Globals.pairs
local string_format = Globals.string_format
local string_lower = Globals.string_lower
local string_match = Globals.string_match
local table_remove = Globals.table_remove
local table_sort = Globals.table_sort

local CreateFrame = Globals.CreateFrame
local GameFontHighlight = Globals.GameFontHighlight
local GetGameTime = Globals.GetGameTime
local GuildControlGetNumRanks = Globals.GuildControlGetNumRanks
local GuildControlGetRankName = Globals.GuildControlGetRankName

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD
local colorGreen = Constants.COLORS.GREEN
local logLevelDescriptions = Constants.LOG_LEVEL_BY_VALUE
local logLevels = Constants.LOG_LEVEL

local Settings = Globals.Settings

-- Retrieve the log level from saved variables or default to INFO
local function getLogLevel(self)
    return self.db.profile.logLevel or logLevels.INFO.level
end

-- Update and save the log level to saved variables
local function setLogLevel(self, level)
    self.db.profile.logLevel = level

    GBCR.Output:Response("Log level set to: " .. string_lower(logLevelDescriptions[level].description) .. ".")
end

-- Return whether debug logging is enabled or disabled
local function isDebugEnabled(self)
    return getLogLevel(self) == logLevels.DEBUG.level
end

-- Disable debug category output for one specific category
local function isCategoryEnabled(self, category)
    return self.db.profile.debugCategories[category] == true
end

-- Enable debug category output for one specific category
local function setCategoryEnabled(self, category, enabled)
    self.db.profile.debugCategories[category] = enabled
end

-- Disable all debug category output
local function enableAllCategories(self)
    for category in pairs(Constants.DEBUG_CATEGORY) do
        self.db.profile.debugCategories[category] = true
    end
end

-- Enable all debug category output
local function disableAllCategories(self)
    for category in pairs(Constants.DEBUG_CATEGORY) do
        self.db.profile.debugCategories[category] = false
    end
end

-- Retrieve the sort mode from saved variables or defaults
local function getSortMode(self)
    return self.db.profile.sortMode or self.db.defaults.profile.sortMode
end

-- Update and save the sort mode to saved variables
local function setSortMode(self, mode)
    self.db.profile.sortMode = mode
end

-- Retrieve the inventory tracking setting from saved variables
local function getInventoryTrackingEnabled(self)
    return self.db.char.bank.inventoryTracking
end

-- Retrieve the donation tracking setting from saved variables
local function getDonationsTrackingEnabled(self)
    return self.db.char.bank.donationsTracking
end

-- Retrieve the donation reporting setting from saved variables
local function getDonationReportingEnabled(self)
    return self.db.char.bank.reportReceivedDonations
end

-- Retrieve the rank fulfillmment setting from saved variables
local function getRankFulfillment(self)
    return self.db.char.bank.rankFulfillment
end

-- Retrieve the combat hide setting from saved variables
local function getCombatHide(self)
    return self.db.profile.combat.hide
end

-- Retrieve the uiTransparency setting from saved variables
local function getUiTransparency(self)
    return self.db.profile.uiTransparency
end

-- Retrieve the clockTime setting from saved variables
local function getClockTime(self)
    return self.db.profile.clockTime
end

-- Retrieve the status of the minimap visibility from saved variables
local function getMinimapEnabled(self)
    return not self.db.profile.minimap.hide
end

-- Helper to toggle the display of the minimap icon
local function toggleMinimapIcon(self)
    if not getMinimapEnabled(self) then
        GBCR.Libs.LibDBIcon:Hide(addonName)
    else
        GBCR.Libs.LibDBIcon:Show(addonName)
    end
end

-- Access the options saved variables
local function getOptionsDB(self)
    return self.db
end

-- Helper to retrieve guild ranks for guild bank fulfillment rule configuration
local function getRankArgs()
    local args = {}
    local MAX_RANKS = 10 -- TODO

    for i = 1, MAX_RANKS do
        local rankIndex = i
        args["rank_" .. rankIndex] = {
            type = "toggle",
            order = rankIndex,
            name = function()
                local n = GuildControlGetNumRanks()
                if rankIndex > n then
                    return ""
                end

                return GuildControlGetRankName(rankIndex) or ("Rank " .. rankIndex)
            end,
            hidden = function()
                return rankIndex > GuildControlGetNumRanks()
            end,
            get = function()
                local rf = GBCR.db.char.bank.rankFulfillment or {}

                return next(rf) == nil or rf[rankIndex] == true
            end,
            set = function(_, v)
                GBCR.db.char.bank.rankFulfillment = GBCR.db.char.bank.rankFulfillment or {}
                GBCR.db.char.bank.rankFulfillment[rankIndex] = v
            end
        }
    end

    return args
end

-- Initialize configuration defaults and configuration options specifically for guild bank alts
local function initGuildBankAltOptions()
    local isBankAlt = GBCR.Guild.weAreGuildBankAlt and true or false
    local isOfficer = GBCR.Guild.weCanEditOfficerNotes and true or false
    if Options.lastBankAltState == isBankAlt and Options.lastOfficerState == isOfficer then
        return
    end

    Options.lastBankAltState = isBankAlt
    Options.lastOfficerState = isOfficer

    GBCR.Libs.AceConfigRegistry:NotifyChange(addonName)
    if isBankAlt and not GBCR.Guild.isGuildRosterRebuilding then
        GBCR.Protocol.SendRosterIfAuthority()
    end
end

-- Initialize configuration defaults and configuration options
local function init(self)
    self.db = GBCR.db

    local values = {}
    local sorting = {}
    local position = 1

    for _, info in pairs(logLevels) do
        values[info.level] = info.description
        sorting[position] = info.level
        position = position + 1
    end
    table_sort(sorting, function(a, b)
        return a > b
    end)

    local bankArgs = {
        settingsHeader = {
            order = 1,
            type = "description",
            fontSize = "medium",
            name = "Configure inventory tracking and donation handling for this guild bank character"
        },
        inventoryTracking = {
            order = 2,
            type = "toggle",
            width = "full",
            name = function()
                return "Enable inventory tracking for " .. GBCR.Guild:GetNormalizedPlayerName()
            end,
            desc = "Enables inventory (bank, bags, and mailbox) scanning and sharing for this player",
            set = function(_, v)
                self.db.char.bank.inventoryTracking = v
                if v then
                    GBCR.Protocol.SendRosterIfAuthority()
                end
            end,
            get = function()
                return self:GetInventoryTrackingEnabled()
            end
        },
        donationsTracking = {
            order = 3,
            type = "toggle",
            width = "full",
            name = "Enable donation tracking",
            desc = "Tracks and shares donations sent to you via the mailbox",
            set = function(_, v)
                self.db.char.bank.donationsTracking = v
            end,
            get = function()
                return self:GetDonationsTrackingEnabled()
            end
        },
        reportReceivedDonations = {
            order = 4,
            type = "toggle",
            width = "full",
            name = "Report received donations",
            desc = "Display a message when donations are processed from mail",
            set = function(_, v)
                self.db.char.bank.reportReceivedDonations = v
            end,
            get = function()
                return self:GetDonationReportingEnabled()
            end
        },
        resetHeader = {order = 5, type = "header", name = "Reset this character's data"},
        resetDescription = {
            order = 6,
            type = "description",
            fontSize = "medium",
            name = "Clears locally stored inventory data for this guild bank character"
        },
        resetAlt = {
            order = 7,
            type = "execute",
            name = "Reset data",
            desc = "Clears locally stored inventory data for this guild bank character",
            func = function()
                local guildName = GBCR.Guild:GetGuildInfo()
                if guildName then
                    GBCR.Database:ResetGuildBankAlt(guildName, GBCR.Guild:GetNormalizedPlayerName())
                end
            end
        },
        ranksHeader = {order = 9, type = "header", name = "Request fulfillment by guild rank"},
        ranksDesc = {
            order = 10,
            type = "description",
            name = "Enable which guild ranks are eligible for request fulfillment from this guild bank",
            fontSize = "medium"
        }
    }

    for key, entry in pairs(getRankArgs()) do
        entry.order = 11 + tonumber(key:match("%d+") or 0)
        bankArgs[key] = entry
    end

    local debugCategoryDefs = {
        {key = "CHUNK", order = 10, name = "CHUNK: data synchronization operations specific to chunk sending"},
        {key = "COMMS", order = 11, name = string_format("COMMS: all addon communication traffic")},
        {key = "DATABASE", order = 12, name = "DATABASE: database operations"},
        {key = "EVENTS", order = 13, name = "EVENTS: event handling"},
        {key = "LEDGER", order = 14, name = "LEDGER: buy, sell, trade, destroy, and mail logging"},
        {key = "INVENTORY", order = 15, name = "INVENTORY: bank, bag, and mail scanning"},
        {key = "ITEM", order = 16, name = string_format("ITEM: item information caching")},
        {key = "PROTOCOL", order = 17, name = "PROTOCOL: protocol version negotiation and debouncing"},
        {key = "ROSTER", order = 18, name = "ROSTER: guild roster and status tracking"},
        {key = "SEARCH", order = 19, name = string_format("SEARCH: search operations")},
        {key = "SYNC", order = 20, name = "SYNC: data synchronization operations"},
        {key = "UI", order = 21, name = "UI: user interface operations"},
        {key = "WHISPER", order = 22, name = "WHISPER: player to player addon communication"}
    }

    local debugArgs = {
        debug = {
            order = 1,
            type = "description",
            fontSize = "medium",
            name = "Enable specific debug categories when log level is set to debug"
        },
        spacer = {order = 30, type = "description", name = " "},
        enableAll = {
            order = 31,
            type = "execute",
            name = "Enable all categories",
            func = function()
                self:EnableAllCategories()
                GBCR.Output:Response("All debug categories enabled.")
            end
        },
        disableAll = {
            order = 32,
            type = "execute",
            name = "Disable all categories",
            func = function()
                self:DisableAllCategories()
                GBCR.Output:Response("All debug categories disabled.")
            end
        },
        spacer2 = {order = 40, type = "description", name = " "}
    }
    for _, def in ipairs(debugCategoryDefs) do
        local key = def.key
        debugArgs[string_lower(key)] = {
            order = def.order,
            type = "toggle",
            width = "full",
            name = def.name,
            set = function(_, v)
                self:SetCategoryEnabled(key, v)
            end,
            get = function()
                return self:IsCategoryEnabled(key)
            end
        }
    end

    local options = {
        type = "group",
        name = function()
            return GBCR.Core.addonHeader
        end,
        childGroups = "tree",
        args = {
            verbosity = {
                order = 1,
                type = "group",
                name = "Verbosity",
                args = {
                    verbosity = {
                        order = 1,
                        name = "Controls which messages appear in chat",
                        type = "select",
                        style = "radio",
                        width = "full",
                        values = values,
                        sorting = sorting,
                        set = function(_, v)
                            self:SetLogLevel(v)
                        end,
                        get = function()
                            return self:GetLogLevel()
                        end
                    }
                }
            },
            interface = {
                order = 2,
                type = "group",
                name = "Interface",
                args = {
                    minimap = {
                        order = 1,
                        type = "toggle",
                        width = "full",
                        name = "Show minimap button",
                        desc = "Toggles visibility of the minimap button",
                        set = function(_, v)
                            self.db.profile.minimap.hide = not v
                            toggleMinimapIcon()
                        end,
                        get = function()
                            return self:GetMinimapEnabled()
                        end
                    },
                    combat = {
                        order = 2,
                        type = "toggle",
                        width = "full",
                        name = "Hide during combat",
                        desc = "Hides the window when entering combat",
                        set = function(_, v)
                            self.db.profile.combat.hide = v
                        end,
                        get = function()
                            return self:GetCombatHide()
                        end
                    },
                    transparency = {
                        order = 3,
                        type = "toggle",
                        width = "full",
                        name = "Make this user interface slightly transparent",
                        set = function(_, v)
                            self.db.profile.uiTransparency = v
                            GBCR.UI:UpdateTransparency()
                        end,
                        get = function()
                            return self:GetUiTransparency()
                        end
                    },
                    clockDisplay = {
                        order = 4,
                        type = "select",
                        width = "full",
                        name = "Clock display",
                        desc = "Controls whether the top-bar clock shows realm (server) time or your local system time",
                        values = {["realm"] = "Realm time", ["local"] = "Local time"},
                        set = function(_, v)
                            self.db.profile.clockTime = v
                            if GBCR.UI.clockLabel then
                                local useLocal = (v == "local")
                                local timeStr
                                if useLocal then
                                    timeStr = date("%H:%M")
                                else
                                    local h, m = GetGameTime()
                                    timeStr = string.format("%02d:%02d", h, m)
                                end
                                GBCR.UI.clockLabel:SetText(Globals.ColorizeText(Constants.COLORS.WHITE, timeStr))
                            end
                        end,
                        get = function()
                            return self:GetClockTime()
                        end
                    }
                }
            },
            database = {
                order = 3,
                type = "group",
                name = "Database",
                args = {
                    resetDescription = {
                        order = 1,
                        type = "description",
                        fontSize = "medium",
                        name = "Clears locally stored data for all guild banks for your current guild"
                    },
                    reset = {
                        order = 2,
                        name = "Reset guild database",
                        desc = "Clears locally stored data for all guild banks for your current guild",
                        type = "execute",
                        func = function()
                            GBCR.Guild:ResetGuild()
                        end
                    }
                }
            },
            debug = {
                order = 4,
                type = "group",
                name = "Debug",
                disabled = function()
                    return not self:IsDebugEnabled()
                end,
                args = debugArgs
            },
            bank = {
                type = "group",
                name = "Bank configuration",
                order = 5,
                hidden = function()
                    return not GBCR.Guild.weAreGuildBankAlt
                end,
                args = bankArgs
            },
            officer = {
                type = "group",
                name = "Officer configuration",
                order = 6,
                hidden = function()
                    return not (GBCR.Guild.weCanEditOfficerNotes == true)
                end,
                args = {
                    desc = {
                        order = 1,
                        type = "description",
                        fontSize = "medium",
                        name = "Define guild bank alts manually, independent of guild notes.\nOnly officers may edit this list. Adding or removing a character immediately saves and broadcasts the updated roster.\n"
                    },
                    addAlt = {
                        order = 2,
                        type = "input",
                        name = "Add character (Name or Name-Realm)",
                        width = "double",
                        set = function(info, val)
                            if not val or val == "" then
                                return
                            end
                            local trimmed = string_match(val, "^%s*(.-)%s*$") or ""
                            if trimmed == "" then
                                return
                            end

                            local lower = string_lower(trimmed)
                            local inPlayer, inRealm = string_match(lower, "^(.-)%-(.+)$")
                            local foundName

                            for cachedName in pairs(GBCR.Guild.cachedGuildMembers) do
                                if string_lower(cachedName) == lower then
                                    foundName = cachedName

                                    break
                                end
                            end

                            if not foundName and not inRealm then
                                local single, ambiguous = nil, false
                                for cachedName in pairs(GBCR.Guild.cachedGuildMembers) do
                                    local cp = string_match(string_lower(cachedName), "^(.-)%-")
                                    if cp == lower then
                                        if single then
                                            ambiguous = true

                                            break
                                        end
                                        single = cachedName
                                    end
                                end
                                if not ambiguous then
                                    foundName = single
                                end
                            end

                            if not foundName and inRealm then
                                for cachedName in pairs(GBCR.Guild.cachedGuildMembers) do
                                    local cp, cr = string_match(string_lower(cachedName), "^(.-)%-(.+)$")
                                    if cp == inPlayer and cr == inRealm then
                                        foundName = cachedName

                                        break
                                    end
                                end
                            end

                            if not foundName then
                                GBCR.Output:Response("%s is not a current guild member.", trimmed)

                                return
                            end

                            local sv = GBCR.Database.savedVariables
                            if not sv or not sv.roster then
                                return
                            end

                            sv.roster.manualAlts = sv.roster.manualAlts or {}
                            for _, existing in ipairs(sv.roster.manualAlts) do
                                if existing == foundName then
                                    GBCR.Output:Response("%s is already in the list.", foundName)

                                    return
                                end
                            end
                            sv.roster.manualAlts[#sv.roster.manualAlts + 1] = foundName
                            GBCR.Guild.cachedGuildBankAlts[foundName] = true
                            GBCR.Guild.guildRosterRefreshNeeded = true

                            local wasThrottled = GBCR.Guild.timerRebuildGuildRosterInfo ~= nil
                            GBCR.Guild:RebuildGuildRosterInfo()

                            if wasThrottled then
                                GBCR.Output:Response("Added %s. Roster update queued (broadcasting shortly).", foundName)
                            else
                                GBCR.Output:Response("Added %s. Rebuilding roster and broadcasting...", foundName)
                            end

                            GBCR.Libs.AceConfigRegistry:NotifyChange(addonName)
                        end,
                        get = function()
                            return ""
                        end
                    },
                    manageAlts = {
                        order = 3,
                        type = "multiselect",
                        name = "Current manually defined guild banks (uncheck to remove immediately)",
                        width = "full",
                        values = function()
                            local out = {}
                            local sv = GBCR.Database.savedVariables
                            if sv and sv.roster and sv.roster.manualAlts then
                                for _, name in ipairs(sv.roster.manualAlts) do
                                    out[name] = name
                                end
                            end

                            return out
                        end,
                        get = function(info, key)
                            return true
                        end,
                        set = function(info, key, state)
                            if state then
                                return
                            end

                            local sv = GBCR.Database.savedVariables
                            if not sv or not sv.roster or not sv.roster.manualAlts then
                                return
                            end

                            for i = #sv.roster.manualAlts, 1, -1 do
                                if sv.roster.manualAlts[i] == key then
                                    table_remove(sv.roster.manualAlts, i)
                                    GBCR.Output:Response("Removed %s. Rebuilding roster and broadcasting...", key)

                                    break
                                end
                            end

                            GBCR.Guild.cachedGuildBankAlts[key] = nil
                            GBCR.Guild:RebuildGuildRosterInfo()
                            GBCR.Libs.AceConfigRegistry:NotifyChange(addonName)
                        end
                    }
                }
            },
            profiles = GBCR.Libs.AceDBOptions:GetOptionsTable(self.db)
        }
    }

    GBCR.Libs.AceConfig:RegisterOptionsTable(addonName, options)

    self.db.RegisterCallback(GBCR, "OnProfileChanged", function(_, _, newProfileName)
        GBCR.Output:Response("Switched to profile %s.", Globals.ColorizeText(colorGold, newProfileName))
    end)
    self.db.RegisterCallback(GBCR, "OnProfileCopied", function(_, _, sourceProfileName)
        GBCR.Output:Response("Copied profile from %s.", Globals.ColorizeText(colorGold, sourceProfileName))
    end)
    self.db.RegisterCallback(GBCR, "OnProfileReset", function()
        GBCR.Output:Response("Profile reset to defaults.")
    end)
    self.db.RegisterCallback(GBCR, "OnProfileDeleted", function(_, _, deletedProfile)
        GBCR.Output:Response("Profile %s deleted.", Globals.ColorizeText(colorGold, deletedProfile))
    end)

    local panel = CreateFrame("Frame", "GBCR_Options")
    self.optionsPanel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -15)
    title:SetText(GBCR.Core.addonHeader)
    self.optionsPanel.title = title

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -0.5, -12.5)
    desc:SetText(string_format("Settings are managed using %s", Globals.ColorizeText(colorGreen, "/bank config")))
    desc:SetFontObject(GameFontHighlight)
    self.optionsPanel.desc = desc

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(160, 26)
    button:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    button:SetText("Open configuration")
    button:SetScript("OnClick", function()
        GBCR.UI:ToggleTab("configuration")
    end)
    self.optionsPanel.button = button

    local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    Settings.RegisterAddOnCategory(category)
end

-- Export functions for other modules
Options.GetLogLevel = getLogLevel
Options.IsDebugEnabled = isDebugEnabled
Options.SetLogLevel = setLogLevel
Options.IsCategoryEnabled = isCategoryEnabled
Options.SetCategoryEnabled = setCategoryEnabled
Options.EnableAllCategories = enableAllCategories
Options.DisableAllCategories = disableAllCategories
Options.GetInventoryTrackingEnabled = getInventoryTrackingEnabled
Options.GetDonationsTrackingEnabled = getDonationsTrackingEnabled
Options.GetDonationReportingEnabled = getDonationReportingEnabled
Options.GetRankFulfillment = getRankFulfillment
Options.GetCombatHide = getCombatHide
Options.GetUiTransparency = getUiTransparency
Options.GetClockTime = getClockTime
Options.GetSortMode = getSortMode
Options.SetSortMode = setSortMode
Options.GetMinimapEnabled = getMinimapEnabled
Options.GetOptionsDB = getOptionsDB
Options.InitGuildBankAltOptions = initGuildBankAltOptions
Options.Init = init
