local addonName, GBCR = ...

GBCR.Output = {}
local Output = GBCR.Output

local Globals = GBCR.Globals
local date = Globals.date
local GetServerTime = Globals.GetServerTime
local GetClassColor = Globals.GetClassColor
local FCF_DockFrame = Globals.FCF_DockFrame
local FCF_SetLocked = Globals.FCF_SetLocked
local FCF_SetWindowColor = Globals.FCF_SetWindowColor
local FCF_SetWindowName = Globals.FCF_SetWindowName
local FCF_SelectDockFrame = Globals.FCF_SelectDockFrame
local ChatFrame1 = Globals.ChatFrame1
local GetChatWindowInfo = Globals.GetChatWindowInfo
local ChatFrame_RemoveAllMessageGroups = Globals.ChatFrame_RemoveAllMessageGroups
local ChatFrame_RemoveAllChannels = Globals.ChatFrame_RemoveAllChannels
local GameFontNormal = Globals.GameFontNormal
local NUM_CHAT_WINDOWS = Globals.NUM_CHAT_WINDOWS

local Constants = GBCR.Constants
local colorGray = Constants.COLORS.GRAY
local colorRed = Constants.COLORS.RED
local colorOrange = Constants.COLORS.ORANGE
local logLevels = Constants.LOG_LEVEL

-- Helper to color player names
function Output:ColorPlayerName(name)
	if not name or name == "" then
		return ""
	end

	local normalized = GBCR.Guild:NormalizeName(name) or name
	local playerClass = GBCR.Guild:GetGuildMemberInfo(normalized)
	if playerClass then
		local _, _, _, classColor = GetClassColor(playerClass)
		if classColor then
			return GBCR.Globals:Colorize(classColor, name)
		end
	end

	return GBCR.Globals:Colorize(colorRed, name)
end

-- Core logging function
-- If fmt contains %, uses string.format with varargs
-- Otherwise concatenates all arguments with spaces
local function log(level, prefix, fmt, ...)
	if level < GBCR.Options:GetLogLevel() and level ~= logLevels.RESPONSE.level then
		return false
	end

	local message
	local numArgs = select("#", ...)
	if numArgs > 0 and type(fmt) == "string" and fmt:find("%%") then
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
		message = tostring(fmt)
	end

	-- If debug level and we have a debug frame, use it
	if level == logLevels.DEBUG.level then
		local debugFrame = Output:GetDebugFrame()
		if debugFrame then
			local timeStr = date("%H:%M:%S", GetServerTime())
			local fullMessage = timeStr .. " GBankClassic: "
			if prefix then
				fullMessage = fullMessage .. prefix .. " " .. message
			else
				fullMessage = fullMessage .. message
			end

			-- Store in buffer for persistence
			Output:BufferDebugMessage(fullMessage)

			-- Add to frame
			debugFrame:AddMessage(fullMessage)

			return true
		end
	end

	-- Otherwise use normal print
	if prefix then
		GBCR.Addon:Print(prefix, message)
	else
		GBCR.Addon:Print(message)
	end

	return true
end

-- Development/troubleshooting details
function Output:Debug(fmt, ...)
	-- Check if first parameter is a category
	if type(fmt) == "string" and Constants.DEBUG_CATEGORY[fmt] then
		local category = fmt
		-- Check if category is enabled
		if not GBCR.Options:IsCategoryEnabled(category) then
			return false
		end

		-- Shift parameters: first arg after category becomes the format string
		local actualFmt = select(1, ...)
		local args = {select(2, ...)}

		return log(logLevels.DEBUG.level, GBCR.Globals:Colorize(colorGray, "[" .. category .. "]"), actualFmt, unpack(args))
	end

	-- Fallback: no category specified
	return log(logLevels.DEBUG.level, GBCR.Globals:Colorize(colorGray, "[DEBUG]"), fmt, ...)
end

-- DebugComm: protocol communication details (controlled by COMMS category)
function Output:DebugComm(fmt, ...)
	-- Only show if debug level is active and the COMMS category is enabled
	if GBCR.Options:GetLogLevel() < logLevels.DEBUG.level then
		return false
	end
	-- Check if COMMS category is enabled
	if not GBCR.Options:IsCategoryEnabled("COMMS") then
		return false
	end

	return log(logLevels.DEBUG.level, GBCR.Globals:Colorize(colorGray, "[COMMS] (DEBUG)"), fmt, ...)
