local addonName, GBCR = ...

GBCR.Events = {}
local Events = GBCR.Events

local Globals = GBCR.Globals
local wipe = Globals.wipe
local hooksecurefunc = Globals.hooksecurefunc
local GuildRoster = Globals.GuildRoster
local IsInInstance = Globals.IsInInstance
local IsInRaid = Globals.IsInRaid
local MailFrame = Globals.MailFrame
local NewTimer = Globals.NewTimer
local IsInGuild = Globals.IsInGuild

local Constants = GBCR.Constants
local timerIntervals = Constants.TIMER_INTERVALS

function Events:SetShareTimer()
	if self.shareTimer then
		GBCR.Addon:CancelTimer(self.shareTimer)
		self.shareTimer = nil
	end
	self.shareTimer = GBCR.Addon:ScheduleTimer(function()
		Events:OnShareTimer()
	end, timerIntervals.VERSION_BROADCAST)
end

function Events:OnShareTimer()
	GBCR.Output:Debug("EVENTS", "OnShareTimer fired")
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "OnShareTimer: skipping (in instance or raid)")

		return
	end

	if GBCR.Guild.onlineMembersCount < 1 then
		GBCR.Output:Debug("EVENTS", "OnShareTimer: skipping (nobody else online)")

		return
	end

	GBCR.Protocol:Share("reply")
	self:SetShareTimer()
end

function Events:ClearGuildCaches()
	wipe(GBCR.Guild.onlineMembers)
	wipe(GBCR.Guild.onlineMembersThatAreGuildBankAlts)
	wipe(GBCR.Guild.banksCache)
	wipe(GBCR.Guild.guildMembersCache)
    GBCR.Guild.onlineMembersCount = 0
    GBCR.Guild.rosterRefreshNeeded = nil
    GBCR.Guild.canWeViewOfficerNotes = nil
end

function Events:RegisterEvent(event, callback)
	if not callback then
		callback = event
	end
    GBCR.Addon:RegisterEvent(event, function(...)
        self[callback](self, ...)
    end)
end

function Events:UnregisterEvent(...)
    GBCR.Addon:UnregisterEvent(...)
end

function Events:RegisterGuildBankAltEvents()
	GBCR.Output:Debug("EVENTS", "RegisterGuildBankAltEvents called (GBCR.Inventory.guildBankAltEventsRegistered=%s)", tostring(GBCR.Inventory.guildBankAltEventsRegistered))
	if GBCR.Inventory.guildBankAltEventsRegistered then
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
		GBCR.Output:Debug("DONATION", "AutoLootMailItem function fired")
		GBCR.Donations:ProcessDonation(mailId)
	end)

	-- When you manually click on a single mail attachment
	-- When you click "Open All" from the inbox
	hooksecurefunc("TakeInboxItem", function(mailId, attachmentIndex)
		GBCR.Output:Debug("DONATION", "TakeInboxItem function fired")
		GBCR.Donations:ProcessItemDonation(mailId, attachmentIndex)
	end)

	-- Any time money is taken from mails
	hooksecurefunc("TakeInboxMoney", function(mailId)
		GBCR.Output:Debug("DONATION", "TakeInboxMoney function fired")
		GBCR.Donations:ProcessMoneyDonation(mailId)
	end)

    GBCR.Inventory.guildBankAltEventsRegistered = true
end

function Events:RegisterEvents()
	GBCR.Output:Debug("EVENTS", "RegisterEvents called (GBCR.Inventory.eventsRegistered=%s)", tostring(GBCR.Inventory.eventsRegistered))
	if GBCR.Inventory.eventsRegistered then
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

    hooksecurefunc("ChatEdit_InsertLink", function(itemLink)
        GBCR.UI:OnInsertLink(itemLink)
    end)

	self:SetShareTimer()

    GBCR.Inventory.eventsRegistered = true
end

