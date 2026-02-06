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

	-- For all players
	self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("GUILD_RANKS_UPDATE")
	self:RegisterEvent("GUILD_ROSTER_UPDATE")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
	-- self:RegisterEvent("MAIL_SEND_SUCCESS")

	-- For guild bank alts
	local player = GBankClassic_Guild:GetNormalizedPlayer()
	if GBankClassic_Guild:IsBank(player) then
		self:RegisterEvent("BAG_UPDATE")
		self:RegisterEvent("BANKFRAME_OPENED")
		self:RegisterEvent("BANKFRAME_CLOSED")
		self:RegisterEvent("AUCTION_HOUSE_SHOW")
		self:RegisterEvent("AUCTION_HOUSE_CLOSED")
		self:RegisterEvent("MERCHANT_SHOW")
		self:RegisterEvent("MERCHANT_CLOSED")
		self:RegisterEvent("TRADE_SHOW")
		self:RegisterEvent("TRADE_CLOSED")
		self:RegisterEvent("CHAT_MSG_LOOT")
		self:RegisterEvent("PLAYER_MONEY")

		-- When you shift-click a mail from the inbox
		hooksecurefunc("AutoLootMailItem", function(mailId)
			GBankClassic_Output:Debug("DONATION", "AutoLootMailItem function fired")
			GBankClassic_Mail:ProcessDonation(mailId)
		end)

		-- When you manually click on a single mail attachment
		-- When you click "Open All" from the inbox
		hooksecurefunc("TakeInboxItem", function(mailId, attachmentIndex)
			GBankClassic_Output:Debug("DONATION", "TakeInboxItem function fired")
			GBankClassic_Mail:ProcessItemDonation(mailId, attachmentIndex)
		end)

		-- Any time money is taken from mails
		hooksecurefunc("TakeInboxMoney", function(mailId)
			GBankClassic_Output:Debug("DONATION", "TakeInboxMoney function fired")
			GBankClassic_Mail:ProcessMoneyDonation(mailId)
		end)
	end

    hooksecurefunc("ChatEdit_InsertLink", function(link)
        GBankClassic_UI:OnInsertLink(link)
    end)

	-- -- Hook MailFrame visibility changes directly for more reliable detection
	-- if MailFrame and not MailFrame.isGBankHooked then
	-- 	MailFrame.isGBankHooked = true
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
	-- if MailFrameTab2 and not MailFrameTab2.isGBankHooked then
	-- 	MailFrameTab2.isGBankHooked = true
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

	-- For all players
	self:UnregisterEvent("PLAYER_LOGIN")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("MAIL_SHOW")
	self:UnregisterEvent("MAIL_CLOSED")
	-- self:UnregisterEvent("MAIL_SEND_SUCCESS")

	-- For guild bank alts
	if GBankClassic_Guild:IsBank() then
		self:UnregisterEvent("BAG_UPDATE")
		self:UnregisterEvent("BANKFRAME_OPENED")
		self:UnregisterEvent("BANKFRAME_CLOSED")
		self:UnregisterEvent("AUCTION_HOUSE_SHOW")
		self:UnregisterEvent("AUCTION_HOUSE_CLOSED")
		self:UnregisterEvent("MERCHANT_SHOW")
		self:UnregisterEvent("MERCHANT_CLOSED")
		self:UnregisterEvent("TRADE_SHOW")
		self:UnregisterEvent("TRADE_CLOSED")
		self:UnregisterEvent("CHAT_MSG_LOOT")
		self:UnregisterEvent("PLAYER_MONEY")
	end
end

-- For all players
function Events:PLAYER_LOGIN(_)
	GBankClassic_Guild:GetPlayer()
end

function Events:PLAYER_ENTERING_WORLD(_)
	GuildRoster()
	GBankClassic_Guild:RefreshOnlineCache()
end

