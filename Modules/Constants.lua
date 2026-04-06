local addonName, GBCR = ...

GBCR.Constants = {}
local Constants = GBCR.Constants

local Globals = GBCR.Globals
local gsub = Globals.gsub
local ipairs = Globals.ipairs
local pairs = Globals.pairs
local string_format = Globals.string_format
local string_gsub = Globals.string_gsub
local tostring = Globals.tostring

local Enum = Globals.Enum
local lootItemPushedSelf = Globals.LOOT_ITEM_PUSHED_SELF
local lootItemPushedSelfMultiple = Globals.LOOT_ITEM_PUSHED_SELF_MULTIPLE
local lootItemSelf = Globals.LOOT_ITEM_SELF
local lootItemSelfMultiple = Globals.LOOT_ITEM_SELF_MULTIPLE

-- Limits
Constants.LIMITS = {
	COMPRESSION_LEVEL = 6,			-- LibDeflate compression level (same payload size for data and fingerprint when using 6-9)
	MAX_PENDING_SENDS = 3, 			-- TODO
	SEARCH_RESULTS = 100,			-- Maximum amount of search results before the user is prompted to refine their search
	MAX_CONCURRENT_ASYNC = 3, 		-- Limit concurrent async operations for item link reconstruction
	BATCH_SIZE = 100, 				-- Limit the batch size for item link reconstruction and UI rendering
	MAX_BUFFER_SIZE = 4096			-- Maximum amount of messages for the /chat debuglog
}

-- Timer intervals (in seconds)
Constants.TIMER_INTERVALS = {
	FINGERPRINT_BROADCAST = 180,    -- 3 minutes: lightweight fingerprint broadcast
	DEBUG_LOG_REFRESH = 2.5,		-- Runs 2.5s after the first event (fixed delay)
	UI_REFRESH = 2.5,				-- Runs 2.5s after the first event (fixed delay)
	BUILD_DONATION_CACHE = 2.5,		-- Runs 2.5s after the last event (trailing debouce, stays quiet until activity is done)
	REBUILD_ROSTER = 10,			-- Runs 10s after the last event (trailing debouce, stays quiet until activity is done)
	BAG_UPDATE_QUIET_TIME = 5,      -- 5 seconds: scan the updated inventory after 5 seconds without BAG_UPDATE_DELAYED events
	TOOLTIP_THROTTLE_MS = 50,		-- 50ms: time between tooltip updates when hovering items in our UI
	BATCH_DELAY = 0.5, 				-- 1/2 second: delay between batches of item link reconstruction (slower = smoother)
	SEARCH_DEBOUNCE = 0.3,			-- Wait until the user stops typing for ~0.3 seconds before firing the expensive search
}

-- One place to define and maintain non-class specific colors
Constants.COLORS = {
	BLUE 	= "ff80bfff", 		-- Debug messages about sharing, fallback for class-color
	GREEN 	= "ff33ff99", 		-- Help text color codes header
	YELLOW 	= "ffffff00", 		-- Debug messages about queries
	GOLD 	= "ffe6cc80", 		-- Help text color codes commands, AddOn is outdated message
	ORANGE 	= "ffffa600",		-- Warnings
	RED 	= "ffff0000",		-- Failures
	GRAY 	= "ff808080",		-- Debug category prefix in debug messages
	WHITE 	= "ffffffff",		-- Temporary link
}

