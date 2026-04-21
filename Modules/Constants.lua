local addonName, GBCR = ...

GBCR.Constants = {}
local Constants = GBCR.Constants

local Globals = GBCR.Globals
local ipairs = Globals.ipairs
local pairs = Globals.pairs
local string_format = Globals.string_format
local string_gsub = Globals.string_gsub
local tostring = Globals.tostring

local Enum = Globals.Enum
local GetServerTime = Globals.GetServerTime

-- Version aware import string prefix (Discord request list)
Constants.IMPORT_PREFIX = "GBCR3:"

-- Limits
Constants.LIMITS = {
    COMPRESSION_LEVEL = 3, -- LibDeflate compression level (same payload size for data and fingerprint when using 6-9); changed to 3 for ~2x faster at 5% larger output
    MAX_CONCURRENT_ASYNC = 3, -- Limit concurrent async operations for item link reconstruction
    MAX_CONCURRENT_OUTBOUND = 3, -- Limit concurrent outbound data share whispers
    BATCH_SIZE_GETITEMINFO = 50, -- How many items to cache per frame
    MAX_BUFFER_SIZE = 4096, -- Maximum amount of messages for the /chat debuglog
    DISCORD_MAX = 1900 -- Maximum character length for Discord message export
}

-- Timer intervals (in seconds)
Constants.TIMER_INTERVALS = {
    GOSSIP_CYCLE = 900, -- 15 minute: background pulse hash broadcast
    FINGERPRINT_BROADCAST = 180, -- 3 minutes: lightweight fingerprint broadcast
    FINGERPRINT_COOLDOWN = 30, -- 30 seconds: cooldown between fingerprint broadcasts
    MANUAL_SHARE_COOLDOWN = 60, -- 1 minute: cooldown between allowed /bank share commands
    MANUAL_SYNC_COOLDOWN = 30, -- 30 seconds: cooldown between allow /bank sync commands
    DEBOUNCE_HARD_DEADLINE = 15, -- Guarantee processing within 15s of the first queued entry
    DEBUG_LOG_REFRESH = 2.5, -- Runs 2.5s after the first event (fixed delay)
    BUILD_DONATION_CACHE = 2.5, -- Runs 2.5s after the last event (trailing debouce, stays quiet until activity is done)
    GRM_WAIT = 2, -- Wait 2 seconds for GRM's GuildRoster() call to complete
    REBUILD_ROSTER = 30, -- Only rebuild the full roster once every 30 seconds
    BAG_UPDATE_QUIET_TIME = 5, -- 5 seconds: scan the updated inventory after 5 seconds without BAG_UPDATE_DELAYED events
    LEDGER_UPDATE_QUIET_TIME = 5, -- 5 seconds: update version + announce after 5 seconds without ledger appends
    SEARCH_DEBOUNCE = 0.2, -- Wait until the user stops typing for a few seconds before firing the expensive search
    UI_REFRESH_DEBOUNCE = 0.5, -- QueueUIRefresh trailing debounce
    UI_REFRESH_FORCE_AGE = 3.0, -- force a draw after this many idle seconds
    ITEM_INFO_RESCAN = 2.0, -- rescan delay after GET_ITEM_INFO_RECEIVED
    ASYNC_COMPRESS = 0, -- compress next frame
    NEW_SESSION_WARN_DELAY = 5, -- empty-inventory warning on login
    ONLINE_CACHE_REFRESH = 2.0, -- secondary refresh in GUILD_ROSTER_UPDATE
    FINGERPRINT_RESPONSE_BATCH = 0.5 -- batch fp-query replies before sending
}

