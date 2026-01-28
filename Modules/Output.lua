GBankClassic_Output = {}

-- Current log level (default to INFO)
GBankClassic_Output.level = LOG_LEVEL.INFO

-- Communication debug flag (default to false)
GBankClassic_Output.commDebug = false

-- Dedicated chat frame for debug output
GBankClassic_Output.debugFrame = nil
GBankClassic_Output.debugMessageBuffer = {}
GBankClassic_Output.maxBufferSize = 1000

-- Persistent debug log configuration
GBankClassic_Output.persistentLog = {}
GBankClassic_Output.persistentLogMaxEntries = 50000 -- Keep last 50,000 entries
GBankClassic_Output.persistentLogMaxAge = 86400 * 7 -- Keep logs for 7 days (in seconds)

-- Category filtering helpers
function GBankClassic_Output:IsCategoryEnabled(category)
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return false
	end
	return GBankClassic_Database.db.global.debugCategories[category] == true
end

function GBankClassic_Output:SetCategoryEnabled(category, enabled)
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return
	end
	GBankClassic_Database.db.global.debugCategories[category] = enabled
end

function GBankClassic_Output:EnableAllCategories()
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return
	end
	for category, _ in pairs(DEBUG_CATEGORY) do
		GBankClassic_Database.db.global.debugCategories[category] = true
	end
end

function GBankClassic_Output:DisableAllCategories()
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return
	end
	for category, _ in pairs(DEBUG_CATEGORY) do
		GBankClassic_Database.db.global.debugCategories[category] = false
	end
end

