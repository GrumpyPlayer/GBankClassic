GBankClassic_Events = GBankClassic_Events or {}

local Events = GBankClassic_Events
local bagUpdateTimer = nil

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("hooksecurefunc", "GuildRoster", "IsInRaid", "MailFrame", "NewTimer")
local hooksecurefunc = upvalues.hooksecurefunc
local GuildRoster = upvalues.GuildRoster
local IsInRaid = upvalues.IsInRaid
local MailFrame = upvalues.MailFrame
local NewTimer = upvalues.NewTimer

function Events:RegisterEvent(event, callback)
	if not callback then
		callback = event
	end
    GBankClassic_Core:RegisterEvent(event, function(...)
        self[callback](self, ...)
    end)
end

function Events:UnregisterEvent(...)
    GBankClassic_Core:UnregisterEvent(...)
end

function Events:RegisterEvents()
	if GBankClassic_Bank.eventsRegistered then
		return
	end

	self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("GUILD_RANKS_UPDATE")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("BANKFRAME_CLOSED")
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_INBOX_UPDATE")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterEvent("TRADE_SHOW")
    self:RegisterEvent("TRADE_CLOSED")
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("MERCHANT_CLOSED")
    self:RegisterEvent("BAG_UPDATE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
	-- self:RegisterEvent("MAIL_SEND_SUCCESS")

    hooksecurefunc("ChatEdit_InsertLink", function(link)
        GBankClassic_UI:OnInsertLink(link)
    end)

	-- -- Hook MailFrame visibility changes directly for more reliable detection
	-- if MailFrame and not MailFrame.gbankHooked then
	-- 	MailFrame.gbankHooked = true
	-- 	MailFrame:HookScript("OnShow", function()
	-- 		GBankClassic_Mail.isOpen = true
	-- 		After(0.1, function()
	-- 			if GBankClassic_UI_Requests.isOpen then
	-- 				GBankClassic_UI_Requests:DrawContent()
	-- 			end
	-- 		end)
	-- 	end)
	-- 	MailFrame:HookScript("OnHide", function()
	-- 		GBankClassic_Mail.isOpen = false
	-- 		After(0.1, function()
	-- 			if GBankClassic_UI_Requests.isOpen then
	-- 				GBankClassic_UI_Requests:DrawContent()
	-- 			end
	-- 		end)
	-- 	end)
	-- end

	-- -- Hook the send mail tab to auto-open requests window for bank alts
	-- if MailFrameTab2 and not MailFrameTab2.gbankHooked then
	-- 	MailFrameTab2.gbankHooked = true
	-- 	MailFrameTab2:HookScript("OnClick", function()
	-- 		local player = GBankClassic_Guild:GetNormalizedPlayer()
	-- 		if player and GBankClassic_Guild:IsBank(player) then
	-- 			After(0.1, function()
	-- 				if GBankClassic_UI_Requests.isOpen then
	-- 					GBankClassic_UI_Requests:DrawContent()
	-- 				else
	-- 					GBankClassic_UI_Requests:Open()
	-- 				end
	-- 			end)
	-- 		end
	-- 	end)
	-- end

	self:SetTimer()
	self:SetShareTimer()

    GBankClassic_Bank.eventsRegistered = true
end

function Events:UnregisterEvents()
	if not GBankClassic_Bank.eventsRegistered then
		return
	end

    GBankClassic_Bank.eventsRegistered = false

	self:UnregisterEvent("PLAYER_LOGIN")
	self:UnregisterEvent("PLAYER_LOGOUT")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    self:UnregisterEvent("BANKFRAME_OPENED")
    self:UnregisterEvent("BANKFRAME_CLOSED")
    self:UnregisterEvent("MAIL_SHOW")
    self:UnregisterEvent("MAIL_INBOX_UPDATE")
    self:UnregisterEvent("MAIL_CLOSED")
    self:UnregisterEvent("TRADE_SHOW")
    self:UnregisterEvent("TRADE_CLOSED")
    self:UnregisterEvent("AUCTION_HOUSE_SHOW")
    self:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    self:UnregisterEvent("MERCHANT_SHOW")
    self:UnregisterEvent("MERCHANT_CLOSED")
    self:UnregisterEvent("BAG_UPDATE")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	-- self:UnregisterEvent("MAIL_SEND_SUCCESS")
end

function Events:SetTimer()
	GBankClassic_Core:ScheduleTimer(function(...)
		self:OnTimer()
	end, TIMER_INTERVALS.ROSTER_AND_ALT_SYNC)
end

function Events:OnTimer()
	self:Sync()
	self:SetTimer()
end

function Events:SetShareTimer()
	GBankClassic_Core:ScheduleTimer(function(...)
		self:OnShareTimer()
	end, TIMER_INTERVALS.VERSION_BROADCAST)
end

function Events:OnShareTimer()
	GBankClassic_Guild:Share("reply", "version")
	self:SetShareTimer()
end

function Events:Sync(priority)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	local version = GBankClassic_Guild:GetVersion()
	if version == nil then
		return
	end
	if version.roster == nil then
		return
	end

	local data = GBankClassic_Core:SerializeWithChecksum(version)
	-- Use provided priority or default to BULK for automatic timer-based syncs
	GBankClassic_Core:SendCommMessage("gbank-v", data, "Guild", nil, priority or "BULK")
end

-- Delta-specific version broadcast
-- Guild bankt alts send both gbank-dv (old) and gbank-dv2 (new) messages for compatibility
function Events:SyncDeltaVersion(priority)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	local version = GBankClassic_Guild:GetVersion()
	if version == nil then
		return
	end
	if version.roster == nil then
		return
	end

	-- Include guild bank alt status for pull-based protocol
	local player = GBankClassic_Guild:GetNormalizedPlayer()
	local isGuildBankAlt = player and GBankClassic_Guild:IsBank(player) or false
	version.isGuildBankAlt = isGuildBankAlt

	-- gbank-dv2 for new clients (with aggregated items hash)
	local data = GBankClassic_Core:SerializeWithChecksum(version)
	GBankClassic_Core:SendCommMessage("gbank-dv2", data, "Guild", nil, priority or "NORMAL")
	
	-- Old clients will compute hash from their legacy alt.bank/alt.bags structure
	-- New clients ignore gbank-dv, so no conflict
	GBankClassic_Core:SendCommMessage("gbank-dv", data, "Guild", nil, priority or "NORMAL")
end

function Events:PLAYER_LOGIN(_)
	GBankClassic_Guild:GetPlayer()
end

function Events:PLAYER_LOGOUT(_)
	-- Check if mail field exists before logout
	local player = GBankClassic_Guild:GetNormalizedPlayer()
	GBankClassic_Output:Debug("MAIL", "========================================")
	GBankClassic_Output:Debug("MAIL", "Checking mail at logout for: %s", player)
	if GBankClassic_Guild.Info and GBankClassic_Guild.Info.alts and GBankClassic_Guild.Info.alts[player] then
		local alt = GBankClassic_Guild.Info.alts[player]
		if alt.mail then
			local mailCount = alt.mail.items and #alt.mail.items or 0
			
			GBankClassic_Output:Debug("MAIL", "Mail field exists with %d items", mailCount)
			GBankClassic_Output:Debug("MAIL", "  version: %s (type: %s)", tostring(alt.mail.version), type(alt.mail.version))
			GBankClassic_Output:Debug("MAIL", "  lastScan: %s (type: %s)", tostring(alt.mail.lastScan), type(alt.mail.lastScan))
			GBankClassic_Output:Debug("MAIL", "  slots type: %s", type(alt.mail.slots))
			if alt.mail.slots then
				GBankClassic_Output:Debug("MAIL", "  slots.count: %s", tostring(alt.mail.slots.count))
			end
			-- Check for metatables or functions that would prevent serialization
			if getmetatable(alt.mail) then
				GBankClassic_Output:Debug("MAIL", "WARNING: alt.mail has a metatable!")
			end
		else
			GBankClassic_Output:Debug("MAIL", "Mail field missing!")
		end
	else
		GBankClassic_Output:Debug("MAIL", "Alt data not found")
	end
	GBankClassic_Output:Debug("MAIL", "========================================")
end

function Events:PLAYER_ENTERING_WORLD(_)
    -- Request initial guild roster update on world enter
	GuildRoster()
	
	-- Initialize cache immediately in case GUILD_ROSTER_UPDATE is delayed
	GBankClassic_Guild:RefreshOnlineCache()
end

function Events:GUILD_RANKS_UPDATE(_)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	-- Load guild data and perform a one-time cleanup of malformed alt entries
	if GBankClassic_Guild:Init(guild) then
		GBankClassic_Options:InitGuild()

		if IsInRaid() then
			GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: ignoring guild ranks cleanup (in raid)")

			return
		end
        
		local cleaned = GBankClassic_Guild:CleanupMalformedAlts()
		if cleaned and cleaned > 0 then
			GBankClassic_Output:Info("Cleaned %d malformed alt entries from saved database", cleaned)
		end
        
        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
        end
	end
end

function Events:GUILD_ROSTER_UPDATE(_)
    -- Refresh online members cache when roster updates
	GBankClassic_Guild:RefreshOnlineCache()
	-- Invalidate banks cache when roster updates
	GBankClassic_Guild:InvalidateBanksCache()
	-- Rebuild guild bank alts roster from guild notes (local only, no network communication)
	GBankClassic_Guild:RebuildGuildBankAltsRoster()
	-- Clear delta error counters for offline players
	GBankClassic_DeltaComms:ClearOfflineErrorCounters(GBankClassic_Guild.Info and GBankClassic_Guild.Info.name)
	-- -- Refresh the requests UI to update guild bank alt controls (like highlight checkbox)
	-- GBankClassic_Guild:RefreshRequestsUI()
end

function Events:BANKFRAME_OPENED(_)
    GBankClassic_Bank:OnUpdateStart()
end

function Events:BANKFRAME_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function Events:MAIL_SHOW(_)
	GBankClassic_Output:Debug("MAIL", "MAIL_SHOW event fired")
    GBankClassic_Bank:OnUpdateStart()
	GBankClassic_MailInventory.hasUpdated = true
	GBankClassic_Output:Debug("MAIL", "MailInventory.hasUpdated set to %s", tostring(GBankClassic_MailInventory.hasUpdated))
    GBankClassic_Mail.isOpen = true
	-- GBankClassic_Mail:InitSendHook()
    GBankClassic_Mail:Check()
	
	-- Hook MailFrame OnHide to detect when mail closes (MAIL_CLOSED event may not fire reliably)
	if not MailFrame.GBankHooked then
		MailFrame:HookScript("OnHide", function()
			GBankClassic_Output:Debug("MAIL", "MailFrame OnHide fired (mailbox closed)")
			self:MAIL_CLOSED()
		end)
		MailFrame.GBankHooked = true
		GBankClassic_Output:Debug("MAIL", "Hooked MailFrame OnHide")
	end
end

function Events:MAIL_INBOX_UPDATE(_)
    GBankClassic_Mail:Scan()
end

function Events:MAIL_CLOSED(_)
	GBankClassic_Output:Debug("MAIL", "MAIL_CLOSED event fired")
    GBankClassic_Mail.isOpen = false
    GBankClassic_Mail.isScanning = false
	GBankClassic_Output:Debug("MAIL", "Calling Bank:OnUpdateStop()")
    GBankClassic_Bank:OnUpdateStop()
	GBankClassic_Output:Debug("MAIL", "Bank:OnUpdateStop() completed")
    GBankClassic_UI_Mail:Close()
	-- -- Refresh requests UI to update fulfill button states
	-- -- Delay slightly to ensure MailFrame state is updated
	-- After(0.1, function()
	-- 	if GBankClassic_UI_Requests.isOpen then
	-- 		GBankClassic_UI_Requests:DrawContent()
	-- 	end
	-- end)
end

-- function Events:MAIL_SEND_SUCCESS(_)
-- 	GBankClassic_Output:Debug("MAIL", "MAIL_SEND_SUCCESS event fired")
-- 	-- Safety: ensure hook is registered when mail UI is opened
-- 	GBankClassic_Mail:InitSendHook()
-- 	GBankClassic_Mail:ApplyPendingSend()
-- end

function Events:TRADE_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
end

function Events:TRADE_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function Events:AUCTION_HOUSE_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
end

function Events:AUCTION_HOUSE_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function Events:MERCHANT_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
end

function Events:MERCHANT_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function Events:BAG_UPDATE(_)
    if bagUpdateTimer then
		return
	end
	
    bagUpdateTimer = NewTimer(5, function()
		GBankClassic_Bank:OnUpdateStart()
		GBankClassic_Bank:OnUpdateStop()
        bagUpdateTimer = nil
    end)
end

function Events:PLAYER_REGEN_DISABLED(_)
    if GBankClassic_Options:GetCombatHide() then
        GBankClassic_UI_Inventory:Close()
    end
end