-- Jitter ranges (in seconds) used to prevent request storms
Constants.JITTER = {
    QUERY_MIN = 2, -- data-query dispatch minimum
    QUERY_MAX = 15, -- data-query dispatch maximum
    RETRY_MIN = 15, -- retry after busy signal minimum
    RETRY_MAX = 45, -- retry after busy signal maximum
    ANNOUNCE_MIN = 5, -- gbc-announce data-request minimum
    ANNOUNCE_MAX = 20,
    HASH_MISMATCH_MIN = 2, -- fp-query dispatch minimum
    HASH_MISMATCH_MAX = 10,
    LOGIN_MIN = 15, -- login-storm broadcast minimum
    LOGIN_MAX = 60,
    TIMEOUT_RETRY_MIN = 60, -- post-timeout retry minimum
    TIMEOUT_RETRY_MAX = 120
}

-- One place to define and maintain non-class specific colors
Constants.COLORS = {
    BLUE = "ff80bfff", -- Debug messages about sharing, fallback for class-color
    GREEN = "ff33ff99", -- Help text color codes header
    YELLOW = "ffffff00", -- Debug messages about queries
    GOLD = "ffe6cc80", -- Help text color codes commands, AddOn is outdated message
    ORANGE = "ffffa600", -- Warnings
    RED = "ffff0000", -- Failures
    GRAY = "ff808080", -- Debug category prefix in debug messages
    WHITE = "ffffffff" -- Temporary link
}

