local addonName, GBCR = ...

GBCR.Events = {}
local Events = GBCR.Events

local Globals = GBCR.Globals
local hooksecurefunc = Globals.hooksecurefunc
local tostring = Globals.tostring
local wipe = Globals.wipe

local GuildRoster = Globals.GuildRoster
local IsInGuild = Globals.IsInGuild
local IsInInstance = Globals.IsInInstance
local IsInRaid = Globals.IsInRaid
local MailFrame = Globals.MailFrame
local NewTimer = Globals.NewTimer

local Constants = GBCR.Constants
local timerIntervals = Constants.TIMER_INTERVALS

-- Helper to set and execute sharing of fingerprint data
local function setShareTimer(self)
	if self.shareTimer then
		GBCR.Addon:CancelTimer(self.shareTimer)

		self.shareTimer = nil
	end

	self.shareTimer = GBCR.Addon:ScheduleTimer(function()
		Events:OnShareTimer()
	end, timerIntervals.FINGERPRINT_BROADCAST)
end

-- Share fingerprint data when outside raid or instance and at least one other guild member is online
local function onShareTimer(self)
	GBCR.Output:Debug("EVENTS", "OnShareTimer fired")

	if not IsInGuild() then
		GBCR.Guild:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "OnShareTimer: skipping (in instance or raid)")

		return
	end

	if GBCR.Guild:GetOnlineMembersCount() <= 1 then
		GBCR.Output:Debug("EVENTS", "OnShareTimer: skipping (nobody else online)")

		return
	end

	GBCR.Protocol:Share("reply")

	setShareTimer(self)
end

-- Helper to register event listeners
local function registerEvent(self, event, callback)
    GBCR.Addon:RegisterEvent(event, function(...)
        self[callback and callback or event](self, ...)
    end)
end

-- Helper to unregister event listeners
local function unregisterEvent(self, ...)
    GBCR.Addon:UnregisterEvent(...)
end

-- Register event listeners specific to guild bank alts when enabling the addon
local function registerGuildBankAltEvents(self)
	GBCR.Output:Debug("EVENTS", "RegisterGuildBankAltEvents called (Events.guildBankAltEventsRegistered=%s)", tostring(Events.guildBankAltEventsRegistered))

	if Events.guildBankAltEventsRegistered then
		return
	end

	-- For guild bank alts
	registerEvent(self, "BAG_UPDATE_DELAYED")
	registerEvent(self, "BANKFRAME_OPENED")
	registerEvent(self, "BANKFRAME_CLOSED")
	registerEvent(self, "AUCTION_HOUSE_SHOW")
	registerEvent(self, "AUCTION_HOUSE_CLOSED")
	registerEvent(self, "MERCHANT_SHOW")
	registerEvent(self, "MERCHANT_CLOSED")
	registerEvent(self, "TRADE_SHOW")
	registerEvent(self, "TRADE_CLOSED")
	registerEvent(self, "CHAT_MSG_LOOT")
	registerEvent(self, "PLAYER_MONEY")

	-- When you shift-click a mail from the inbox
	hooksecurefunc("AutoLootMailItem", function(mailId)
		GBCR.Output:Debug("DONATIONS", "AutoLootMailItem function fired")
		GBCR.Donations:ProcessDonation(mailId)
	end)

	-- When you manually click on a single mail attachment
	-- When you click "Open All" from the inbox
	hooksecurefunc("TakeInboxItem", function(mailId, attachmentIndex)
		GBCR.Output:Debug("DONATIONS", "TakeInboxItem function fired")
		GBCR.Donations:ProcessItemDonation(mailId, attachmentIndex)
	end)

	-- Any time money is taken from mails
	hooksecurefunc("TakeInboxMoney", function(mailId)
		GBCR.Output:Debug("DONATIONS", "TakeInboxMoney function fired")
		GBCR.Donations:ProcessMoneyDonation(mailId)
	end)

    Events.guildBankAltEventsRegistered = true
end

-- Register all event listeners when enabling the addon
local function registerEvents(self)
	GBCR.Output:Debug("EVENTS", "RegisterEvents called (Events.eventsRegistered=%s)", tostring(Events.eventsRegistered))

	if Events.eventsRegistered then
		return
	end

	-- For all players
	registerEvent(self, "PLAYER_ENTERING_WORLD")
	registerEvent(self, "PLAYER_GUILD_UPDATE")
	registerEvent(self, "GUILD_ROSTER_UPDATE")
	registerEvent(self, "GUILD_RANKS_UPDATE")
	registerEvent(self, "PLAYER_REGEN_DISABLED")
	registerEvent(self, "MAIL_SHOW")
	registerEvent(self, "MAIL_CLOSED")

    hooksecurefunc("ChatEdit_InsertLink", function(itemLink)
        GBCR.UI:OnInsertLink(itemLink)
    end)

	setShareTimer(self)

    Events.eventsRegistered = true
