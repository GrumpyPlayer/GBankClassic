ADOPTION_STATUS = {
	ADOPTED = "adopted",
	STALE = "stale",
	INVALID = "invalid",
	UNAUTHORIZED = "unauthorized",
	IGNORED = "ignored",
}

-- Timer intervals (in seconds)
TIMER_INTERVALS = {
	ROSTER_AND_ALT_SYNC = 600,      -- 10 minutes: full roster/alt data sync
	VERSION_BROADCAST = 180,        -- 3 minutes: lightweight version ping
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
	DELTA = "DELTA",             -- Delta sync operations and computations
	SYNC = "SYNC",               -- Data synchronization operations
	CHUNK = "CHUNK",             -- Data synchronization operations specific to chunk sending
	DONATION = "DONATION",		 -- Donation ledger operations
	WHISPER = "WHISPER",         -- Whisper sends, skips, and online checks
	-- REQUESTS = "REQUESTS",       -- Request system activity and updates
	UI = "UI",                   -- UI operations, window opens/closes
	PROTOCOL = "PROTOCOL",       -- Protocol version negotiation
	DATABASE = "DATABASE",       -- Database operations, SavedVariables
	EVENTS = "EVENTS",           -- WoW event handling
	INVENTORY = "INVENTORY",	 -- Inventory (bags, bank, mail) scanning and tracking
	MAIL = "MAIL",               -- Mail inventory scanning and tracking
	ITEM = "ITEM",               -- Item loading, validation, and processing
	-- FULFILL = "FULFILL",		 -- Request fullfillment by guild bank alts
	SEARCH = "SEARCH",			 -- Search operations
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

-- Communication prefix descriptions for debug logging
COMM_PREFIX_DESCRIPTIONS = {
	["gbank-v"] = "(Version)",
	["gbank-dv"] = "(Delta version)",
	["gbank-dv2"] = "(Delta version - Aggregate items)",
	["gbank-d"] = "(Data - No links)", -- togbank-d3 (we're not using togbank-d)
	["gbank-dd"] = "(Delta data - No links)", -- togbank-d4 (we're not using togbank-d2)
	-- ["gbank-dr"] = "(Delta range request)",
	-- ["gbank-dc"] = "(Delta chain)",
	["gbank-r"] = "(Query)",
	["gbank-rr"] = "(Query reply)",
	-- ["gbank-rq"] = "(Request query)",
	-- ["gbank-rd"] = "(Request data)",
	-- ["gbank-rm"] = "(Request mutations)",
	["gbank-state"] = "(State summary)",
	["gbank-nochange"] = "(No change)",
	["gbank-h"] = "(Hello)",
	["gbank-hr"] = "(Hello reply)",
	["gbank-s"] = "(Share)",
	["gbank-sr"] = "(Share reply)",
	["gbank-w"] = "(Wipe)",
	["gbank-wr"] = "(Wipe reply)",
}

-- Protocol version and capabilities
PROTOCOL = {
	VERSION = 2,                    -- Current protocol version (bump for breaking changes)
	SUPPORTS_DELTA = true,          -- This client supports delta updates
	DELTA_SNAPSHOT_MAX_AGE = 3600,  -- 1 hour: snapshots older than this are invalid
	DELTA_HISTORY_MAX_COUNT = 10,   -- Keep last N deltas per alt (memory limit)
	DELTA_CHAIN_MAX_HOPS = 30,      -- Max deltas in one chain request (increased for testing)
	DELTA_CHAIN_MAX_SIZE = 5000,    -- If chain >5KB, fall back to full sync
}