-- Commands are displayed in help in the order they appear here
local commandRegistry = {
	-- Command registry: name, usage, help (nil to hide from help output), expert, handler

	-- Basic commands
	{
		name = "config",
		help = "open the AddOn configuration options",
		handler = function()
			GBCR.Options:Open()
		end,
	},
	{
		name = "help",
		help = "this message",
		handler = function()
			GBCR.Chat:ShowHelp()
		end,
	},
	{
		name = "reset",
		help = "reset your own " .. addonName .. " database",
		handler = function()
			GBCR.Guild:ResetGuild()
		end,
	},
	{
		name = "restoreui",
		help = "restore the user interface window size and position back to the default",
		expert = true,
		handler = function()
			GBCR.UI:RestoreUI()
		end,
	},
	{
		name = "sync",
		help = "manually receive the latest data from other online users with guild bank data; this is done every 10 minutes automatically",
		handler = function()
			GBCR.Protocol:PerformSync()
		end,
	},
	{
		name = "share",
		help = "manually share the contents of your guild bank with other online users of " .. addonName .. "; this is done every 3 minutes automatically",
		handler = function()
			GBCR.Inventory:OnUpdateStart()
			GBCR.Inventory:OnUpdateStop()
			GBCR.Protocol:Share()
		end,
	},
	{
		name = "version",
		help = "display the " .. addonName .. " version",
		handler = function()
			GBCR.Output:Response("You are using " .. addonName .. ", version: %s.", Globals:Colorize(Constants.COLORS.GOLD, GBCR.Core.addonVersion))
		end,
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
				local queueMultipleAltCount = Globals:Count(GBCR.Protocol.debounceQueues.multipleAlts or {})
				local queueSingularAltCount = Globals:Count(GBCR.Protocol.debounceQueues.singularAlt or {})

				GBCR.Output:Response("Debounce status: %s.", Globals:Colorize(Constants.COLORS.GOLD, GBCR.Protocol.debounceConfig.enabled and "enabled" or "disabled"))
				GBCR.Output:Response("Queued protocol messages with singular guild bank alt: %d.", Globals:Colorize(Constants.COLORS.GOLD, queueSingularAltCount))
				GBCR.Output:Response("Queued protocol messages with multiple guild bank alts: %d.", Globals:Colorize(Constants.COLORS.GOLD, queueMultipleAltCount))

				if arg1 == "detail" then
					if queueMultipleAltCount > 0 then
						GBCR.Output:Response("Messages with multiple guild bankt alts:")
						for altNorm, best in pairs(GBCR.Protocol.debounceQueues.multipleAlts) do
							GBCR.Output:Response("  %s: sender=%s, version=%s", altNorm, best.sender, tostring(best.version))
						end
					end
					if queueSingularAltCount > 0 then
						GBCR.Output:Response("Messages with singular guild bank alt:")
						for key, queued in pairs(GBCR.Protocol.debounceQueues.singularAlt) do
							GBCR.Output:Response("  %s: sender=%s, version=%s", key, queued.sender, tostring(queued.version))
						end
					end
				end
			end
		end,
	},
	{
		name = "debugclear",
		help = "clear the debug output",
		expert = true,
		handler = function()
			GBCR.UI:ClearDebugContent()
		end,
	},
	{
		name = "debuglog",
		help = "create a dedicated window for debug output",
		expert = true,
		handler = function()
			GBCR.UI.Debug:Toggle()
		end,
	},
	{
		name = "hello",
		help = "understand which online guild members use which addon version and know what guild bank data",
		expert = true,
		handler = function()
			GBCR.Protocol:Hello()
		end,
	},
	{
		name = "roster",
		help = "if officer notes are used to define guild bank alts, use this command to share the roster of guild bank alts with online guild members",
		expert = true,
		handler = function()
			GBCR.Protocol:AuthorRosterData()
		end,
	},
	{
		name = "versions",
		help = "show addon versions of online guild members",
		expert = true,
		handler = function()
			GBCR.Chat:PrintVersions()
		end,
	},
	{
		name = "wipe",
		help = "reset your own " .. addonName .. " database",
		expert = true,
		handler = function()
			GBCR.Guild:ResetGuild()
		end,
	},
	{
		name = "wipeall",
		help = "officer only: reset your own " .. addonName .. " database and that of all online guild members",
		expert = true,
		handler = function()
			GBCR.Protocol:Wipe()
		end,
	},

	-- Hidden commands (no help text)
	{
		name = "conf", -- alternative to `/bank config`
		help = "open the AddOn configuration options",
		handler = function()
			GBCR.Options:Open()
		end,
	},
	{
		name = "options", -- alternative to `/bank config`
		help = "open the AddOn configuration options",
		handler = function()
			GBCR.Options:Open()
		end,
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
		end,
	},
}
Constants.COMMAND_REGISTRY = commandRegistry
Constants.COMMAND_HANDLERS = {}
for _, cmd in ipairs(commandRegistry) do
	Constants.COMMAND_HANDLERS[cmd.name] = cmd.handler
