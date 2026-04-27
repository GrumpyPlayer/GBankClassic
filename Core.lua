local addonName, GBCR = ...

GBCR.Core = {}
local Core = GBCR.Core

GBCR.Addon = GBCR.Libs.AceAddon:NewAddon(addonName, "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0")

local Globals = GBCR.Globals
local string_match = Globals.string_match
local tonumber = Globals.tonumber

local GetAddOnMetadata = Globals.GetAddOnMetadata

local Constants = GBCR.Constants
local logLevels = Constants.LOG_LEVEL

-- _G[addonName] = GBCR

-- Make the addon metadata universally available
local function loadMetadata(self)
    local addonTitle = GetAddOnMetadata(addonName, "Title")
    local addonVersion = GetAddOnMetadata(addonName, "Version") or "0.0.0"
    local major, minor, patch = string_match(addonVersion, "(%d+)%.(%d+)%.(%d+)")
    local addonVersionNumber = (tonumber(major) * 10000) + (tonumber(minor) * 100) + (tonumber(patch) or 0)
    local addonIsOutdated = GBCR.Protocol.isAddonOutdated and
                                Globals.ColorizeText(Constants.COLORS.GOLD, " (a newer version is available)") or ""
    local addonHeader = addonTitle .. " v" .. addonVersion .. addonIsOutdated

    self.addonTitle = addonTitle
    self.addonHeader = addonHeader
    self.addonVersion = addonVersion
    self.addonVersionNumber = addonVersionNumber

    if GBCR.UI.window then
        GBCR.UI.window:SetTitle(addonHeader)
    end
end

-- Called when the addon is loaded
function GBCR.Addon:OnInitialize()
    loadMetadata(Core)

    local defaults = {
        char = {bank = {inventoryTracking = true, donationsTracking = true, reportReceivedDonations = true, rankFulfillment = {}}},
        profile = {
            combat = {hide = true},
            minimap = {hide = false},
            uiTransparency = false,
            clockTime = "realm",
            framePositions = {
                inventory = {width = 850, height = 485},
                debug = {width = 800, height = 400},
                panes = {cartLeft = 550, previewRight = 284}
            },
            logLevel = logLevels.INFO.level,
            debugCategories = {
                COMMS = false,
                WHISPER = false,
                PROTOCOL = false,
                SYNC = false,
                CHUNK = false,
                DATABASE = false,
                UI = false,
                ITEM = false,
                SEARCH = false,
                EVENTS = false,
                INVENTORY = false,
                ROSTER = false,
                LEDGER = false
            },
            sortMode = "default"
        },
        global = {guilds = {}}
    }
    GBCR.db = GBCR.Libs.AceDB:New("GBCR_DB_V30010", defaults, true)

    GBCR.Database:Init()
    GBCR.Options:Init()
    GBCR.UI.Debug:Init()
    GBCR.Inventory:Init()
    GBCR.Guild:Init()
    GBCR.Chat.Init()
    GBCR.Protocol:Init()
    GBCR.UI:Init()
    GBCR.Ledger:Init()

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
    GBCR.UI:StopNetworkTicker()

    GBCR.Protocol.gossipLoopRunning = false
    GBCR.Protocol.isAcceptingIncoming = false
    GBCR.Protocol.isProcessingQueue = false

    local function cancelTimer(holder, field)
        if holder[field] then
            holder[field]:Cancel();
            holder[field] = nil
        end
    end

    cancelTimer(GBCR.Protocol, "timerLoginHashBroadcast")
    cancelTimer(GBCR.Protocol, "printVersionsTimer")
    cancelTimer(GBCR.Protocol, "itemLoadWatchdog")
    cancelTimer(GBCR.Guild, "timerRebuildGuildRosterInfo")
    cancelTimer(GBCR.Events, "timerRefreshOnlineMembersCache")
    cancelTimer(GBCR.Events, "timerBagUpdateDelayedScanInventory")
    cancelTimer(GBCR.Events, "timerGetItemInfoReceivedScanInventory")
    cancelTimer(GBCR.Ledger, "timerLedgerUpdateBroadcast")
    cancelTimer(GBCR.UI, "clockTicker")
    cancelTimer(GBCR.UI, "syncPulseTicker")
    cancelTimer(GBCR.UI, "searchTimer")
    cancelTimer(GBCR.UI, "resizeTimer")
end

-- Export functions for other modules
Core.LoadMetadata = loadMetadata