-- Commands are displayed in help in the order they appear here
local commandRegistry = {
    -- Command registry: name, usage, help (nil to hide from help output), expert, handler

    -- Basic commands
    {
        name = "config",
        help = "open configuration options",
        handler = function()
            GBCR.UI.Inventory:ToggleTab("configuration")
        end
    },
    {
        name = "help",
        help = "this message",
        handler = function()
            GBCR.Chat.ShowHelp()
        end
    },
    {
        name = "reset",
        help = "reset your own " .. addonName .. " database",
        handler = function()
            GBCR.Guild:ResetGuild()
        end
    },
    {
        name = "restoreui",
        help = "restore the user interface window size and position back to the default",
        expert = true,
        handler = function()
            GBCR.UI:RestoreUI()
        end
    },
    {
        name = "share",
        help = "share your guild bank data with online members",
        handler = function()
            local now = GetServerTime()
            local last = GBCR.Protocol.lastManualShare or 0
            local cooldown = GBCR.Constants.TIMER_INTERVALS.MANUAL_SHARE_COOLDOWN
            if now - last < cooldown then
                GBCR.Output:Response("Please wait %d seconds before sharing again.", cooldown - (now - last))

                return
            end
            GBCR.Protocol.lastManualShare = now
            GBCR.Protocol:SendFingerprint()
            GBCR.Output:Response(
                "Notifying online guild members that your bank data is available. Anyone who is missing it will request it automatically.")
        end
    },
    {
        name = "sync",
        help = "request missing guild bank data from online members",
        handler = function()
            local now = GetServerTime()
            local last = GBCR.Protocol.lastSync or 0
            local cooldown = GBCR.Constants.TIMER_INTERVALS.MANUAL_SYNC_COOLDOWN
            if now - last < cooldown then
                GBCR.Output:Response("Please wait %d seconds before syncing again.", cooldown - (now - last))

                return
            end
            GBCR.Protocol:PerformSync()
            GBCR.Output:Response("Checking for missing guild bank data from online members...")
        end
    },
    {
        name = "version",
        help = "display the " .. addonName .. " version",
        handler = function()
            GBCR.Output:Response("You are running " .. addonName .. ", version: %s.",
                                 Globals.ColorizeText(Constants.COLORS.GOLD, GBCR.Core.addonVersion))
        end
    },

    -- Expert commands (alphabetically sorted)
    {
        name = "debounce",
        help = "show debounced message queue status (debug)",
        expert = true,
        handler = function(arg1)
            if arg1 == "off" then
                GBCR.Protocol.debounceConfig.enabled = false
                GBCR.Output:Response("Debouncing disabled.")
            elseif arg1 == "on" then
                GBCR.Protocol.debounceConfig.enabled = true
                GBCR.Output:Response("Debouncing enabled.")
            else
                local queueMultipleAltCount = Globals.Count(GBCR.Protocol.debounceQueues.multipleAlts or {})
                local queueSingularAltCount = Globals.Count(GBCR.Protocol.debounceQueues.singularAlt or {})

                GBCR.Output:Response("Debounce status: %s.", Globals.ColorizeText(Constants.COLORS.GOLD, GBCR.Protocol
                                                                                      .debounceConfig.enabled and "enabled" or
                                                                                      "disabled"))
                GBCR.Output:Response("Queued protocol messages with data about one guild bank alt: %d.",
                                     Globals.ColorizeText(Constants.COLORS.GOLD, queueSingularAltCount))
                GBCR.Output:Response("Queued protocol messages with data about multiple guild bank alts: %d.",
                                     Globals.ColorizeText(Constants.COLORS.GOLD, queueMultipleAltCount))

                if arg1 == "detail" then
                    if queueMultipleAltCount > 0 then
                        GBCR.Output:Response("Messages with data about multiple guild bank alts:")
                        for altNorm, best in pairs(GBCR.Protocol.debounceQueues.multipleAlts) do
                            GBCR.Output:Response("  %s: sender=%s, version=%s", altNorm, best.sender, tostring(best.version))
                        end
                    end
                    if queueSingularAltCount > 0 then
                        GBCR.Output:Response("Messages with data about one guild bank alt:")
                        for key, queued in pairs(GBCR.Protocol.debounceQueues.singularAlt) do
                            GBCR.Output:Response("  %s: sender=%s, version=%s", key, queued.sender, tostring(queued.version))
                        end
                    end
                end
            end
        end
    },
    {
        name = "debugclear",
        help = "clear the debug output",
        expert = true,
        handler = function()
            GBCR.UI:ClearDebugContent()
        end
    },
    {
        name = "debuglog",
        help = "toggle the display of a dedicated window for debug output",
        expert = true,
        handler = function()
            GBCR.UI.Debug:Toggle()
        end
    },
    {
        name = "hello",
        help = "display what guild bank data you know about and inform others",
        expert = true,
        handler = function()
            GBCR.Protocol:SendHello()
        end
    },
    {
        name = "roster",
        help = "if officer notes are used to define guild bank alts, use this command to share the roster of guild bank alts with online guild members",
        expert = true,
        handler = function()
            GBCR.Protocol.SendRosterIfAuthority()
        end
    },
    {
        name = "versions",
        help = "show addon versions of online guild members",
        expert = true,
        handler = function()
            GBCR.Chat.PrintVersions()
        end
    },
    {
        name = "wipe",
        help = "reset your own " .. addonName .. " database",
        expert = true,
        handler = function()
            GBCR.Guild:ResetGuild()
        end
    },
    {
        name = "wipeall",
        help = "officer only: reset your own " .. addonName .. " database and that of all online guild members",
        expert = true,
        handler = function()
            GBCR.Output:Response("Requesting all online members to reset their guild bank database.")
            GBCR.Protocol.SendWipeAll()
        end
    },

    -- Hidden commands (no help text)
    {
        name = "conf", -- alternative to `/bank config`
        help = "open configuration options",
        handler = function()
            GBCR.UI.Inventory:ToggleTab("configuration")
        end
    },
    {
        name = "options", -- alternative to `/bank config`
        help = "open configuration options",
        handler = function()
            GBCR.UI.Inventory:ToggleTab("configuration")
        end
    },
    {
        name = "debug",
        handler = function()
            if GBCR.Options:IsDebugEnabled() then
                local restoreLevel = Constants.preDebugLogLevel and Constants.preDebugLogLevel or Constants.LOG_LEVEL.INFO.level

                Constants.preDebugLogLevel = nil
                GBCR.Options:SetLogLevel(restoreLevel)
                GBCR.Output:Response("Debug: off.")
                GBCR.UI.Debug:Close()
            else
                Constants.preDebugLogLevel = GBCR.Options:GetLogLevel()
                GBCR.Options:SetLogLevel(Constants.LOG_LEVEL.DEBUG.level)
                GBCR.Output:Response("Debug: on.")
            end
        end
    }
}
Constants.COMMAND_REGISTRY = commandRegistry
Constants.COMMAND_HANDLERS = {}
for _, cmd in ipairs(commandRegistry) do
    Constants.COMMAND_HANDLERS[cmd.name] = cmd.handler