end

-- Instructions as multiline strings for readability
Constants.HELP_INSTRUCTIONS = {
	{
		title = "Instructions for setting up a new guild bank:",
		text = string_format([[
1. Log in with the guild bank character, ensuring they are in the guild.
2. Add %s to their guild or officer note, then type %s.
3. In addon options (Escape -> Options -> Addons -> GBankClassic), click on the %s icon (expand/collapse) to the left of the entry, enable reporting and scanning for the bank character in the %s section.
4. Open and close your bank and mailbox.
5. Type %s and confirm your bank character is included in the roster.
6. Type %s. Wait up to 3 minutes (or type %s for immediate sharing) until %s completes.
7. Verify with a guild member (they type %s).]], Globals:Colorize(Constants.COLORS.GOLD, "gbank"), Globals:Colorize(Constants.COLORS.GOLD, "/reload"), Globals:Colorize(Constants.COLORS.GOLD, "-"), Globals:Colorize(Constants.COLORS.GOLD, "Bank"), Globals:Colorize(Constants.COLORS.GOLD, "/bank roster"), Globals:Colorize(Constants.COLORS.GOLD, "/reload"), Globals:Colorize(Constants.COLORS.GOLD, "/bank share"), Globals:Colorize(Constants.COLORS.GOLD, "Finished sending your latest data"), Globals:Colorize(Constants.COLORS.GOLD, "/bank")),
	},
	{
		title = "Instructions for removing a guild bank:",
		text = string_format([[
1. Log in with an officer or another bank character in the same guild (or a character from a different guild).
2. If the bank character is still in the guild, remove %s from their notes.
3. Type %s and confirm the bank character is no longer listed.
4. Verify with a guild member (they type %s).]], Globals:Colorize(Constants.COLORS.GOLD, "gbank"), Globals:Colorize(Constants.COLORS.GOLD, "/bank roster"), Globals:Colorize(Constants.COLORS.GOLD, "/bank")),
	},
}

-- For processing incoming data
Constants.ADOPTION_STATUS = {
	ADOPTED = "adopted",
	STALE = "stale",
	INVALID = "invalid",
	UNAUTHORIZED = "unauthorized",
	IGNORED = "ignored"
}

-- Communication prefix descriptions for debug logging (maximum of 16 characters)
Constants.COMM_PREFIX_DESCRIPTIONS = {
	["gbc-fp-share"] = "(fingerprint share)", 		-- Share fingerprint data
	["gbc-fp-query"] = "(fingerprint query)", 		-- Query fingerprint data
	["gbc-data-share"] = "(data share)", 			-- Share guild bank alt data
	["gbc-data-query"] = "(data query)", 			-- Request guild bank alt data
	["gbc-roster-share"] = "(roster share)", 		-- Share roster data
	["gbc-roster-query"] = "(roster query)", 		-- Request roster data
	["gbc-h"] = "(hello)",
	["gbc-hr"] = "(hello reply)",
	["gbc-s"] = "(share)",
	["gbc-sr"] = "(share reply)",
	["gbc-w"] = "(wipe)",
	["gbc-wr"] = "(wipe reply)"
}

