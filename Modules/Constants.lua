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
	DEBUG = 1,       -- development/troubleshooting details
	INFO = 2,        -- sync status, normal operations
	WARN = 3,        -- something unexpected but recoverable
	ERROR = 4,       -- something failed
	RESPONSE = 5,    -- response to user commands (always shown)
}

-- Debug categories for filtering
DEBUG_CATEGORY = {
	ROSTER = "ROSTER",           -- Guild roster updates, online/offline tracking
	COMMS = "COMMS",             -- All addon communication traffic
	DELTA = "DELTA",             -- Delta sync operations and computations
	SYNC = "SYNC",               -- Data synchronization operations
	CHUNK = "CHUNK",             -- Data synchronization operations specific to chunk sending
	CACHE = "CACHE",             -- Cache operations (guild roster cache, etc.)
	WHISPER = "WHISPER",         -- Whisper sends, skips, and online checks
	-- REQUESTS = "REQUESTS",       -- Request system activity and updates
	UI = "UI",                   -- UI operations, window opens/closes
	PROTOCOL = "PROTOCOL",       -- Protocol version negotiation
	DATABASE = "DATABASE",       -- Database operations, SavedVariables
	EVENTS = "EVENTS",           -- WoW event handling
	INVENTORY = "INVENTORY",	 -- Inventory (bags, bank, mail) scanning and tracking
	MAIL = "MAIL",               -- Mail inventory scanning and tracking
	ITEM = "ITEM",               -- Item loading, validation, and processing
	-- FULFILL = "FULFILL",
	SEARCH = "SEARCH",			-- Search operations
}

-- -- Request storage settings
-- REQUEST_LOG = {
-- 	EXPIRY_SECONDS = 30 * 24 * 60 * 60,      -- 30 days: completed/cancelled requests and tombstones removed after this
-- 	PRUNE_INTERVAL = 300,                    -- 5 minutes: minimum interval between automatic prunes
-- }

-- -- Request sync throttling settings
-- REQUESTS_SYNC = {
-- 	-- NOTE: Short values for quick testing; production values should be higher.
-- 	INDEX_QUERY_COOLDOWN = 60,         -- seconds between index queries (global and per-sender)
-- 	INDEX_INFLIGHT_TIMEOUT = 30,       -- seconds before in-flight index sync is considered stale
-- }

-- Communication prefix descriptions for debug logging
COMM_PREFIX_DESCRIPTIONS = {
	["gbank-v"] = "(Version)",
	["gbank-dv"] = "(Delta version)",
	["gbank-d"] = "(Data - No links)",
	["gbank-dd"] = "(Delta data - No links)",
	-- ["gbank-dr"] = "(Delta range request)",
	-- ["gbank-dc"] = "(Delta chain)",
	["gbank-r"] = "(Query)",
	["gbank-rr"] = "(Query reply)",
	-- ["gbank-rq"] = "(Request Query)",
	-- ["gbank-rd"] = "(Request Data)",
	-- ["gbank-rm"] = "(Request Mutations)",
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
	DELTA_SUPPORT_THRESHOLD = 0.05, -- Use delta if >5% of online guild supports it (lowered for testing: 1 of 14 = 7.1%)
	DELTA_HISTORY_MAX_COUNT = 10,   -- Keep last N deltas per alt (memory limit)
	DELTA_HISTORY_MAX_AGE = 3600,   -- 1 hour: purge deltas older than this
	DELTA_CHAIN_MAX_HOPS = 30,      -- Max deltas in one chain request (increased for testing)
	DELTA_CHAIN_MAX_SIZE = 5000,    -- If chain >5KB, fall back to full sync
}

-- Feature flags (for easy enable/disable during development/testing)
FEATURES = {
	DELTA_ENABLED = true,           -- Enable delta sync protocol
	FORCE_DELTA_SYNC = false,       -- Force delta sync (bypass thresholds) for testing
	FORCE_FULL_SYNC = false,        -- Force full sync (disable delta) for testing
}