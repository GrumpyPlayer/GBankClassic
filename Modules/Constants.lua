ADOPTION_STATUS = {
	ADOPTED = "adopted",
	STALE = "stale",
	INVALID = "invalid",
	UNAUTHORIZED = "unauthorized",
	IGNORED = "ignored",
}

-- Timer intervals (in seconds)
TIMER_INTERVALS = {
	VERSION_BROADCAST = 180,        -- 3 minutes: lightweight broadcast
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
	-- REQUESTS = "REQUESTS",       -- Request system activity and updates
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

-- -- Request storage settings
-- REQUEST_LOG = {
-- 	EXPIRY_SECONDS = 30 * 24 * 60 * 60,      -- 30 days: completed/cancelled requests and tombstones removed after this
-- 	PRUNE_INTERVAL = 300,                    -- 5 minutes: minimum interval between automatic prunes
-- }

-- -- Request sync throttling settings
-- REQUESTS_SYNC = {
-- 	-- Short values for quick testing; production values should be higher.
-- 	INDEX_QUERY_COOLDOWN = 60,         -- Seconds between index queries (global and per-sender)
-- 	INDEX_INFLIGHT_TIMEOUT = 30,       -- Seconds before in-flight index sync is considered stale
-- }

-- Communication prefix descriptions for debug logging (maximum of 16 characters)
COMM_PREFIX_DESCRIPTIONS = {
	["gbank-dv2"] = "(Fingerprint)", -- Broadcast addon and roster version, alts: version + hash
	["gbank-r"] = "(Query)", -- Request specific missing data (type = alt-request, roster)
	["gbank-rr"] = "(Query reply)", -- Acknowledge to requester that we have the data they want
	["gbank-state"] = "(State summary)", -- Send to acknowledger our version/hash for one specific guild bank alt (type = state-summary, name = alt, summary = { version, hash })
	["gbank-d"] = "(Data)", -- Share data (type = alt, roster)
	["gbank-nochange"] = "(No change)", -- Confirm we have nothing to share

	["gbank-h"] = "(Hello)",
	["gbank-hr"] = "(Hello reply)",
	["gbank-s"] = "(Share)",
	["gbank-sr"] = "(Share reply)",
	["gbank-w"] = "(Wipe)",
	["gbank-wr"] = "(Wipe reply)",

	-- ["gbank-rq"] = "(Request query)",
	-- ["gbank-rd"] = "(Request data)",
	-- ["gbank-rm"] = "(Request mutations)",
}

-- Protocol version and capabilities
PROTOCOL = {
	VERSION = 2,                    -- Current protocol version (bump for breaking changes)
}