-- Debug categories for filtering
Constants.DEBUG_CATEGORY = {
	ROSTER = "ROSTER",           -- Guild roster updates, online/offline tracking
	COMMS = "COMMS",             -- All addon communication traffic
	SYNC = "SYNC",               -- Data synchronization operations
	CHUNK = "CHUNK",             -- Data synchronization operations specific to chunk sending
	DONATIONS = "DONATIONS",		 -- Donation ledger operations
	WHISPER = "WHISPER",         -- Whisper sends, skips, and online checks
	-- REQUESTS = "REQUESTS",    -- Request system activity and updates
	UI = "UI",                   -- UI operations, window opens/closes
	PROTOCOL = "PROTOCOL",       -- Protocol version negotiation and debouncing
	DATABASE = "DATABASE",       -- Database operations, SavedVariables
	EVENTS = "EVENTS",           -- WoW event handling
	INVENTORY = "INVENTORY",	 -- Inventory (bags, bank, mail) scanning and tracking
	-- MAIL = "MAIL",               -- Mail scanning and tracking
	ITEM = "ITEM",               -- Item loading, validation, and processing
	-- FULFILL = "FULFILL",		 -- Request fullfillment by guild bank alts
	SEARCH = "SEARCH",			 -- Search operations
	-- QUERIES = "QUERIES",         -- Peer query/response decisions and hash matching
	-- REPLIES = "REPLIES" 		 -- Debug output from /bank hello replies and /bank wipeall replies
}

-- Log levels (lower = more verbose)
local logLevels = {
	DEBUG = {
		level = 1,		-- Development/troubleshooting details
		description = "Debug (show everything)",
	},
	INFO = {
		level = 2,      -- Sync status, normal operations
		description = "Info and above (default)",
	},
	WARN = {
		level = 3,		-- Something unexpected but recoverable
		description = "Warnings and above",
	},
	ERROR = {
		level = 4,		-- Something failed
		description = "Errors and above"
	},
	RESPONSE = {
		level = 5,		-- Response to user commands (always shown)
		description = "Quiet (only respond to /bank commands)"
	}
}
Constants.LOG_LEVEL = logLevels
Constants.LOG_LEVEL_BY_VALUE = {}
for _, info in pairs(logLevels) do
    Constants.LOG_LEVEL_BY_VALUE[info.level] = info
end

-- Loot
Constants.PATTERN_LOOT_MULTIPLE = string_gsub(string_gsub(lootItemSelfMultiple, "%%s", "(.+)"), "%%d", "(%%d+)")
Constants.PATTERN_LOOT_PUSHED_MULTIPLE = string_gsub(string_gsub(lootItemPushedSelfMultiple, "%%s", "(.+)"), "%%d", "(%%d+)")
Constants.PATTERN_LOOT_PUSHED_SINGLE = string_gsub(lootItemPushedSelf, "%%s", "(.+)")
Constants.PATTERN_LOOT_SINGLE = string_gsub(lootItemSelf, "%%s", "(.+)")

