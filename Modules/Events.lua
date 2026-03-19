GBankClassic_Events = GBankClassic_Events or {}

local Events = GBankClassic_Events
local bagUpdateTimer = nil

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("wipe")
local wipe = upvalues.wipe
local upvalues = Globals.GetUpvalues("hooksecurefunc", "GuildRoster", "IsInInstance", "IsInRaid", "MailFrame", "NewTimer", "GetTime", "IsInGuild", "After")
local hooksecurefunc = upvalues.hooksecurefunc
local GuildRoster = upvalues.GuildRoster
local IsInInstance = upvalues.IsInInstance
local IsInRaid = upvalues.IsInRaid
local MailFrame = upvalues.MailFrame
local NewTimer = upvalues.NewTimer
local IsInGuild = upvalues.IsInGuild
local After = upvalues.After

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
	GBankClassic_Output:Debug("EVENTS", "RegisterGuildBankAltEvents called (GBankClassic_Bank.guildBankAltEventsRegistered=%s)", tostring(GBankClassic_Bank.guildBankAltEventsRegistered))
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
	GBankClassic_Output:Debug("EVENTS", "RegisterEvents called (GBankClassic_Bank.eventsRegistered=%s)", tostring(GBankClassic_Bank.eventsRegistered))
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
	GBankClassic_Output:Debug("EVENTS", "UnregisterGuildBankAltEvents called (GBankClassic_Bank.guildBankAltEventsRegistered=%s)", tostring(GBankClassic_Bank.guildBankAltEventsRegistered))
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
	GBankClassic_Output:Debug("EVENTS", "UnregisterEvents called (GBankClassic_Bank.eventsRegistered=%s)", tostring(GBankClassic_Bank.eventsRegistered))
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
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD: skipping (in instance or raid)")

		return
	end

	if isReloadingUi == true then
		GBankClassic_Guild:GetNormalizedPlayer()
		GBankClassic_Guild.rosterRefreshNeeded = true
		GuildRoster()
	end
end

function Events:PLAYER_GUILD_UPDATE(_)
	GBankClassic_Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE event fired")
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE: skipping (in instance or raid)")

		return
	end

	GBankClassic_Guild.rosterRefreshNeeded = true
	GuildRoster()
end

function Events:GUILD_ROSTER_UPDATE(_, importantChange)
	GBankClassic_Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE event fired (importantChange=%s)", tostring(importantChange))
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE: skipping (in instance or raid)")

		return
	end

	-- When the loading screen has appeared, the player has joined a guild, rank promotions/demotions, or rank privileges (such as being able to view officer notes) changed
	if importantChange or GBankClassic_Guild.rosterRefreshNeeded then
		GBankClassic_Guild:VerifyOfficerNotePermissions()
		GBankClassic_Guild:RebuildGuildBankAltsRoster()
	end

	-- Always update online status
	GBankClassic_Guild:RefreshOnlineMembersCache()

	-- GBankClassic_Guild:RefreshRequestsUI()
end

function Events:GUILD_RANKS_UPDATE(_)
	GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE event fired")
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: skipping (in instance or raid)")

		return
	end

	local guild = GBankClassic_Guild:GetGuildName()
	if not guild then
		return
	end

	if GBankClassic_Guild:Init(guild) then
		GBankClassic_Options:InitGuild()

		After(15, function()
			local cleaned = GBankClassic_Guild:CleanupDatabase()
			if cleaned and cleaned > 0 then
				GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: cleaned %d entries from database", cleaned)
			end
		end)

        GBankClassic_UI:RequestRefresh()
	end
end

function Events:PLAYER_REGEN_DISABLED(_)
	GBankClassic_Output:Debug("EVENTS", "PLAYER_REGEN_DISABLED event fired (GBankClassic_Options:GetCombatHide()=%s)", tostring(GBankClassic_Options:GetCombatHide()))
    if GBankClassic_Options:GetCombatHide() then
        GBankClassic_UI_Inventory:Close()
    end
end

function Events:MAIL_SHOW(_)
	GBankClassic_Output:Debug("EVENTS", "MAIL_SHOW event fired")
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
	GBankClassic_Output:Debug("EVENTS", "MAIL_CLOSED event fired")
    if GBankClassic_Mail.donationItemRegistry then
        wipe(GBankClassic_Mail.donationItemRegistry)
    end
    if GBankClassic_Mail.itemDonationVerificationQueue then
        wipe(GBankClassic_Mail.itemDonationVerificationQueue)
    end
	GBankClassic_Mail.isGoldDonationPending = nil
	GBankClassic_Mail.goldBalanceBeforeDonation = nil
    GBankClassic_Mail.isOpen = false
    -- GBankClassic_Mail.isScanning = false

    GBankClassic_Bank:OnUpdateStart()
    GBankClassic_Bank:OnUpdateStop()

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
	GBankClassic_Output:Debug("EVENTS", "BAG_UPDATE_DELAYED event fired (bagUpdateTimer=%s)", tostring(bagUpdateTimer))
    if bagUpdateTimer then
		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (in instance or raid)")

		return
	end

    bagUpdateTimer = NewTimer(TIMER_INTERVALS.ALT_DATA_QUEUE_RETRY, function()
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
	GBankClassic_Output:Debug("EVENTS", "CHAT_MSG_LOOT event fired")
	GBankClassic_Mail:ProcessPossibleItemDonation(message)
end

function Events:PLAYER_MONEY(_)
	GBankClassic_Output:Debug("EVENTS", "PLAYER_MONEY event fired")
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
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("EVENTS", "OnShareTimer: skipping (in instance or raid)")

		return
	end

	if GBankClassic_Guild.onlineMembersCount < 1 then
		GBankClassic_Output:Debug("EVENTS", "OnShareTimer: skipping (nobody else online)")

		return
	end

	GBankClassic_Guild:Share("reply")
	-- GBankClassic_Guild:QueryRequestsIndex(nil, "NORMAL")
	self:SetShareTimer()
end

function Events:ClearGuildCaches()
	wipe(GBankClassic_Guild.onlineMembers)
	wipe(GBankClassic_Guild.onlineMembersThatAreGuildBankAlts)
	wipe(GBankClassic_Guild.banksCache)
	wipe(GBankClassic_Guild.guildMembersCache)
    GBankClassic_Guild.onlineMembersCount = 0
    GBankClassic_Guild.rosterRefreshNeeded = nil
    GBankClassic_Guild.canWeViewOfficerNotes = nil
end