GBankClassic_Events = GBankClassic_Events or {}

local Events = GBankClassic_Events
local bagUpdateTimer = nil

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("After", "wipe")
local After = upvalues.After
local wipe = upvalues.wipe
local upvalues = Globals.GetUpvalues("hooksecurefunc", "GuildRoster", "IsInRaid", "MailFrame", "NewTimer", "GetTime", "IsInGuild")
local hooksecurefunc = upvalues.hooksecurefunc
local GuildRoster = upvalues.GuildRoster
local IsInRaid = upvalues.IsInRaid
local MailFrame = upvalues.MailFrame
local NewTimer = upvalues.NewTimer
local IsInGuild = upvalues.IsInGuild

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

function Events:RegisterGuildBankAltEvents()
	if GBankClassic_Bank.guildBankAltEventsRegistered then
		return
	end

	-- For guild bank alts
	self:RegisterEvent("BAG_UPDATE_DELAYED")
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

	-- -- Hook the send mail tab to auto-open requests window for bank alts
	-- if MailFrameTab2 and not MailFrameTab2.isGBankHooked then
	-- 	MailFrameTab2.isGBankHooked = true
	-- 	MailFrameTab2:HookScript("OnClick", function()
	-- 		local player = GBankClassic_Guild:GetNormalizedPlayer()
	-- 		if player and GBankClassic_Guild:IsGuildBankAlt(player) then
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

    GBankClassic_Bank.guildBankAltEventsRegistered = true
end

function Events:RegisterEvents()
	if GBankClassic_Bank.eventsRegistered then
		return
	end

	-- For all players
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_GUILD_UPDATE")
	self:RegisterEvent("GUILD_ROSTER_UPDATE")
	self:RegisterEvent("GUILD_RANKS_UPDATE")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
	-- self:RegisterEvent("MAIL_SEND_SUCCESS")

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

	self:SetShareTimer()

    GBankClassic_Bank.eventsRegistered = true
end

function Events:UnregisterGuildBankAltEvents()
	if not GBankClassic_Bank.guildBankAltEventsRegistered then
		return
	end

    GBankClassic_Bank.guildBankAltEventsRegistered = false

	-- For guild bank alts
	self:UnregisterEvent("BAG_UPDATE_DELAYED")
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

function Events:UnregisterEvents()
	if not GBankClassic_Bank.eventsRegistered then
		return
	end

    GBankClassic_Bank.eventsRegistered = false

	-- For all players
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("PLAYER_GUILD_UPDATE")
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("MAIL_SHOW")
	self:UnregisterEvent("MAIL_CLOSED")
	-- self:UnregisterEvent("MAIL_SEND_SUCCESS")

	-- For guild bank alts
	self:UnregisterGuildBankAltEvents()
end

-- For all players
function Events:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
	GBankClassic_Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD event fired (isInitialLogin=%s, isReloadingUi=%s)", tostring(isInitialLogin), tostring(isReloadingUi))
	if isInitialLogin then
		GBankClassic_Guild:CleanupMalformedAlts()
		GBankClassic_Guild:ShareAddonVersionData()
	end
	if IsInGuild() then
		GBankClassic_Guild.rosterRefreshNeeded = true
		GBankClassic_Guild:GetNormalizedPlayer()
		GuildRoster()
	else
		self:ClearGuildCaches()
	end
end

function Events:PLAYER_GUILD_UPDATE(_)
	if IsInGuild() then
		GBankClassic_Guild.rosterRefreshNeeded = true
		GuildRoster()
	else
		self:ClearGuildCaches()
	end
end

function Events:GUILD_ROSTER_UPDATE(_, importantChange)
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	-- When the loading screen has appeared, the player has joined a guild, rank promotions/demotions, or rank privileges (such as being able to view officer notes) changed
	if importantChange or GBankClassic_Guild.rosterRefreshNeeded then
		GBankClassic_Guild:VerifyOfficerNotePermissions()
		GBankClassic_Guild:RebuildGuildBankAltsRoster()
	end

	-- Always update online status
	GBankClassic_Guild:RefreshOnlineMembersCache()

	GBankClassic_DeltaComms:ClearOfflineErrorCounters(GBankClassic_Guild.Info and GBankClassic_Guild.Info.name)

	-- GBankClassic_Guild:RefreshRequestsUI()
end

function Events:GUILD_RANKS_UPDATE(_)
	local guild = GBankClassic_Guild:GetGuildName()
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
			GBankClassic_Output:Info("Cleaned %d malformed guild bank alt entries from saved database.", cleaned)
			GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: cleaned %d malformed alt entries from saved database", cleaned)
		end
        
        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
			GBankClassic_UI_Inventory:RefreshCurrentTab()
        end
		if GBankClassic_UI_Donations.isOpen then
			GBankClassic_UI_Donations:DrawContent()
		end
	end
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
        wipe(GBankClassic_Mail.donationItemRegistry)
    end
    if GBankClassic_Mail.itemDonationVerificationQueue then
        wipe(GBankClassic_Mail.itemDonationVerificationQueue)
    end
	GBankClassic_Mail.isGoldDonationPending = nil
	GBankClassic_Mail.goldBalanceBeforeDonation = nil
    GBankClassic_Mail.isOpen = false

	GBankClassic_Output:Debug("MAIL", "Calling Bank:OnUpdateStart()")
    GBankClassic_Bank:OnUpdateStart()
	GBankClassic_Output:Debug("MAIL", "Bank:OnUpdateStart() completed")
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
function Events:BAG_UPDATE_DELAYED(_)
    if bagUpdateTimer then
		return
	end
	
    bagUpdateTimer = NewTimer(TIMER_INTERVALS.ALT_DATA_QUEUE_RETRY, function()
		GBankClassic_Output:Debug("INVENTORY", "Calling Bank:OnUpdateStart()")
		GBankClassic_Bank:OnUpdateStart()
		GBankClassic_Output:Debug("INVENTORY", "Bank:OnUpdateStart() completed")
		GBankClassic_Output:Debug("INVENTORY", "Calling Bank:OnUpdateStop()")
		GBankClassic_Bank:OnUpdateStop()
		GBankClassic_Output:Debug("INVENTORY", "Bank:OnUpdateStop() completed")
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

function Events:SetShareTimer()
	if self.shareTimer then
		GBankClassic_Core:CancelTimer(self.shareTimer)
		self.shareTimer = nil
	end
	self.shareTimer = GBankClassic_Core:ScheduleTimer(function(...)
		self:OnShareTimer()
	end, TIMER_INTERVALS.VERSION_BROADCAST)
end

function Events:OnShareTimer()
	GBankClassic_Output:Debug("EVENTS", "OnShareTimer fired")
	GBankClassic_Guild:Share("reply")
	self:SetShareTimer()
end

function Events:ClearGuildCaches()
	wipe(GBankClassic_Guild.onlineMembers)
	wipe(GBankClassic_Guild.onlineMembersThatAreGuildBankAlts)
	wipe(GBankClassic_Guild.banksCache)
	wipe(GBankClassic_Guild.guildMembersCache)
    GBankClassic_Guild.onlineMembersCount = 0
    GBankClassic_Guild.rosterRefreshNeeded = true
    GBankClassic_Guild.canWeViewOfficerNotes = nil
end