end

-- Info: sync status, normal operations
function Output:Info(fmt, ...)
	return log(logLevels.INFO.level, nil, fmt, ...)
end

-- Warn: something unexpected but recoverable
function Output:Warn(fmt, ...)
	return log(logLevels.WARN.level, GBCR.Globals:Colorize(colorOrange, "[WARN]"), fmt, ...)
end

-- Error: something failed
function Output:Error(fmt, ...)
	return log(logLevels.ERROR.level, GBCR.Globals:Colorize(colorRed, "[ERROR]"), fmt, ...)
end

-- Response: response to user commands (always shown)
function Output:Response(fmt, ...)
	return log(logLevels.RESPONSE.level, nil, fmt, ...)
end

-- Store message in buffer
function Output:BufferDebugMessage(message)
	self.debugMessageBuffer = {}
	table.insert(self.debugMessageBuffer, message)

	-- Keep buffer size manageable
	while #self.debugMessageBuffer > Constants.LIMITS.MAX_BUFFER_SIZE do
		table.remove(self.debugMessageBuffer, 1)
	end
end

-- Redraw all buffered messages to debug frame
function Output:RedrawDebugMessages()
	if not self.debugFrame then
		return
	end

	self.debugFrame:Clear()
	for _, msg in ipairs(self.debugMessageBuffer or {}) do
		self.debugFrame:AddMessage(msg)
	end
end

-- Create or get dedicated debug chat frame
function Output:GetDebugFrame()
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
					Output:RedrawDebugMessages()
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
function Output:CreateDebugTab()
	-- Check if tab already exists
	for i = 1, NUM_CHAT_WINDOWS do
		local name = GetChatWindowInfo(i)
		if name == "GBankClassicDebug" then
			self.debugFrame = _G["ChatFrame"..i]
			-- Reconfigure and show existing frame
			self.debugFrame:SetMaxLines(Constants.LIMITS.MAX_BUFFER_SIZE)
			self.debugFrame:SetFading(false)
			FCF_SetLocked(self.debugFrame, false)
			-- Remove all message filters
			ChatFrame_RemoveAllMessageGroups(self.debugFrame)
			ChatFrame_RemoveAllChannels(self.debugFrame)

			-- Hook OnShow to redraw messages when tab becomes visible
			if not self.debugFrame.gbankClassicHooked then
				self.debugFrame:HookScript("OnShow", function()
					Output:RedrawDebugMessages()
				end)
				self.debugFrame.gbankClassicHooked = true
			end

			self.debugFrame:Show()
			FCF_DockFrame(self.debugFrame)

			-- Restore General as the active tab so the debug frame isn't selected on the next reload
			FCF_SelectDockFrame(ChatFrame1)

			-- Initial draw of buffered messages
			self:RedrawDebugMessages()

			GBCR.Addon:Print("GBankClassicDebug tab found and shown (ChatFrame"..i..")")

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
		GBCR.Addon:Print(GBCR.Globals:Colorize(colorRed, "Failed to create debug tab: no available chat frames"))
		GBCR.Addon:Print("Try using an existing chat frame instead")

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
	frame:SetMaxLines(Constants.LIMITS.MAX_BUFFER_SIZE)
	frame:SetFading(false)
	frame:SetTimeVisible(120)
	frame:SetIndentedWordWrap(false)

	-- Make visible and dock it
	frame:Show()
	FCF_DockFrame(frame)

	-- Restore General as the active tab so the debug frame isn't selected on the next reload
	FCF_SelectDockFrame(ChatFrame1)

	-- Hook OnShow to redraw messages when tab becomes visible
	if not frame.gbankClassicHooked then
		frame:HookScript("OnShow", function()
			Output:RedrawDebugMessages()
		end)
		frame.gbankClassicHooked = true
	end

	self.debugFrame = frame

	-- Initial draw of buffered messages
	self:RedrawDebugMessages()

	GBCR.Addon:Print("Created GBankClassicDebug chat tab (ChatFrame"..frameIndex..")")
	GBCR.Addon:Print("You can now right-click the tab to customize or close it")

	return true
end