local addonName, GBCR = ...

GBCR.Core = {}
local Core = GBCR.Core

GBCR.Addon = GBCR.Libs.AceAddon:NewAddon(addonName, "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

local Globals = GBCR.Globals
local tonumber = Globals.tonumber

local GetAddOnMetadata = Globals.GetAddOnMetadata

local Constants = GBCR.Constants
local logLevels = Constants.LOG_LEVEL

-- Make the addon metadata universally available
local function loadMetadata(self)
    local addonTitle = GetAddOnMetadata(addonName, "Title")
    local addonVersion = GetAddOnMetadata(addonName, "Version") or "0.0.0"
    local major, minor, patch = string.match(addonVersion, "(%d+)%.(%d+)%.(%d+)")
    local addonVersionNumber = (tonumber(major) * 10000) + (tonumber(minor) * 100) + (tonumber(patch) or 0)
    local addonIsOutdated = GBCR.Protocol.isAddonOutdated and Globals:Colorize(Constants.COLORS.GOLD, " (a newer version is available)") or ""
    local addonHeader = addonTitle .. " v" .. addonVersion .. addonIsOutdated

    self.addonTitle = addonTitle
	self.addonHeader = addonHeader
	self.addonVersion = addonVersion
	self.addonVersionNumber = addonVersionNumber

    if GBCR.UI.Inventory.window then
        GBCR.UI.Inventory.window:SetTitle(addonHeader)
    end
end

-- Called when the addon is loaded
function GBCR.Addon:OnInitialize()
    loadMetadata(Core)

    local defaults = {
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
				inventory = {
					width = 700,
					height = 500,
				},
				debug = {
					width = 800,
					height = 400,
				}
            },
			logLevel = logLevels.INFO.level,
			debugCategories = {
				ROSTER = false,
				COMMS = false,
				SYNC = false,
				CHUNK = false,
				DONATIONS = false,
				WHISPER = false,
				-- REQUESTS = false,
				UI = false,
				PROTOCOL = false,
				DATABASE = false,
				EVENTS = false,
				INVENTORY = false,
				-- MAIL = false,
				ITEM = false,
				-- FULFILL = false,
				SEARCH = false,
				-- QUERIES = false,
				REPLIES = false,
			},
			sortMode = "default"
		},
		global = {
			guilds = {}
		}
	}
    GBCR.db = GBCR.Libs.AceDB:New("GBCR_DB_ALPHA", defaults, true)

    GBCR.Database:Init()
    GBCR.Options:Init()
    GBCR.UI.Debug:Init()
    GBCR.Inventory:Init()
    GBCR.Guild:Init()
    GBCR.Chat:Init()
    GBCR.Protocol:Init()
    GBCR.UI:Init()
    GBCR.Donations:Init()
    GBCR.Search:Init()

    local framePositionsDebug = GBCR.db.profile.framePositions.debug
    if not framePositionsDebug.left or not framePositionsDebug.top then
        GBCR.UI:RestoreUI()
    end
end

-- Called when the addon is enabled
function GBCR.Addon:OnEnable()
    GBCR.Events:RegisterEvents()
end

-- Called when the addon is disabled
function GBCR.Addon:OnDisable()
    GBCR.Events:UnregisterEvents()
    GBCR.Protocol:CancelAllDebounceTimers()
end

-- Export functions for other modules
Core.LoadMetadata = loadMetadata