function Events:UnregisterGuildBankAltEvents()
	GBCR.Output:Debug("EVENTS", "UnregisterGuildBankAltEvents called (GBCR.Inventory.guildBankAltEventsRegistered=%s)", tostring(GBCR.Inventory.guildBankAltEventsRegistered))
	if not GBCR.Inventory.guildBankAltEventsRegistered then
		return
	end

    GBCR.Inventory.guildBankAltEventsRegistered = false

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
	GBCR.Output:Debug("EVENTS", "UnregisterEvents called (GBCR.Inventory.eventsRegistered=%s)", tostring(GBCR.Inventory.eventsRegistered))
	if not GBCR.Inventory.eventsRegistered then
		return
	end

    GBCR.Inventory.eventsRegistered = false

	-- For all players
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("PLAYER_GUILD_UPDATE")
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("MAIL_SHOW")
	self:UnregisterEvent("MAIL_CLOSED")

	-- For guild bank alts
	self:UnregisterGuildBankAltEvents()
end

-- Events for all players
function Events:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
	GBCR.Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD event fired (isInitialLogin=%s, isReloadingUi=%s)", tostring(isInitialLogin), tostring(isReloadingUi))
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD: skipping (in instance or raid)")

		return
	end

	if isReloadingUi == true then
		GBCR.Guild:GetNormalizedPlayer()
		GBCR.Guild.rosterRefreshNeeded = true
		GuildRoster()
	end
end

function Events:PLAYER_GUILD_UPDATE(_)
	GBCR.Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE event fired")
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE: skipping (in instance or raid)")

		return
	end

	GBCR.Guild.rosterRefreshNeeded = true
	GuildRoster()
end

function Events:GUILD_ROSTER_UPDATE(_, importantChange)
	GBCR.Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE event fired (importantChange=%s)", tostring(importantChange))
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE: skipping (in instance or raid)")

		return
	end

	-- TODO: to instantly enable/disable bank scanning upon add or removal of "gbank" in someone's note we could scan the full roster each GUILD_ROSTER_UPDATE event; is that worth it or do we just keep it limited to PLAYER_ENTERING_WORLD (/reload)
	-- When the loading screen has appeared, the player has joined a guild, rank promotions/demotions, or rank privileges (such as being able to view officer notes) changed
	-- if importantChange or GBCR.Guild.rosterRefreshNeeded then
		GBCR.Guild:VerifyOfficerNotePermissions()
		GBCR.Guild:RebuildGuildBankAltsRoster()
		GBCR.Options:InitGuildBankAltOptions()
		GBCR.UI:QueueUIRefresh()
	-- end

	-- Always update online status
	GBCR.Guild:RefreshOnlineMembersCache()
end

function Events:GUILD_RANKS_UPDATE(_)
	GBCR.Output:Debug("EVENTS", "GUILD_RANKS_UPDATE event fired")
	if not IsInGuild() then
		self:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: skipping (in instance or raid)")

		return
	end

	local guild = GBCR.Guild:GetGuildName()
	if not guild then
		return
	end

	if GBCR.Guild:Init(guild) then
		GBCR.Options:InitGuildBankAltOptions()

        -- GBCR.UI:QueueUIRefresh() -- TODO: is this really needed?
	end
end

function Events:PLAYER_REGEN_DISABLED(_)
	GBCR.Output:Debug("EVENTS", "PLAYER_REGEN_DISABLED event fired (GBCR.Options:GetCombatHide()=%s)", tostring(GBCR.Options:GetCombatHide()))
    if GBCR.Options:GetCombatHide() then
        GBCR.UI.Inventory:Close()
    end
end

