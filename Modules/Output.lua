local addonName, GBCR = ...

GBCR.Output = {}
local Output = GBCR.Output

local Globals = GBCR.Globals
local date = Globals.date
local find = Globals.find
local select = Globals.select
local string_format = Globals.string_format
local tostring = Globals.tostring
local type = Globals.type

local GetServerTime = Globals.GetServerTime

local Constants = GBCR.Constants
local colorGray = Constants.COLORS.GRAY
local colorOrange = Constants.COLORS.ORANGE
local colorRed = Constants.COLORS.RED
local logLevels = Constants.LOG_LEVEL

-- Helper function to add debug messages to a buffer for display
local function bufferContent(self, message)
    local debugMessageBuffer = self.debugMessageBuffer
    debugMessageBuffer[#debugMessageBuffer + 1] = message

    local limit = Constants.LIMITS.MAX_BUFFER_SIZE
    local currentSize = #debugMessageBuffer

    if currentSize > limit + 50 then
        local newCount = currentSize - 50
        for i = 1, newCount do
            debugMessageBuffer[i] = debugMessageBuffer[i + 50]
        end

        for i = newCount + 1, currentSize do
            debugMessageBuffer[i] = nil
        end
    end
end

-- Helper function that enabled all logging
local function log(self, level, prefix, fmt, ...)
	if level < GBCR.Options:GetLogLevel() and level ~= logLevels.RESPONSE.level then
		return false
	end

	local message
	local numArgs = select("#", ...)

	if numArgs > 0 then
		if type(fmt) == "string" and find(fmt, "%", 1, true) then
			message = string_format(fmt, ...)
		else
			message = tostring(fmt)
			for i = 1, numArgs do
				message = message .. " " .. tostring(select(i, ...))
			end
		end
	else
		message = tostring(fmt)
	end

	if level == logLevels.DEBUG.level then
		local timeStr = date("%H:%M:%S", GetServerTime())
		bufferContent(self, timeStr .. ": " .. (prefix or "") .. " " .. message)

		GBCR.UI:QueueDebugLogRefresh()

		return true
	end

	if prefix then
		GBCR.Addon:Print(prefix, message)
	else
		GBCR.Addon:Print(message)
	end

	return true
end

-- Development/troubleshooting details
local function debug(self, categoryOrFmt, ...)
	if type(categoryOrFmt) == "string" and Constants.DEBUG_CATEGORY[categoryOrFmt] then
		if not GBCR.Options:IsCategoryEnabled(categoryOrFmt) then
			return false
		end

		return log(self, logLevels.DEBUG.level, Globals:Colorize(colorGray, "[" .. categoryOrFmt .. "]"), ...)
	end

	-- Fallback: no category specified
	return log(self, logLevels.DEBUG.level, Globals:Colorize(colorGray, "[DEBUG]"), categoryOrFmt, ...)
end

-- Potocol communication details (controlled by COMMS category)
local function debugComm(self, fmt, ...)
	if GBCR.Options:GetLogLevel() < logLevels.DEBUG.level then
		return false
	end

	if not GBCR.Options:IsCategoryEnabled("COMMS") then
		return false
	end

	return log(self, logLevels.DEBUG.level, Globals:Colorize(colorGray, "[COMMS] (DEBUG)"), fmt, ...)
end

-- Sync status, normal operations
local function info(self, fmt, ...)
	return log(self, logLevels.INFO.level, nil, fmt, ...)
end

-- Something unexpected but recoverable
local function warn(self, fmt, ...)
	return log(self, logLevels.WARN.level, Globals:Colorize(colorOrange, "[WARN]"), fmt, ...)
end

-- Something failed
local function error(self, fmt, ...)
	return log(self, logLevels.ERROR.level, Globals:Colorize(colorRed, "[ERROR]"), fmt, ...)
end

-- Response to user commands (always shown)
local function response(self, fmt, ...)
	return log(self, logLevels.RESPONSE.level, nil, fmt, ...)
end

-- Export functions for other modules
Output.Debug = debug
Output.DebugComm = debugComm
Output.Info = info
Output.Warn = warn
Output.Error = error
Output.Response = response