end

-- Instructions as multiline strings for readability
Constants.HELP_INSTRUCTIONS = {
    {
        title = "Setting up a new guild bank:",
        text = string_format([[
1. Log in as the guild bank character (must be in a guild).
2. Add %s to your public or officer note, then wait a few seconds.
   The %s tab will appear automatically in %s. Open it to confirm tracking is enabled.
3. Open your bank, then open your mailbox, then close them both.
4. Your data is now recorded. It shares automatically within a couple of minutes.
   You will see %s in chat when it completes.
5. Ask a guild member to type %s to verify your items are visible.]], Globals.ColorizeText(Constants.COLORS.GOLD, "gbank"),
                             Globals.ColorizeText(Constants.COLORS.GOLD, "Bank Configuration"),
                             Globals.ColorizeText(Constants.COLORS.GOLD, "/bank config"),
                             Globals.ColorizeText(Constants.COLORS.GOLD, "Finished sending your latest data"),
                             Globals.ColorizeText(Constants.COLORS.GOLD, "/bank"))
    },
    {
        title = "Removing a guild bank:",
        text = string_format([[
    1. Remove %s from the character's guild note (requires officer access).
       Anyone who can view the guild roster will remove their data automatically within a few seconds.
    2. Ask a guild member to type %s to confirm the character is no longer listed.]],
                             Globals.ColorizeText(Constants.COLORS.GOLD, "gbank"),
                             Globals.ColorizeText(Constants.COLORS.GOLD, "/bank"))
    }

}

-- Communication prefix descriptions for debug logging (maximum of 16 characters)
-- Unsolicited sharing goes to guild when cheap, whisper when expensive, responses always go to the requester via whisper
Constants.COMM_PREFIX_DESCRIPTIONS = {
    ["gbc-hash"] = "(hash share)", -- snall, broadcast `addonVersion:stateHash` to the guild that represents all known alts + their version
    ["gbc-announce"] = "(announce)", -- small, roadcast our guild bank alt name to the guild that we just manually scanned our inventory, discovered an update, an updated our version
    ["gbc-fp-share"] = "(fingerprint share)", -- medium (7 chunks), broadcast a periodic fingerprint of our data; or targeted whisper in response to query
    ["gbc-fp-query"] = "(fingerprint query)", -- small, argeted whisper to query fingerprint data
    ["gbc-data-share"] = "(data share)", -- large (35 chunks), targeted whisper to share guild bank alt data
    ["gbc-data-query"] = "(data query)", -- small, targeted whsiper to request guild bank alt data; fallback to guild broadcast
    ["gbc-roster-share"] = "(roster share)", -- small, targeted whisper to share roster data; fallback to guild broadcast
    ["gbc-roster-query"] = "(roster query)", -- small, targeted whisper to request roster data; fallback to guild broadcast
    ["gbc-h"] = "(hello)",
    ["gbc-hr"] = "(hello reply)",
    ["gbc-w"] = "(wipe)",
    ["gbc-wr"] = "(wipe reply)"
}