function Events:MAIL_SHOW(_)
	GBCR.Output:Debug("EVENTS", "MAIL_SHOW event fired")
    GBCR.Inventory:OnUpdateStart()
	GBCR.Inventory.mailHasUpdated = true
	GBCR.Output:Debug("INVENTORY", "GBCR.Inventory.mailHasUpdated set to %s", tostring(GBCR.Inventory.mailHasUpdated))
    GBCR.Donations.isOpen = true
    GBCR.Donations:Check()

	if not MailFrame.isGBankHooked then
		MailFrame:HookScript("OnHide", function()
			GBCR.Output:Debug("INVENTORY", "MailFrame OnHide fired (mailbox closed)")
			Events:MAIL_CLOSED()
		end)
		MailFrame.isGBankHooked = true
		GBCR.Output:Debug("INVENTORY", "Hooked MailFrame OnHide")
	end
end

function Events:MAIL_CLOSED(_)
	GBCR.Output:Debug("EVENTS", "MAIL_CLOSED event fired")
    if GBCR.Donations.donationItemRegistry then
        wipe(GBCR.Donations.donationItemRegistry)
    end
    if GBCR.Donations.itemDonationVerificationQueue then
        wipe(GBCR.Donations.itemDonationVerificationQueue)
    end
	GBCR.Donations.isGoldDonationPending = nil
	GBCR.Donations.goldBalanceBeforeDonation = nil
    GBCR.Donations.isOpen = false
    GBCR.Inventory:OnUpdateStart()
    GBCR.Inventory:OnUpdateStop()
end

-- Events for guild bank alts
function Events:BAG_UPDATE_DELAYED(_)
	GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED event fired (bagUpdateTimer=%s, GBCR.Donations.isOpen=%s, isAuctionHouseClosed=%s)", tostring(self.bagUpdateTimer), tostring(GBCR.Donations.isOpen), tostring(self.isAuctionHouseClosed))

	if GBCR.Donations.isOpen == true then
		GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (mail is still open)")

		return
	end

	if self.isAuctionHouseClosed and self.isAuctionHouseClosed ~= true then
		GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (AH is still open)")

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (in instance or raid)")

		return
	end

	if self.bagUpdateTimer and not self.bagUpdateTimer:IsCancelled() then
   		self.bagUpdateTimer:Cancel()
        self.bagUpdateTimer = nil
    end

    self.bagUpdateTimer = NewTimer(timerIntervals.ALT_DATA_QUEUE_RETRY, function()
        GBCR.Output:Debug("EVENTS", "Debounced BAG_UPDATE_DELAYED timer fired")
		GBCR.Inventory:OnUpdateStart()
		GBCR.Inventory:OnUpdateStop()
        self.bagUpdateTimer = nil
    end)
end

function Events:BANKFRAME_OPENED(_)
    GBCR.Inventory:OnUpdateStart()
end

function Events:BANKFRAME_CLOSED(_)
    GBCR.Inventory:OnUpdateStop()
end

function Events:AUCTION_HOUSE_SHOW(_)
	GBCR.Output:Debug("EVENTS", "AUCTION_HOUSE_SHOW event fired")
	self.isAuctionHouseClosed = false
    GBCR.Inventory:OnUpdateStart()
end

function Events:AUCTION_HOUSE_CLOSED(_)
	GBCR.Output:Debug("EVENTS", "AUCTION_HOUSE_CLOSED event fired")
	self.isAuctionHouseClosed = true
    GBCR.Inventory:OnUpdateStop()
end

function Events:MERCHANT_SHOW(_)
    GBCR.Inventory:OnUpdateStart()
end

function Events:MERCHANT_CLOSED(_)
    GBCR.Inventory:OnUpdateStop()
end

function Events:TRADE_SHOW(_)
	GBCR.Inventory:OnUpdateStart()
end

function Events:TRADE_CLOSED(_)
	GBCR.Inventory:OnUpdateStop()
end

function Events:CHAT_MSG_LOOT(_, message)
	GBCR.Output:Debug("EVENTS", "CHAT_MSG_LOOT event fired")
	GBCR.Donations:ProcessPossibleItemDonation(message)
end

function Events:PLAYER_MONEY(_)
	GBCR.Output:Debug("EVENTS", "PLAYER_MONEY event fired")
	GBCR.Donations:ProcessPossibleMoneyDonation()
end