-- Detect if mail is from the Auction House
Constants.AH_MAIL_SUBJECT_PATTERNS = {
    gsub(Globals.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", ".*"),
    gsub(Globals.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", ".*"),
    gsub(Globals.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", ".*"),
    gsub(Globals.AUCTION_SOLD_MAIL_SUBJECT, "%%s", ".*"),
    gsub(Globals.AUCTION_WON_MAIL_SUBJECT, "%%s", ".*"),
}

-- Which item classes need to retain their link due to enchants and suffixes
Constants.ITEM_CLASSES_NEEDING_LINK = {
	[Enum.ItemClass.Weapon] = true,
	[Enum.ItemClass.Armor] = true,
}

-- Sorting
Constants.SORT_LIST = {
	["default"] = "Default (rarity/type)",
	["alpha"]   = "Alphabetical",
	["type"]    = "By type (class/slot)",
	["rarity"]  = "By rarity",
	["level"]   = "By item level"
}
Constants.SORT_ORDER = { "default", "alpha", "type", "rarity", "level" }
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
		{ property = "rarity", isDescending = false, fallback = 0 },
		{ property = "class", fallback = 99 },
		{ property = "equipId", fallback = 0 },
		{ property = "subClass", fallback = 99 },
		{ property = "level", fallback = 0 },
		{ property = "price", fallback = 0 },
		{ property = "name", fallback = "" },
	},

	-- Alphabetical
	alpha = {
		{ property = "name", fallback = "" },
	},

	-- By type (class/slot)
	type = {
		{ property = "class", fallback = 99 },
		{ property = "equipId", fallback = "" },
		{ property = "subClass", fallback = 99 },
		{ property = "rarity", fallback = 0 },
		{ property = "name", fallback = "" },
	},

	--  By rarity
	rarity = {
		{ property = "rarity", isDescending = true, fallback = 0 },
		{ property = "name", fallback = "" },
	},

	-- By item level
	level = {
		{ property = "level", isDescending = true, fallback = 0 },
		{ property = "name", fallback = "" },
	},
}
Constants.SORT_MODES = sortModes
Constants.SORT_COMPARATORS = {}
for mode, rules in pairs(sortModes) do
    Constants.SORT_COMPARATORS[mode] = Globals:CreateSortHandler(rules)
end

-- Filtering
Constants.FILTER = {
	CLASS_MAP = {
		armor = 4, weapon = 2, consumable = 0, trade = 7, container = 1, recipe = 9, quest = 12
	},
	MISC_CLASSES = {
		[15]=true, [5]=true, [10]=true, [13]=true, [14]=true, [3]=true, [8]=true, [11]=true, [6]=true
	},
	TYPE_LIST = {
        ["any"]       = "All types",
        ["armor"]     = "Armor",
        ["weapon"]    = "Weapons",
        ["consumable"]= "Consumables",
        ["trade"]     = "Trade goods",
        ["container"] = "Container",
        ["recipe"]    = "Recipe",
        ["quest"]     = "Quest items",
        ["misc"]      = "Everything else"
    },
	TYPE_ORDER = { "any", "armor", "weapon", "consumable", "trade", "container", "recipe", "quest", "misc" },
	SLOT_LIST = {
        ["any"]       = "All slots",
        ["head"]      = "Head",
        ["neck"]      = "Neck",
        ["shoulder"]  = "Shoulder",
        ["back"]      = "Back",
        ["chest"]     = "Chest",
        ["shirt"]     = "Shirt",
        ["tabard"]    = "Tabard",
        ["wrist"]     = "Wrist",
        ["hands"]     = "Hands",
        ["waist"]     = "Waist",
        ["legs"]      = "Legs",
        ["feet"]      = "Feet",
        ["finger"]    = "Finger",
        ["trinket"]   = "Trinket",
        ["onehand"]   = "One-hand",
        ["shield"]    = "Shield",
        ["twohand"]   = "Two-hand",
        ["ranged"]    = "Ranged",
        ["mainhand"]  = "Main hand",
        ["offhand"]   = "Off hand",
        ["holdable"]  = "Held in off-hand",
        ["bag"]       = "Bag",
        ["robe"]      = "Robe"
    },
	SLOT_ORDER = { "any", "head", "neck", "shoulder", "shirt", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket", "back", "onehand", "mainhand", "offhand", "twohand", "ranged", "shield", "holdable", "tabard", "bag" },
	SLOT_MAP = {
		head 		= 1,
		neck 		= 2,
		shoulder 	= 3,
		shirt 		= 4,
		chest 		= 5,
		waist 		= 6,
		legs 		= 7,
		feet 		= 8,
		wrist 		= 9,
		hands 		= 10,
		finger 		= 11,
		trinket 	= 12,
		onehand 	= 13,
		shield 		= 14,
		ranged 		= 26,
		back 		= 16,
		twohand 	= 17,
		bag 		= 18,
		tabard 		= 19,
		robe		= 20,
		mainhand 	= 21,
		offhand 	= 22,
		holdable 	= 23
	},
	RARITY_LIST = {
        ["any"]       = "All qualities",
        ["poor"]      = "Poor (grey)",
        ["common"]    = "Common (white)",
        ["uncommon"]  = "Uncommon (green)",
        ["rare"]      = "Rare (blue)",
        ["epic"]      = "Epic (purple)",
        ["legendary"] = "Legendary (orange)"
    },
	RARITY_ORDER = { "any", "poor", "common", "uncommon", "rare", "epic", "legendary" },
	RARITY_MAP = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 },
}