function GBankClassic_Output:Init()
	-- Level will be set from Options after DB is loaded
	-- Initialize debug log enabled state (default to false - users can enable in options)
	if GBankClassicDebugLogEnabled == nil then
		GBankClassicDebugLogEnabled = false
	end
	
	-- Load persistent log from SavedVariables if it exists
	if GBankClassicDebugLog then
		self.persistentLog = GBankClassicDebugLog
		GBankClassic_Output:Debug("SYSTEM", "Loaded %d persistent debug log entries from SavedVariables", #self.persistentLog)
		-- Clean up old entries on load
		self:GarbageCollectPersistentLog()
	else
		self.persistentLog = {}
	end
end

function GBankClassic_Output:SetLevel(level)
	self.level = level
end

function GBankClassic_Output:GetLevel()
	return self.level
end

function GBankClassic_Output:SetCommDebug(enabled)
	self.commDebug = enabled
end

function GBankClassic_Output:GetCommDebug()
	return self.commDebug
end

-- Store message in buffer
function GBankClassic_Output:BufferDebugMessage(message)
	table.insert(self.debugMessageBuffer, message)

	-- Keep buffer size manageable
	while #self.debugMessageBuffer > self.maxBufferSize do
		table.remove(self.debugMessageBuffer, 1)
	end
end

-- Redraw all buffered messages to debug frame
function GBankClassic_Output:RedrawDebugMessages()
	if not self.debugFrame then return end

	self.debugFrame:Clear()
	for _, msg in ipairs(self.debugMessageBuffer) do
		self.debugFrame:AddMessage(msg)
	end
end

-- Create or get dedicated debug chat frame
function GBankClassic_Output:GetDebugFrame()
	-- Return cached frame if we have it
	if self.debugFrame then
		return self.debugFrame
	end

	-- Try to find existing GBankClassicDebug tab (even if hidden)
	for i = 1, NUM_CHAT_WINDOWS do
		local name = GetChatWindowInfo(i)
		if name == "GBankClassicDebug" then
			self.debugFrame = _G["ChatFrame"..i]

			-- Ensure OnShow hook is set to redraw messages when tab becomes visible
			if not self.debugFrame.gbankClassicHooked then
				self.debugFrame:HookScript("OnShow", function()
					GBankClassic_Output:RedrawDebugMessages()
				end)
				self.debugFrame.gbankClassicHooked = true
			end

			-- Restore buffered messages when frame is found
			self:RedrawDebugMessages()
			return self.debugFrame
		end
	end

	return nil
end

-- Create dedicated debug chat tab
function GBankClassic_Output:CreateDebugTab()
	-- Check if tab already exists
	for i = 1, NUM_CHAT_WINDOWS do
		local name = GetChatWindowInfo(i)
		if name == "GBankClassicDebug" then
			self.debugFrame = _G["ChatFrame"..i]
			-- Reconfigure and show existing frame
			self.debugFrame:SetMaxLines(1000)
			self.debugFrame:SetFading(false)
			FCF_SetLocked(self.debugFrame, false)
			-- Remove all message filters
			ChatFrame_RemoveAllMessageGroups(self.debugFrame)
			ChatFrame_RemoveAllChannels(self.debugFrame)

			-- Hook OnShow to redraw messages when tab becomes visible
			if not self.debugFrame.gbankClassicHooked then
				self.debugFrame:HookScript("OnShow", function()
					GBankClassic_Output:RedrawDebugMessages()
				end)
				self.debugFrame.gbankClassicHooked = true
			end

			self.debugFrame:Show()
			FCF_DockFrame(self.debugFrame)

			-- Initial draw of buffered messages
			self:RedrawDebugMessages()

			GBankClassic_Core:Print("GBankClassicDebug tab found and shown (ChatFrame"..i..")")
			return true
		end
	end

	-- Find first available chat frame slot (first one with no name)
	local frameIndex = nil
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame"..i]
		if frame then
			local name = GetChatWindowInfo(i)
			-- Use first frame with no name (truly empty slot)
			if not name or name == "" then
				frameIndex = i
				break
			end
		end
	end

	if not frameIndex then
		GBankClassic_Core:Print("|cffff0000Failed to create debug tab: no available chat frames|r")
		GBankClassic_Core:Print("Try using an existing chat frame instead")
		return false
	end

	-- Configure the frame
	local frame = _G["ChatFrame"..frameIndex]

	-- Use WoW's proper API to create a new named window
	FCF_SetWindowName(frame, "GBankClassicDebug")
	FCF_SetWindowColor(frame, 0.3, 0.3, 0.3)
	FCF_SetLocked(frame, false)

	-- Set font size (required for WoW to save the frame)
	local fontFile, _, fontFlags = GameFontNormal:GetFont()
	frame:SetFont(fontFile, 12, fontFlags)

	-- Clear all message groups and channels
	ChatFrame_RemoveAllMessageGroups(frame)
	ChatFrame_RemoveAllChannels(frame)

	-- Configure message history
	frame:SetMaxLines(1000)
	frame:SetFading(false)
	frame:SetTimeVisible(120)
	frame:SetIndentedWordWrap(false)

	-- Make visible and dock it
	frame:Show()
	FCF_DockFrame(frame)

	-- Hook OnShow to redraw messages when tab becomes visible
	if not frame.gbankClassicHooked then
		frame:HookScript("OnShow", function()
			GBankClassic_Output:RedrawDebugMessages()
		end)
		frame.gbankClassicHooked = true
	end

	self.debugFrame = frame

	-- Initial draw of buffered messages
	self:RedrawDebugMessages()

	GBankClassic_Core:Print("Created GBankClassicDebug chat tab (ChatFrame"..frameIndex..")")
	GBankClassic_Core:Print("You can now right-click the tab to customize or close it")
	return true
end

-- Remove debug tab
function GBankClassic_Output:RemoveDebugTab()
	for i = 1, NUM_CHAT_WINDOWS do
		local name = GetChatWindowInfo(i)
		if name == "GBankClassicDebug" then
			local frame = _G["ChatFrame"..i]
			-- Reset the frame completely
			FCF_SetWindowName(frame, "Combat Log", i)
			FCF_ResetChatWindows()
			frame:Hide()
			self.debugFrame = nil
			GBankClassic_Core:Print("Removed GBankClassicDebug tab - please /reload to complete removal")
			return true
		end
	end

	GBankClassic_Core:Print("GBankClassicDebug tab not found")
	return false
end

-- Core logging function
-- If fmt contains %, uses string.format with varargs
-- Otherwise concatenates all arguments with spaces
local function Log(level, prefix, fmt, ...)
	if level < GBankClassic_Output:GetLevel() and level ~= LOG_LEVEL.RESPONSE then
		return false
	end

	local message
	local numArgs = select("#", ...)
	if numArgs > 0 and fmt:find("%%") then
		-- Format string detected, use string.format
		message = string.format(fmt, ...)
	elseif numArgs > 0 then
		-- No format specifiers, concatenate all args with spaces
		local parts = { tostring(fmt) }
		for i = 1, numArgs do
			local arg = select(i, ...)
			parts[#parts + 1] = tostring(arg)
		end
		message = table.concat(parts, " ")
	else
		message = fmt
	end

	-- If debug level and we have a debug frame, use it
	if level == LOG_LEVEL.DEBUG then
		local debugFrame = GBankClassic_Output:GetDebugFrame()
		if debugFrame then
			local fullMessage = "GBankClassic: "
			if prefix then
				fullMessage = fullMessage .. prefix .. " " .. message
			else
				fullMessage = fullMessage .. message
			end

			-- Store in buffer for persistence
			GBankClassic_Output:BufferDebugMessage(fullMessage)

			-- Add to frame
			debugFrame:AddMessage(fullMessage)
			return true
		end
	end

	-- Otherwise use normal print
	if prefix then
		GBankClassic_Core:Print(prefix, message)
	else
		GBankClassic_Core:Print(message)
	end

	-- Always store debug-level messages in persistent log (if debug logging enabled)
	if level == LOG_LEVEL.DEBUG and GBankClassicDebugLogEnabled then
		local fullMessage = "GBankClassic: "
		if prefix then
			fullMessage = fullMessage .. prefix .. " " .. message
		else
			fullMessage = fullMessage .. message
		end
		GBankClassic_Output:AddToPersistentLog(fullMessage)
	end

	return true
end

-- Debug: development/troubleshooting details
function GBankClassic_Output:Debug(fmt, ...)
	-- Check if first parameter is a category
	if type(fmt) == "string" and DEBUG_CATEGORY[fmt] then
		local category = fmt
		-- Check if category is enabled
		if not self:IsCategoryEnabled(category) then
			return false
		end
		-- Shift parameters: first arg after category becomes the format string
		local actualFmt = select(1, ...)
		local args = {select(2, ...)}
		return Log(LOG_LEVEL.DEBUG, "|cff888888[DEBUG]|r", actualFmt, unpack(args))
	end
	-- No category or unknown category - check if uncategorized debug is enabled
	if GBankClassic_Database and GBankClassic_Database.db then
		if not GBankClassic_Database.db.global.showUncategorizedDebug then
			return false
		end
	end
	return Log(LOG_LEVEL.DEBUG, "|cff888888[DEBUG]|r", fmt, ...)
end

-- DebugComm: protocol communication details (controlled by COMMS category)
function GBankClassic_Output:DebugComm(fmt, ...)
	-- Only show if debug level is active AND COMMS category is enabled
	if GBankClassic_Output.level < LOG_LEVEL.DEBUG then
		return false
	end
	-- Check if COMMS category is enabled
	if not self:IsCategoryEnabled("COMMS") then
		return false
	end
	return Log(LOG_LEVEL.DEBUG, "|cff888888[DEBUG] (comm)|r", fmt, ...)
end

-- Info: sync status, normal operations
function GBankClassic_Output:Info(fmt, ...)
	return Log(LOG_LEVEL.INFO, nil, fmt, ...)
end

-- Warn: something unexpected but recoverable
function GBankClassic_Output:Warn(fmt, ...)
	return Log(LOG_LEVEL.WARN, "|cffffcc00[WARN]|r", fmt, ...)
end

-- Error: something failed
function GBankClassic_Output:Error(fmt, ...)
	return Log(LOG_LEVEL.ERROR, "|cffff4444[ERROR]|r", fmt, ...)
end

-- Response: response to user commands (always shown)
function GBankClassic_Output:Response(fmt, ...)
	return Log(LOG_LEVEL.RESPONSE, nil, fmt, ...)
end

-- Add entry to persistent debug log with timestamp
function GBankClassic_Output:AddToPersistentLog(message)
	local entry = {
		timestamp = time(),
		message = message
	}
	table.insert(self.persistentLog, entry)

	-- Simple circular buffer: remove oldest if we exceed max entries
	while #self.persistentLog > self.persistentLogMaxEntries do
		table.remove(self.persistentLog, 1)
	end
end

-- Garbage collect old entries from persistent log
function GBankClassic_Output:GarbageCollectPersistentLog()
	local currentTime = time()
	local cutoffTime = currentTime - self.persistentLogMaxAge
	local removed = 0

	-- Remove entries older than max age
	local i = 1
	while i <= #self.persistentLog do
		if self.persistentLog[i].timestamp < cutoffTime then
			table.remove(self.persistentLog, i)
			removed = removed + 1
		else
			i = i + 1
		end
	end

	if removed > 0 then
		GBankClassic_Output:Debug("SYSTEM", "Garbage collected %d old debug log entries (older than %d days)", removed, self.persistentLogMaxAge / 86400)
	end
end

-- Save persistent log to SavedVariables
function GBankClassic_Output:SavePersistentLog()
	-- Run garbage collection before saving
	self:GarbageCollectPersistentLog()

	-- Write to global SavedVariable
	GBankClassicDebugLog = self.persistentLog

	GBankClassic_Output:Debug("SYSTEM", "Saved %d persistent debug log entries to SavedVariables", #self.persistentLog)
end

-- Export persistent log to formatted string for viewing
function GBankClassic_Output:ExportPersistentLog(maxEntries)
	maxEntries = maxEntries or 100
	local output = {}
	local startIdx = math.max(1, #self.persistentLog - maxEntries + 1)

	for i = startIdx, #self.persistentLog do
		local entry = self.persistentLog[i]
		local timeStr = date("%Y-%m-%d %H:%M:%S", entry.timestamp)
		table.insert(output, string.format("[%s] %s", timeStr, entry.message))
	end

	return table.concat(output, "\n")
end

-- Export persistent log in compact format (no formatting overhead)
function GBankClassic_Output:ExportPersistentLogCompact(maxEntries, searchFilter)
	maxEntries = maxEntries or 1000
	local output = {}
	local startIdx = math.max(1, #self.persistentLog - maxEntries + 1)
	local count = 0

	for i = startIdx, #self.persistentLog do
		local entry = self.persistentLog[i]
		-- Apply search filter if provided
		if not searchFilter or string.find(entry.message:lower(), searchFilter:lower(), 1, true) then
			local timeStr = date("%H:%M:%S", entry.timestamp)  -- Compact time format
			table.insert(output, timeStr .. " " .. entry.message)
			count = count + 1
		end
	end

	return table.concat(output, "\n"), count
end

-- Clear persistent log
function GBankClassic_Output:ClearPersistentLog()
	local count = #self.persistentLog
	self.persistentLog = {}
	GBankClassicDebugLog = {}
	GBankClassic_Output:Response("Cleared %d persistent debug log entries", count)
end