-- Communication state
Constants.STATE = {
    IDLE = 1, -- Data is current, doing nothing
    DISCOVERING = 2, -- A hash mismatch occurred, we have whispered someone for their fingerprint (7 chunks for 100 alts)
    OUTDATED = 3, -- The fingerprint parsing revealed our guild bank alt data is old, we jitter the query for guild bank alt data over a 2 to 15 seconds window to prevent request storms
    REQUESTING = 4, -- We whispered a specific player for the alt data (35 chunks for 1424 items) and started a 10-second timeout, we timeout our request after 30-second and then revert back to outdated; if we receive a busy signal, we jitter the retry over a 15 to 45 seconds so the sender has time to clear their outbound queue
    RECEIVING = 5, -- AceComm has begun firing chunk callbacks
    UPDATED = 6 -- Data fully assembled, awaiting asynchronous parsing
}

-- For processing incoming data
Constants.ADOPTION_STATUS = {
    ADOPTED = "adopted",
    STALE = "stale",
    INVALID = "invalid",
    UNAUTHORIZED = "unauthorized",
    IGNORED = "ignored"
}

-- For logging operations in the ledger
Constants.LEDGER = {MAX_ENTRIES = 200, PRUNE_TO = 150, SYNC_WINDOW = 50}
Constants.LEDGER_OPERATION = {
    IN = 0x01,
    OUT = 0x02,
    MAIL = 0x04,
    TRADE = 0x08,
    VENDOR = 0x10,
    LOOT = 0x20,
    COD = 0x40,
    DESTROY = 0x80,
    AH = 0x200,
    AH_BUYER = 0x400
}
Constants.LEDGER_OPERATION.MAIL_IN = 0x01 + 0x04 -- 0x05
Constants.LEDGER_OPERATION.MAIL_OUT = 0x02 + 0x04 -- 0x06
Constants.LEDGER_OPERATION.MAIL_COD_IN = 0x01 + 0x04 + 0x40 -- 0x45
Constants.LEDGER_OPERATION.TRADE_IN = 0x01 + 0x08 -- 0x09
Constants.LEDGER_OPERATION.TRADE_OUT = 0x02 + 0x08 -- 0x0A
Constants.LEDGER_OPERATION.VENDOR_SELL = 0x01 + 0x10 -- 0x11 (money in, item out)
Constants.LEDGER_OPERATION.VENDOR_BUY = 0x02 + 0x10 -- 0x12 (money out, item in)
Constants.LEDGER_OPERATION.LOOT_IN = 0x01 + 0x20 -- 0x21 (not currently used)
Constants.LEDGER_OPERATION.DESTROY_OUT = 0x02 + 0x80 -- 0x82
Constants.LEDGER_OPERATION.AH_SOLD = 0x001 + 0x004 + 0x200 -- 0x205
Constants.LEDGER_OPERATION.AH_CANCELLED = 0x002 + 0x004 + 0x200 -- 0x206
Constants.LEDGER_OPERATION.AH_OUTBID = 0x001 + 0x004 + 0x200 + 0x400 -- 0x605
Constants.LEDGER_OPERATION.AH_WON = 0x002 + 0x004 + 0x200 + 0x400 -- 0x606
Constants.LEDGER_MONEY_ITEM = 0

-- Debug categories for filtering
Constants.DEBUG_CATEGORY = {
    COMMS = "COMMS", -- All addon communication traffic
    WHISPER = "WHISPER", -- Whisper sends, skips, and online checks
    PROTOCOL = "PROTOCOL", -- Protocol version negotiation and debouncing
    SYNC = "SYNC", -- Data synchronization operations
    CHUNK = "CHUNK", -- Data synchronization operations specific to chunk sending
    DATABASE = "DATABASE", -- Database operations, SavedVariables
    UI = "UI", -- UI operations, window opens/closes
    ITEM = "ITEM", -- Item loading, validation, and processing
    SEARCH = "SEARCH", -- Search operations
    EVENTS = "EVENTS", -- WoW event handling
    INVENTORY = "INVENTORY", -- Inventory (bags, bank, mail) scanning and tracking
    ROSTER = "ROSTER", -- Guild roster updates, online/offline tracking
    LEDGER = "LEDGER" -- Guild bank operations that get logged and stored (buy, sell, trade, destroy, donations)
}