end

-- Helper to unregister event listeners specific to guild bank alts when disabling the addon
local function unregisterGuildBankAltEvents(self)
	GBCR.Output:Debug("EVENTS", "UnregisterGuildBankAltEvents called (Events.guildBankAltEventsRegistered=%s)", tostring(Events.guildBankAltEventsRegistered))

	if not Events.guildBankAltEventsRegistered then
		return
	end

    Events.guildBankAltEventsRegistered = false

	-- For guild bank alts
	unregisterEvent(self, "BAG_UPDATE_DELAYED")
	unregisterEvent(self, "BANKFRAME_OPENED")
	unregisterEvent(self, "BANKFRAME_CLOSED")
	unregisterEvent(self, "AUCTION_HOUSE_SHOW")
	unregisterEvent(self, "AUCTION_HOUSE_CLOSED")
	unregisterEvent(self, "MERCHANT_SHOW")
	unregisterEvent(self, "MERCHANT_CLOSED")
	unregisterEvent(self, "TRADE_SHOW")
	unregisterEvent(self, "TRADE_CLOSED")
	unregisterEvent(self, "CHAT_MSG_LOOT")
	unregisterEvent(self, "PLAYER_MONEY")
end

-- Unregister all event listeners when disabling the addon
local function unregisterEvents(self)
	GBCR.Output:Debug("EVENTS", "UnregisterEvents called (Events.eventsRegistered=%s)", tostring(Events.eventsRegistered))

	if not Events.eventsRegistered then
		return
	end

    Events.eventsRegistered = false

	-- For all players
	unregisterEvent(self, "PLAYER_ENTERING_WORLD")
	unregisterEvent(self, "PLAYER_GUILD_UPDATE")
	unregisterEvent(self, "GUILD_ROSTER_UPDATE")
	unregisterEvent(self, "GUILD_RANKS_UPDATE")
	unregisterEvent(self, "PLAYER_REGEN_DISABLED")
	unregisterEvent(self, "MAIL_SHOW")
	unregisterEvent(self, "MAIL_CLOSED")

	-- For guild bank alts
	unregisterGuildBankAltEvents(self)
end

-- Export functions for other modules
Events.OnShareTimer = onShareTimer
Events.RegisterGuildBankAltEvents = registerGuildBankAltEvents
Events.RegisterEvents = registerEvents
Events.UnregisterEvents = unregisterEvents

-- Events for all players
function Events:PLAYER_ENTERING_WORLD(self, isInitialLogin, isReloadingUi)
	GBCR.Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD event fired (isInitialLogin=%s, isReloadingUi=%s)", tostring(isInitialLogin), tostring(isReloadingUi))

	if not IsInGuild() then
		GBCR.Guild:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD: skipping (in instance or raid)")

		return
	end

	if isInitialLogin == true then
		if GBCR.Options:GetLogLevel() == GBCR.Constants.LOG_LEVEL.DEBUG.level then
			GBCR.UI.Debug:Open()
		end
	end

	if isReloadingUi == true then
		GBCR.Guild:GetNormalizedPlayer()
		GBCR.Guild.rosterRefreshNeeded = true
		GuildRoster()
	end

	GBCR.Donations:BuildDonationCache()
	GBCR.Search:MarkAllDirty()
end

function Events:PLAYER_GUILD_UPDATE()
	GBCR.Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE event fired")

	if not IsInGuild() then
		GBCR.Guild:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE: skipping (in instance or raid)")

		return
	end

	GBCR.Guild.rosterRefreshNeeded = true
	GuildRoster()
end

function Events:GUILD_ROSTER_UPDATE(self, importantChange)
	GBCR.Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE event fired (importantChange=%s)", tostring(importantChange))

	if not IsInGuild() then
		GBCR.Guild:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE: skipping (in instance or raid)")

		return
	end

	-- TODO: to instantly enable/disable bank scanning upon add or removal of "gbank" in someone's note we could scan the full roster each GUILD_ROSTER_UPDATE event; is that worth it or do we just keep it limited to PLAYER_ENTERING_WORLD (/reload)

	-- When the loading screen has appeared, the player has joined a guild, rank promotions/demotions, or rank privileges (such as being able to view officer notes) changed
	-- if importantChange or GBCR.Guild.rosterRefreshNeeded then
		GBCR.Guild:RebuildGuildBankAltsRoster()
		-- GBCR.UI:QueueUIRefresh()
	-- end

	GBCR.Guild:RefreshOnlineMembersCache()
