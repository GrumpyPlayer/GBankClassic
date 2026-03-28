ADOPTION_STATUS = {
	ADOPTED = "adopted",
	STALE = "stale",
	INVALID = "invalid",
	UNAUTHORIZED = "unauthorized",
	IGNORED = "ignored",
}

-- Timer intervals (in seconds)
TIMER_INTERVALS = {
	VERSION_BROADCAST = 180,        -- 3 minutes: lightweight fingerprint broadcast with version and hash data
	ALT_DATA_QUEUE_RETRY = 5,       -- 5 seconds: queue reprocessing delay
}

-- Log levels (lower = more verbose)
LOG_LEVEL = {
	DEBUG = 1,       -- Development/troubleshooting details
	INFO = 2,        -- Sync status, normal operations
	WARN = 3,        -- Something unexpected but recoverable
	ERROR = 4,       -- Something failed
	RESPONSE = 5,    -- Response to user commands (always shown)
}

-- Debug categories for filtering
DEBUG_CATEGORY = {
	ROSTER = "ROSTER",           -- Guild roster updates, online/offline tracking
	COMMS = "COMMS",             -- All addon communication traffic
	SYNC = "SYNC",               -- Data synchronization operations
	CHUNK = "CHUNK",             -- Data synchronization operations specific to chunk sending
	DONATION = "DONATION",		 -- Donation ledger operations
	WHISPER = "WHISPER",         -- Whisper sends, skips, and online checks
	-- REQUESTS = "REQUESTS",    -- Request system activity and updates
	UI = "UI",                   -- UI operations, window opens/closes
	PROTOCOL = "PROTOCOL",       -- Protocol version negotiation and debouncing
	DATABASE = "DATABASE",       -- Database operations, SavedVariables
	EVENTS = "EVENTS",           -- WoW event handling
	INVENTORY = "INVENTORY",	 -- Inventory (bags, bank, mail) scanning and tracking
	MAIL = "MAIL",               -- Mail inventory scanning and tracking
	ITEM = "ITEM",               -- Item loading, validation, and processing
	-- FULFILL = "FULFILL",		 -- Request fullfillment by guild bank alts
	SEARCH = "SEARCH",			 -- Search operations
	QUERIES = "QUERIES",         -- Peer query/response decisions and hash matching
	REPLIES = "REPLIES",		 -- Debug output from /bank hello replies and /bank wipeall replies
}

-- Communication prefix descriptions for debug logging (maximum of 16 characters)
COMM_PREFIX_DESCRIPTIONS = {
	["gbc-dv2"] = "(Fingerprint)", -- Broadcast addon and roster version, alts: version + itemsHash
	["gbc-d"] = "(Data)", -- Share data (type = alt, roster)
	["gbc-r"] = "(Query)", -- Request specific missing data (type = alt-request, roster) or for legacy clients (type = alt)
	["gbc-h"] = "(Hello)",
	["gbc-hr"] = "(Hello reply)",
	["gbc-s"] = "(Share)",
	["gbc-sr"] = "(Share reply)",
	["gbc-w"] = "(Wipe)",
	["gbc-wr"] = "(Wipe reply)",
}

-- Protocol version and capabilities
PROTOCOL = {
	VERSION = 2,                    -- Current protocol version (bump for breaking changes)
}