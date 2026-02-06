GBankClassic_Output = GBankClassic_Output or {}

local Output = GBankClassic_Output

Output.level = LOG_LEVEL.INFO
Output.commDebug = false
Output.debugFrame = nil
Output.debugMessageBuffer = {}
Output.maxBufferSize = 1000

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("FCF_DockFrame", "FCF_ResetChatWindows", "FCF_SetLocked", "FCF_SetWindowColor", "FCF_SetWindowName", "GetChatWindowInfo", "ChatFrame_RemoveAllMessageGroups", "ChatFrame_RemoveAllChannels")
local FCF_DockFrame = upvalues.FCF_DockFrame
local FCF_ResetChatWindows = upvalues.FCF_ResetChatWindows
local FCF_SetLocked = upvalues.FCF_SetLocked
local FCF_SetWindowColor = upvalues.FCF_SetWindowColor
local FCF_SetWindowName = upvalues.FCF_SetWindowName
local GetChatWindowInfo = upvalues.GetChatWindowInfo
local ChatFrame_RemoveAllMessageGroups = upvalues.ChatFrame_RemoveAllMessageGroups
local ChatFrame_RemoveAllChannels = upvalues.ChatFrame_RemoveAllChannels
local upvalues = Globals.GetUpvalues("GameFontNormal")
local GameFontNormal = upvalues.GameFontNormal
local upvalues = Globals.GetUpvalues("NUM_CHAT_WINDOWS")
local NUM_CHAT_WINDOWS = upvalues.NUM_CHAT_WINDOWS

-- Category filtering helpers
function Output:IsCategoryEnabled(category)
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return false
	end

	return GBankClassic_Database.db.global.debugCategories[category] == true
end

function Output:SetCategoryEnabled(category, enabled)
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return
	end
	
	GBankClassic_Database.db.global.debugCategories[category] = enabled
end

function Output:EnableAllCategories()
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return
	end

	for category, _ in pairs(DEBUG_CATEGORY) do
		GBankClassic_Database.db.global.debugCategories[category] = true
	end
end

function Output:DisableAllCategories()
	if not GBankClassic_Database or not GBankClassic_Database.db then
		return
	end

	for category, _ in pairs(DEBUG_CATEGORY) do
		GBankClassic_Database.db.global.debugCategories[category] = false
	end
end

function Output:SetLevel(level)
	self.level = level
end

function Output:GetLevel()
	return self.level
end

function Output:SetCommDebug(enabled)
	self.commDebug = enabled
end

-- Store message in buffer
function Output:BufferDebugMessage(message)
	table.insert(self.debugMessageBuffer, message)

	-- Keep buffer size manageable
	while #self.debugMessageBuffer > self.maxBufferSize do
		table.remove(self.debugMessageBuffer, 1)
	end
end

-- Redraw all buffered messages to debug frame
function Output:RedrawDebugMessages()
	if not self.debugFrame then
		return
	end

	self.debugFrame:Clear()
	for _, msg in ipairs(self.debugMessageBuffer) do
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
					self:RedrawDebugMessages()
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
			self.debugFrame:SetMaxLines(1000)
			self.debugFrame:SetFading(false)
			FCF_SetLocked(self.debugFrame, false)
			-- Remove all message filters
			ChatFrame_RemoveAllMessageGroups(self.debugFrame)
			ChatFrame_RemoveAllChannels(self.debugFrame)

			-- Hook OnShow to redraw messages when tab becomes visible
			if not self.debugFrame.gbankClassicHooked then
				self.debugFrame:HookScript("OnShow", function()
					self:RedrawDebugMessages()
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
			self:RedrawDebugMessages()
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
function Output:RemoveDebugTab()
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
local function log(level, prefix, fmt, ...)
	if level < Output.level and level ~= LOG_LEVEL.RESPONSE then
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
	if level == LOG_LEVEL.DEBUG then
		local debugFrame = Output:GetDebugFrame()
		if debugFrame then
			local fullMessage = "GBankClassic: "
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
		GBankClassic_Core:Print(prefix, message)
	else
		GBankClassic_Core:Print(message)
	end

	return true
end

-- Development/troubleshooting details
function Output:Debug(fmt, ...)
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
		
		return log(LOG_LEVEL.DEBUG, "|cff888888[DEBUG]|r", actualFmt, unpack(args))
	end
	
	-- Fallback: no category specified
	return log(LOG_LEVEL.DEBUG, "|cff888888[DEBUG]|r", fmt, ...)
end

-- DebugComm: protocol communication details (controlled by COMMS category)
function Output:DebugComm(fmt, ...)
	-- Only show if debug level is active and the COMMS category is enabled
	if Output.level < LOG_LEVEL.DEBUG then
		return false
	end
	-- Check if COMMS category is enabled
	if not self:IsCategoryEnabled("COMMS") then
		return false
	end
	
	return log(LOG_LEVEL.DEBUG, "|cff888888[DEBUG] (comm)|r", fmt, ...)
end

-- Info: sync status, normal operations
function Output:Info(fmt, ...)
	return log(LOG_LEVEL.INFO, nil, fmt, ...)
end

-- Warn: something unexpected but recoverable
function Output:Warn(fmt, ...)
	return log(LOG_LEVEL.WARN, "|cffffcc00[WARN]|r", fmt, ...)
end

-- Error: something failed
function Output:Error(fmt, ...)
	return log(LOG_LEVEL.ERROR, "|cffff4444[ERROR]|r", fmt, ...)
end

-- Response: response to user commands (always shown)
function Output:Response(fmt, ...)
	return log(LOG_LEVEL.RESPONSE, nil, fmt, ...)
end