-- Log levels (lower = more verbose)
local logLevels = {
    DEBUG = {
        level = 1, -- Development/troubleshooting details
        description = "Debug (show everything)"
    },
    INFO = {
        level = 2, -- Sync status, normal operations
        description = "Info and above (default)"
    },
    WARN = {
        level = 3, -- Something unexpected but recoverable
        description = "Warnings and above"
    },
    ERROR = {
        level = 4, -- Something failed
        description = "Errors and above"
    },
    RESPONSE = {
        level = 5, -- Response to user commands (always shown)
        description = "Quiet (only respond to /bank commands)"
    }
}
Constants.LOG_LEVEL = logLevels
Constants.LOG_LEVEL_BY_VALUE = {}
for _, info in pairs(logLevels) do
    Constants.LOG_LEVEL_BY_VALUE[info.level] = info
end

-- Detect if mail is from the Auction House
Constants.AH_MAIL_SUBJECT_PATTERNS = {
    {pattern = string_gsub(Globals.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", ".*"), ahType = "REMOVED"},
    {pattern = string_gsub(Globals.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", ".*"), ahType = "EXPIRED"},
    {pattern = string_gsub(Globals.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", ".*"), ahType = "OUTBID"},
    {pattern = string_gsub(Globals.AUCTION_SOLD_MAIL_SUBJECT, "%%s", ".*"), ahType = "SOLD"},
    {pattern = string_gsub(Globals.AUCTION_WON_MAIL_SUBJECT, "%%s", ".*"), ahType = "WON"}
}

-- Map AH mail type to ledger opcode
Constants.AH_MAIL_OPCODES = {
    REMOVED = Constants.LEDGER_OPERATION.AH_CANCELLED, -- item returned, bank alt was seller
    EXPIRED = Constants.LEDGER_OPERATION.AH_CANCELLED, -- item returned, bank alt was seller
    SOLD = Constants.LEDGER_OPERATION.AH_SOLD, -- gold received, bank alt was seller
    OUTBID = Constants.LEDGER_OPERATION.AH_OUTBID, -- gold refunded, bank alt was buyer
    WON = Constants.LEDGER_OPERATION.AH_WON -- item received, bank alt was buyer
}

-- Which item classes need to retain their link due to enchants and suffixes
Constants.ITEM_CLASSES_NEEDING_LINK = {[Enum.ItemClass.Weapon] = true, [Enum.ItemClass.Armor] = true}

-- UI tabs
Constants.UI = {
    TABS = {
        {text = "Browse", value = "browse"},
        {text = "My request list", value = "cart"},
        {text = "Ledger", value = "ledger"},
        {text = "Export", value = "export"},
        {text = "Network", value = "network"},
        {text = "Configuration", value = "configuration"}
    },
    TABS_BANK = {{text = "Request fulfillment", value = "fulfillment"}}
}

-- Sorting
Constants.SORT_LIST = {
    ["default"] = "Default (rarity/type)",
    ["alpha"] = "Alphabetical",
    ["type"] = "By type (class/slot)",
    ["rarity"] = "By rarity",
    ["level"] = "By item level"
}
Constants.SORT_ORDER = {"default", "alpha", "type", "rarity", "level"}
local sortModes = {
    -- Possible property values:
    -- 	name: The name of the item.
    -- 	rarity: The quality of the item. The value is 0 to 7, which represents Poor to Heirloom.
    -- 	level: The item level of this item.
    -- 	price: Items vendor value, in copper. Will need to be parsed into gold, silver, copper. Format ggggsscc.
    -- 	class: The numeric ID of itemType. See Enum.ItemClass (e.g., consumable, container, weapon, armor, reagents, etc.)
    -- 	subClass:  The numeric ID of itemSubType. See https://wowpedia.fandom.com/wiki/ItemType (e.g., potion, elixir, guns, bows, cloth, leather, tailoring, engineer)
    -- 	equipId: The numeric ID indicating in what InventorySlotId an item can be equiped. See Enum.InventoryType (e.g., head, neck, shoulder, chest, feet, etc.)
    -- 	icon: Texture Id of the item icon.

    -- Default (rarity/type)
    default = {
        {property = "rarity", isDescending = false, fallback = 0},
        {property = "class", fallback = 99},
        {property = "equipId", fallback = 0},
        {property = "subClass", fallback = 99},
        {property = "level", fallback = 0},
        {property = "price", fallback = 0},
        {property = "name", fallback = ""}
    },

    -- Alphabetical
    alpha = {{property = "name", fallback = ""}},

    -- By type (class/slot)
    type = {
        {property = "class", fallback = 99},
        {property = "equipId", fallback = ""},
        {property = "subClass", fallback = 99},
        {property = "rarity", fallback = 0},
        {property = "name", fallback = ""}
    },

    --  By rarity
    rarity = {{property = "rarity", isDescending = true, fallback = 0}, {property = "name", fallback = ""}},

    -- By item level
    level = {{property = "level", isDescending = true, fallback = 0}, {property = "name", fallback = ""}}
}
Constants.SORT_MODES = sortModes
Constants.SORT_COMPARATORS = {}
local createSortHandler = Globals.CreateSortHandler
for mode, rules in pairs(sortModes) do
    Constants.SORT_COMPARATORS[mode] = createSortHandler(rules)
end

-- Filtering
Constants.FILTER = {
    SLOT_LIST = {
        ["any"] = "All slots",
        ["head"] = "Head",
        ["neck"] = "Neck",
        ["shoulder"] = "Shoulder",
        ["back"] = "Back",
        ["chest"] = "Chest",
        ["shirt"] = "Shirt",
        ["tabard"] = "Tabard",
        ["wrist"] = "Wrist",
        ["hands"] = "Hands",
        ["waist"] = "Waist",
        ["legs"] = "Legs",
        ["feet"] = "Feet",
        ["finger"] = "Finger",
        ["trinket"] = "Trinket",
        ["onehand"] = "One-hand",
        ["shield"] = "Shield",
        ["twohand"] = "Two-hand",
        ["ranged"] = "Ranged",
        ["mainhand"] = "Main hand",
        ["offhand"] = "Off hand",
        ["holdable"] = "Held in off-hand",
        ["bag"] = "Bag",
        ["robe"] = "Robe"
    },
    SLOT_ORDER = {
        "any",
        "head",
        "neck",
        "shoulder",
        "shirt",
        "chest",
        "wrist",
        "hands",
        "waist",
        "legs",
        "feet",
        "finger",
        "trinket",
        "back",
        "onehand",
        "mainhand",
        "offhand",
        "twohand",
        "ranged",
        "shield",
        "holdable",
        "tabard",
        "bag"
    },
    SLOT_MAP = {
        head = 1,
        neck = 2,
        shoulder = 3,
        shirt = 4,
        chest = 5,
        waist = 6,
        legs = 7,
        feet = 8,
        wrist = 9,
        hands = 10,
        finger = 11,
        trinket = 12,
        onehand = 13,
        shield = 14,
        ranged = 26,
        back = 16,
        twohand = 17,
        bag = 18,
        tabard = 19,
        robe = 20,
        mainhand = 21,
        offhand = 22,
        holdable = 23
    },
    RARITY_LIST = {
        ["any"] = "All qualities",
        ["poor"] = "Poor (grey)",
        ["common"] = "Common (white)",
        ["uncommon"] = "Uncommon (green)",
        ["rare"] = "Rare (blue)",
        ["epic"] = "Epic (purple)",
        ["legendary"] = "Legendary (orange)"
    },
    RARITY_ORDER = {"any", "poor", "common", "uncommon", "rare", "epic", "legendary"},
    RARITY_MAP = {poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5}
}