end

function Events:GUILD_RANKS_UPDATE()
	GBCR.Output:Debug("EVENTS", "GUILD_RANKS_UPDATE event fired")

	if not IsInGuild() then
		GBCR.Guild:ClearGuildCaches()

		return
	end

	if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: skipping (in instance or raid)")

		return
	end

	if GBCR.Guild:Init(GBCR.Guild:GetGuildInfo()) then
		GBCR.Options:InitGuildBankAltOptions()

        -- GBCR.UI:QueueUIRefresh() -- TODO: is this really needed?
	end
end

function Events:PLAYER_REGEN_DISABLED()
	GBCR.Output:Debug("EVENTS", "PLAYER_REGEN_DISABLED event fired (GBCR.Options:GetCombatHide()=%s)", tostring(GBCR.Options:GetCombatHide()))

    if GBCR.Options:GetCombatHide() then
        GBCR.UI.Inventory:Close()
    end
end

function Events:MAIL_SHOW()
	GBCR.Output:Debug("EVENTS", "MAIL_SHOW event fired")

    GBCR.Inventory:OnUpdateStart()
	GBCR.Inventory.mailHasUpdated = true
	GBCR.Output:Debug("INVENTORY", "GBCR.Inventory.mailHasUpdated set to %s", tostring(GBCR.Inventory.mailHasUpdated))

    GBCR.Donations.isOpen = true
    GBCR.Donations:Check()

	if not MailFrame.isGBCRHooked then
		MailFrame:HookScript("OnHide", function()
			Events:MAIL_CLOSED()

			GBCR.Output:Debug("INVENTORY", "MailFrame OnHide fired (mailbox closed)")
		end)
		MailFrame.isGBCRHooked = true

		GBCR.Output:Debug("INVENTORY", "Hooked MailFrame OnHide")
	end
end

function Events:MAIL_CLOSED()
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
function Events:BAG_UPDATE_DELAYED()
	GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED event fired (bagUpdateTimer=%s, GBCR.Donations.isOpen=%s, isAuctionHouseClosed=%s)", tostring(self.bagUpdateTimer), tostring(GBCR.Donations.isOpen), tostring(self.isAuctionHouseClosed))

	if GBCR.Donations.isOpen == true then
		GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (mail is still open)")

		return
	end

	if self.isAuctionHouseClosed == false then
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

    self.bagUpdateTimer = NewTimer(timerIntervals.BAG_UPDATE_QUIET_TIME, function()
        GBCR.Output:Debug("EVENTS", "Debounced BAG_UPDATE_DELAYED timer fired")

		GBCR.Inventory:OnUpdateStart()
		GBCR.Inventory:OnUpdateStop()
        self.bagUpdateTimer = nil
    end)
end

function Events:BANKFRAME_OPENED()
    GBCR.Inventory:OnUpdateStart()
end

function Events:BANKFRAME_CLOSED()
    GBCR.Inventory:OnUpdateStop()
end

function Events:AUCTION_HOUSE_SHOW()
	GBCR.Output:Debug("EVENTS", "AUCTION_HOUSE_SHOW event fired")

	self.isAuctionHouseClosed = false
    GBCR.Inventory:OnUpdateStart()
end

function Events:AUCTION_HOUSE_CLOSED()
	GBCR.Output:Debug("EVENTS", "AUCTION_HOUSE_CLOSED event fired")

	self.isAuctionHouseClosed = true
    GBCR.Inventory:OnUpdateStop()
end

function Events:MERCHANT_SHOW()
    GBCR.Inventory:OnUpdateStart()
end

function Events:MERCHANT_CLOSED()
    GBCR.Inventory:OnUpdateStop()
end

function Events:TRADE_SHOW()
	GBCR.Inventory:OnUpdateStart()
end

function Events:TRADE_CLOSED()
	GBCR.Inventory:OnUpdateStop()
end

function Events:CHAT_MSG_LOOT(_, message)
	GBCR.Output:Debug("EVENTS", "CHAT_MSG_LOOT event fired")

	GBCR.Donations:ProcessPossibleItemDonation(message)
end

function Events:PLAYER_MONEY()
	GBCR.Output:Debug("EVENTS", "PLAYER_MONEY event fired")

	GBCR.Donations:ProcessPossibleMoneyDonation()
end