function Events:GUILD_RANKS_UPDATE(_)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	if GBankClassic_Guild:Init(guild) then
		GBankClassic_Options:InitGuild()

		if IsInRaid() then
			GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: ignoring guild ranks cleanup (in raid)")

			return
		end
        
		local cleaned = GBankClassic_Guild:CleanupMalformedAlts()
		if cleaned and cleaned > 0 then
			GBankClassic_Output:Info("Cleaned %d malformed alt entries from saved database", cleaned)
			GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE:", "Cleaned %d malformed alt entries from saved database", cleaned)
		end
        
        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
        end
		if GBankClassic_UI_Donations.isOpen then
			GBankClassic_UI_Donations:DrawContent()
		end
	end
end

function Events:GUILD_ROSTER_UPDATE(_)
	GBankClassic_Guild:RefreshOnlineCache()
	GBankClassic_Guild:InvalidateBanksCache()
	GBankClassic_Guild:RebuildGuildBankAltsRoster()
	GBankClassic_DeltaComms:ClearOfflineErrorCounters(GBankClassic_Guild.Info and GBankClassic_Guild.Info.name)
	-- GBankClassic_Guild:RefreshRequestsUI()
end

function Events:PLAYER_REGEN_DISABLED(_)
    if GBankClassic_Options:GetCombatHide() then
        GBankClassic_UI_Inventory:Close()
    end
end

function Events:MAIL_SHOW(_)
	GBankClassic_Output:Debug("MAIL", "MAIL_SHOW event fired")

    GBankClassic_Bank:OnUpdateStart()
	GBankClassic_MailInventory.hasUpdated = true
	GBankClassic_Output:Debug("MAIL", "MailInventory.hasUpdated set to %s", tostring(GBankClassic_MailInventory.hasUpdated))
    GBankClassic_Mail.isOpen = true
	-- GBankClassic_Mail:InitSendHook()
    GBankClassic_Mail:Check()
	
	if not MailFrame.isGBankHooked then
		MailFrame:HookScript("OnHide", function()
			GBankClassic_Output:Debug("MAIL", "MailFrame OnHide fired (mailbox closed)")
			self:MAIL_CLOSED()
		end)
		MailFrame.isGBankHooked = true
		GBankClassic_Output:Debug("MAIL", "Hooked MailFrame OnHide")
	end
end

function Events:MAIL_CLOSED(_)
	GBankClassic_Output:Debug("MAIL", "MAIL_CLOSED event fired")

    if GBankClassic_Mail.donationItemRegistry then
        table.wipe(GBankClassic_Mail.donationItemRegistry)
    end
    if GBankClassic_Mail.itemDonationVerificationQueue then
        table.wipe(GBankClassic_Mail.itemDonationVerificationQueue)
    end
	GBankClassic_Mail.isGoldDonationPending = nil
	GBankClassic_Mail.goldBalanceBeforeDonation = nil
    GBankClassic_Mail.isOpen = false

	-- GBankClassic_Output:Debug("MAIL", "Calling Bank:OnUpdateStart()")
    -- GBankClassic_Bank:OnUpdateStart()
	-- GBankClassic_Output:Debug("MAIL", "Bank:OnUpdateStart() completed")
	GBankClassic_Output:Debug("MAIL", "Calling Bank:OnUpdateStop()")
    GBankClassic_Bank:OnUpdateStop()
	GBankClassic_Output:Debug("MAIL", "Bank:OnUpdateStop() completed")

    -- GBankClassic_UI_Mail:Close()
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
-- 	GBankClassic_Mail:InitSendHook()
-- 	GBankClassic_Mail:ApplyPendingSend()
-- end

-- For guild bank alts
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

function Events:BANKFRAME_OPENED(_)
    GBankClassic_Bank:OnUpdateStart()
end

function Events:BANKFRAME_CLOSED(_)
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

function Events:TRADE_SHOW(_)
	GBankClassic_Bank:OnUpdateStart()
end

function Events:TRADE_CLOSED(_)
	GBankClassic_Bank:OnUpdateStop()
end

function Events:CHAT_MSG_LOOT(_, message)
	GBankClassic_Output:Debug("DONATION", "CHAT_MSG_LOOT event fired")
	GBankClassic_Mail:ProcessPossibleItemDonation(message)
end

function Events:PLAYER_MONEY(_)
	GBankClassic_Output:Debug("DONATION", "PLAYER_MONEY event fired")
	GBankClassic_Mail:ProcessPossibleMoneyDonation()
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