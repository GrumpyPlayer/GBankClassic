local addonName, GBCR = ...

GBCR.Events = {}
local Events = GBCR.Events

Events.tooltipSortBuffer = {}

local Globals = GBCR.Globals
local hooksecurefunc = Globals.hooksecurefunc
local next = Globals.next
local pairs = Globals.pairs
local string_match = Globals.string_match
local table_sort = Globals.table_sort
local tonumber = Globals.tonumber
local tostring = Globals.tostring
local wipe = Globals.wipe

local After = Globals.After
local GameTooltip = Globals.GameTooltip
local GetContainerItemInfo = Globals.GetContainerItemInfo
local GetPlayerTradeMoney = Globals.GetPlayerTradeMoney
local GetTargetTradeMoney = Globals.GetTargetTradeMoney
local GuildRoster = Globals.GuildRoster
local IsAltKeyDown = Globals.IsAltKeyDown
local IsControlKeyDown = Globals.IsControlKeyDown
local IsInGuild = Globals.IsInGuild
local IsInInstance = Globals.IsInInstance
local IsInRaid = Globals.IsInRaid
local IsShiftKeyDown = Globals.IsShiftKeyDown
local MailFrame = Globals.MailFrame
local NewTimer = Globals.NewTimer
local UnitName = Globals.UnitName

local tradeBagFull = Globals.ERR_TRADE_BAG_FULL
local tradeCancelled = Globals.ERR_TRADE_CANCELLED
local tradeComplete = Globals.ERR_TRADE_COMPLETE
local tradeTargetBagFull = Globals.ERR_TRADE_TARGET_BAG_FULL
local tradeTargetMaxExceeded = Globals.ERR_TRADE_TARGET_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS

local Constants = GBCR.Constants
local timerIntervals = Constants.TIMER_INTERVALS

local C_Container = Globals.C_Container

-- ================================================================================================
-- Register the hook to reset our custom state flag when no longer displaying the tooltip
GameTooltip:HookScript("OnTooltipCleared", function(self)
    GBCR.Output:Debug("EVENTS", "OnTooltipCleared function fired")

    self.tooltipProcessedByGBCR = nil
end)

-- Register the hook to display bank inventory in the tooltop
GameTooltip:HookScript("OnTooltipSetItem", function(self)
    GBCR.Output:Debug("EVENTS", "OnTooltipSetItem function fired")

    if self.tooltipProcessedByGBCR then
        return
    end

    local sources = self.pendingSourcesForGBCR
    if not sources then
        local _, itemLink = self:GetItem()
        if itemLink then
            local itemID = tonumber(string_match(itemLink, "|Hitem:(%d+):"))
            if itemID and GBCR.Inventory.cachedSourcesPerItem then
                sources = GBCR.Inventory.cachedSourcesPerItem[itemID]
            end
        end
    end

    if not sources then
        return
    end

    local count = 0
    for altName in pairs(sources) do
        count = count + 1
        Events.tooltipSortBuffer[count] = altName
    end

    if count == 0 then
        return
    end

    self.tooltipProcessedByGBCR = true

    for i = count + 1, #Events.tooltipSortBuffer do
        Events.tooltipSortBuffer[i] = nil
    end
    table_sort(Events.tooltipSortBuffer)

    self:AddLine(" ")
    self:AddLine(Globals.ColorizeText(Constants.COLORS.GREEN, GBCR.Core.addonTitle))

    local show = IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown()
    local total = 0
    for i = 1, count do
        local altName = Events.tooltipSortBuffer[i]
        local qty = sources[altName]
        total = total + qty

        if show then
            self:AddDoubleLine(altName, qty, 1, 1, 1, 1, 1, 1)
        end
    end

    if count >= 1 then
        self:AddDoubleLine(Globals.ColorizeText(Constants.COLORS.GOLD, "Total across all guild banks:"),
                           Globals.ColorizeText(Constants.COLORS.GOLD, tostring(total)))
    end
end)

-- ================================================================================================
-- Helper to register event listeners
local function registerEvent(self, event, callback)
    GBCR.Addon:RegisterEvent(event, function(...)
        self[callback and callback or event](self, ...)
    end)
end

-- Helper to unregister event listeners
local function unregisterEvent(...)
    GBCR.Addon:UnregisterEvent(...)
end

-- Helper wrapper for ledger events
local function hookLedgerEvent(apiTable, apiFuncName, ledgerAction)
    if type(apiTable) == "string" then
        ledgerAction = apiFuncName
        apiFuncName = apiTable
        apiTable = _G
    end

    hooksecurefunc(apiTable, apiFuncName, function(...)
        if not GBCR.Guild.weAreGuildBankAlt then
            return
        end

        GBCR.Output:Debug("LEDGER", apiFuncName .. " function fired")

        if type(ledgerAction) == "string" then
            GBCR.Ledger[ledgerAction](GBCR.Ledger, ...)
        elseif type(ledgerAction) == "function" then
            ledgerAction(...)
        end
    end)
end

-- Helper for vendor sell and destroy
local function captureContainerItem(bag, slot)
    local info = GetContainerItemInfo(bag, slot)
    if not info then
        return nil
    end

    return {
        itemString = (info.hyperlink and GBCR.Inventory:GetItemKey(info.hyperlink)) or tostring(info.itemID or 0),
        count = info.stackCount or 1
    }
end

-- Register event listeners specific to guild bank alts when enabling the addon
local function registerGuildBankAltEvents(self)
    GBCR.Output:Debug("EVENTS", "RegisterGuildBankAltEvents called (guildBankAltEventsRegistered=%s)",
                      tostring(Events.guildBankAltEventsRegistered))

    if Events.guildBankAltEventsRegistered then
        return
    end

    registerEvent(self, "BAG_UPDATE_DELAYED")
    registerEvent(self, "BANKFRAME_OPENED")
    registerEvent(self, "BANKFRAME_CLOSED")
    registerEvent(self, "AUCTION_HOUSE_SHOW")
    registerEvent(self, "AUCTION_HOUSE_CLOSED")
    registerEvent(self, "MERCHANT_SHOW")
    registerEvent(self, "MERCHANT_CLOSED")
    registerEvent(self, "TRADE_SHOW")
    registerEvent(self, "TRADE_MONEY_CHANGED")
    registerEvent(self, "TRADE_ACCEPT_UPDATE")
    registerEvent(self, "TRADE_PLAYER_ITEM_CHANGED")
    registerEvent(self, "TRADE_TARGET_ITEM_CHANGED")
    registerEvent(self, "TRADE_REQUEST_CANCEL")
    registerEvent(self, "TRADE_CLOSED")
    registerEvent(self, "UI_ERROR_MESSAGE")
    registerEvent(self, "GET_ITEM_INFO_RECEIVED")

    -- When you shift-click a mail from the inbox
    hookLedgerEvent("AutoLootMailItem", "OnAutoLootMailItem")

    -- When you manually click on a single mail attachment
    -- When you click "Open All" from the inbox
    hookLedgerEvent("TakeInboxItem", "OnTakeInboxItem")

    -- Any time money is taken from mails
    hookLedgerEvent("TakeInboxMoney", "OnTakeInboxMoney")

    -- Mail send
    hookLedgerEvent("SendMail", "OnSendMail")

    -- Vendor buy
    hookLedgerEvent("BuyMerchantItem", "OnBuyMerchantItem")

    -- Vendor sell: step 1
    hookLedgerEvent(C_Container, "UseContainerItem", function(bag, slot)
        if not Events.isMerchantOpen then
            return
        end

        Events.pendingVendorSellItem = captureContainerItem(bag, slot)
    end)

    -- Vendor sell: step 2
    hookLedgerEvent("SellCursorItem", "OnSellCursorItem")

    -- Destroy: step 1
    hookLedgerEvent(C_Container, "PickupContainerItem", function(bag, slot)
        Events.pendingCursorItem = captureContainerItem(bag, slot)
    end)

    -- Destroy: step 2
    hookLedgerEvent("DeleteCursorItem", "OnDeleteCursorItem")

    Events.guildBankAltEventsRegistered = true

    Events.myGuildRosterIndex = nil
end

-- Register all event listeners when enabling the addon
local function registerEvents(self)
    GBCR.Output:Debug("EVENTS", "RegisterEvents called (eventsRegistered=%s)", tostring(Events.eventsRegistered))

    if Events.eventsRegistered then
        return
    end

    -- For all players
    registerEvent(self, "PLAYER_ENTERING_WORLD")
    registerEvent(self, "PLAYER_LOGOUT")
    registerEvent(self, "PLAYER_GUILD_UPDATE")
    registerEvent(self, "GUILD_ROSTER_UPDATE")
    registerEvent(self, "GUILD_RANKS_UPDATE")
    registerEvent(self, "PLAYER_REGEN_DISABLED")
    registerEvent(self, "PLAYER_REGEN_ENABLED")
    registerEvent(self, "ZONE_CHANGED_NEW_AREA")
    registerEvent(self, "MAIL_SHOW")
    registerEvent(self, "MAIL_CLOSED")
    registerEvent(self, "MODIFIER_STATE_CHANGED")

    -- Drag an item into search
    hooksecurefunc("ChatEdit_InsertLink", function(itemLink)
        GBCR.Output:Debug("EVENTS", "ChatEdit_InsertLink function fired")

        GBCR.UI.Inventory:OnChatEdit_InsertLink(itemLink)
    end)

    Events.eventsRegistered = true
end

-- Helper to unregister event listeners specific to guild bank alts when disabling the addon
local function unregisterGuildBankAltEvents()
    GBCR.Output:Debug("EVENTS", "UnregisterGuildBankAltEvents called (guildBankAltEventsRegistered=%s)",
                      tostring(Events.guildBankAltEventsRegistered))

    if not Events.guildBankAltEventsRegistered then
        return
    end

    Events.guildBankAltEventsRegistered = false

    -- For guild bank alts
    unregisterEvent("BAG_UPDATE_DELAYED")
    unregisterEvent("BANKFRAME_OPENED")
    unregisterEvent("BANKFRAME_CLOSED")
    unregisterEvent("AUCTION_HOUSE_SHOW")
    unregisterEvent("AUCTION_HOUSE_CLOSED")
    unregisterEvent("MERCHANT_SHOW")
    unregisterEvent("MERCHANT_CLOSED")
    unregisterEvent("TRADE_SHOW")
    unregisterEvent("TRADE_MONEY_CHANGED")
    unregisterEvent("TRADE_ACCEPT_UPDATE")
    unregisterEvent("TRADE_PLAYER_ITEM_CHANGED")
    unregisterEvent("TRADE_TARGET_ITEM_CHANGED")
    unregisterEvent("TRADE_REQUEST_CANCEL")
    unregisterEvent("TRADE_CLOSED")
    unregisterEvent("UI_ERROR_MESSAGE")
    unregisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- Unregister all event listeners when disabling the addon
local function unregisterEvents(self)
    GBCR.Output:Debug("EVENTS", "UnregisterEvents called (eventsRegistered=%s)", tostring(Events.eventsRegistered))

    if not Events.eventsRegistered then
        return
    end

    Events.eventsRegistered = false

    -- For all players
    unregisterEvent("PLAYER_ENTERING_WORLD")
    unregisterEvent("PLAYER_LOGOUT")
    unregisterEvent("PLAYER_GUILD_UPDATE")
    unregisterEvent("GUILD_ROSTER_UPDATE")
    unregisterEvent("GUILD_RANKS_UPDATE")
    unregisterEvent("PLAYER_REGEN_DISABLED")
    unregisterEvent("PLAYER_REGEN_ENABLED")
    unregisterEvent("ZONE_CHANGED_NEW_AREA")
    unregisterEvent("MAIL_SHOW")
    unregisterEvent("MAIL_CLOSED")
    unregisterEvent("MODIFIER_STATE_CHANGED")

    -- For guild bank alts
    unregisterGuildBankAltEvents()
end

-- Helper to skip event execution unless in a guild and not in an instance or raid
local function shouldSkipGuildEvent(eventName)
    if not IsInGuild() then
        GBCR.Guild:ClearGuildCaches()

        return true
    end

    if IsInInstance() or IsInRaid() then
        GBCR.Output:Debug("EVENTS", "%s: skipping (in instance or raid)", eventName)

        return true
    end

    return false
end

-- Helper to compress data upon logging out
local function compressAltField(altData, field, compressedField)
    local data = altData[field]
    if not data or type(data) ~= "table" then
        return
    end

    if next(data) ~= nil then
        altData[compressedField] = GBCR.Database.CompressData(data)
    else
        altData[compressedField] = nil
    end
    altData[field] = nil
end

-- ================================================================================================
-- Export functions for other modules
Events.RegisterGuildBankAltEvents = registerGuildBankAltEvents
Events.RegisterEvents = registerEvents
Events.UnregisterEvents = unregisterEvents

-- ================================================================================================
-- Events for all players
function Events:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
    GBCR.Output:Debug("EVENTS", "PLAYER_ENTERING_WORLD event fired (isInitialLogin=%s, isReloadingUi=%s)",
                      tostring(isInitialLogin), tostring(isReloadingUi))

    GBCR.Protocol:UpdateSafetyLockout()

    if shouldSkipGuildEvent("PLAYER_ENTERING_WORLD") then
        return
    end

    if isInitialLogin == true then
        if GBCR.Options:GetLogLevel() == Constants.LOG_LEVEL.DEBUG.level then
            GBCR.UI.Debug:Open()
        end
    end

    if isReloadingUi == true then
        GBCR.Guild:GetNormalizedPlayerName()
        GBCR.Guild.guildRosterRefreshNeeded = true
        GuildRoster()
    end

    if isInitialLogin or isReloadingUi then
        GBCR.Protocol:SendStateHash()
    end

    GBCR.UI.Inventory:MarkAllDirty()
    GBCR.Guild.weAreGuildBankAlt = nil

    After(Constants.TIMER_INTERVALS.NEW_SESSION_WARN_DELAY, function()
        if GBCR.Guild.weAreGuildBankAlt then
            local db = GBCR.Database.savedVariables
            local myName = GBCR.Guild:GetNormalizedPlayerName()
            local myData = db and db.alts and db.alts[myName]
            if not myData or not myData.items or #myData.items == 0 then
                GBCR.Output:Response(Globals.ColorizeText(Constants.COLORS.ORANGE, "Action required!") ..
                                         " You are a guild bank alt, but your local inventory data is empty. Please visit a bank and mailbox to record your items!")
            end
        end
    end)
end

function Events:PLAYER_LOGOUT()
    GBCR.Output:Debug("EVENTS", "PLAYER_LOGOUT event fired")

    local sv = GBCR.Database.savedVariables
    if not sv or not sv.alts then
        return
    end

    for _, altData in pairs(sv.alts) do
        compressAltField(altData, "items", "itemsCompressed")
        compressAltField(altData, "cache", "cacheCompressed")
        compressAltField(altData, "ledger", "ledgerCompressed")
    end
end

function Events:PLAYER_GUILD_UPDATE()
    GBCR.Output:Debug("EVENTS", "PLAYER_GUILD_UPDATE event fired")

    if shouldSkipGuildEvent("PLAYER_GUILD_UPDATE") then
        return
    end

    GBCR.Guild.guildRosterRefreshNeeded = true
    GuildRoster()
end

function Events:GUILD_ROSTER_UPDATE(_, importantChange)
    GBCR.Output:Debug("EVENTS", "GUILD_ROSTER_UPDATE event fired (importantChange=%s)", tostring(importantChange))

    if shouldSkipGuildEvent("GUILD_ROSTER_UPDATE") then
        return
    end

    GBCR.Guild:AreWeGuildBankAlt()
    GBCR.Guild:RebuildGuildRosterInfo()
    GBCR.UI:QueueUIRefresh()

    if not self.timerRefreshOnlineMembersCache then
        GBCR.Guild:RefreshOnlineMembersCache()
        self.timerRefreshOnlineMembersCache = NewTimer(Constants.TIMER_INTERVALS.ONLINE_CACHE_REFRESH, function()
            self.timerRefreshOnlineMembersCache = nil
            GBCR.Guild:RefreshOnlineMembersCache()
        end)
    end
end

function Events:GUILD_RANKS_UPDATE()
    GBCR.Output:Debug("EVENTS", "GUILD_RANKS_UPDATE event fired")

    if shouldSkipGuildEvent("GUILD_RANKS_UPDATE") then
        return
    end

    if next(GBCR.Guild.cachedGuildMembers) then
        GBCR.Guild.weCanViewOfficerNotes = Globals.CanViewOfficerNote()
        GBCR.Guild.weCanEditOfficerNotes = Globals.CanEditOfficerNote()
        GBCR.Guild:IsAnyoneAuthority()
        GBCR.UI.Inventory.lastKnownBankAltState = nil
        GBCR.UI.Inventory.lastKnownOfficerState = nil
        GBCR.Options.InitGuildBankAltOptions()
        GBCR.UI:QueueUIRefresh()
    elseif GBCR.Guild.isGuildRosterRebuilding or GBCR.Guild.timerRebuildGuildRosterInfo then
        GBCR.Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: scan already scheduled/running, skipping Guild:Init")
    else
        GBCR.Guild:Init(GBCR.Guild:GetGuildInfo())
    end
end

function Events:PLAYER_REGEN_DISABLED()
    GBCR.Output:Debug("EVENTS", "PLAYER_REGEN_DISABLED event fired")

    GBCR.Protocol:UpdateSafetyLockout()
    if GBCR.Options:GetCombatHide() then
        GBCR.UI.Inventory:Close()
    end
end

function Events:PLAYER_REGEN_ENABLED()
    GBCR.Output:Debug("EVENTS", "PLAYER_REGEN_ENABLED event fired")

    GBCR.Protocol:UpdateSafetyLockout()
end

function Events:ZONE_CHANGED_NEW_AREA()
    GBCR.Output:Debug("EVENTS", "ZONE_CHANGED_NEW_AREA event fired")

    GBCR.Protocol:UpdateSafetyLockout()
end

function Events:MAIL_SHOW()
    GBCR.Output:Debug("EVENTS", "MAIL_SHOW event fired")

    GBCR.Inventory:OnUpdateStart()
    GBCR.Inventory.mailHasUpdated = true
    self.isMailOpen = true
    GBCR.Ledger:Check()
    if not MailFrame.isGBCRHooked then
        MailFrame:HookScript("OnHide", function()
            GBCR.Output:Debug("INVENTORY", "MailFrame OnHide function fired (mailbox closed)")
            Events:MAIL_CLOSED()
        end)
        MailFrame.isGBCRHooked = true
        GBCR.Output:Debug("INVENTORY", "Hooked MailFrame OnHide function")
    end
end

function Events:MAIL_CLOSED()
    GBCR.Output:Debug("EVENTS", "MAIL_CLOSED event fired")

    if GBCR.Ledger.recentAppends then
        wipe(GBCR.Ledger.recentAppends)
    end
    self.isMailOpen = false
    GBCR.Inventory:OnUpdateStart()
    GBCR.Inventory:OnUpdateStop()
end

function Events:MODIFIER_STATE_CHANGED()
    if not GameTooltip:IsShown() then
        return
    end

    local _, link = GameTooltip:GetItem()
    if not link then
        return
    end

    local itemID = tonumber(string_match(link, "|Hitem:(%d+):"))
    if not itemID then
        return
    end

    local sourcesIndex = GBCR.Inventory.cachedSourcesPerItem
    if not sourcesIndex or not sourcesIndex[itemID] or not next(sourcesIndex[itemID]) then
        return
    end

    GameTooltip.tooltipProcessedByGBCR = nil
    GameTooltip.pendingSourcesForGBCR = sourcesIndex[itemID]
    GameTooltip:SetOwner(Globals.WorldFrame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
end

-- ================================================================================================
-- Events for guild bank alts
function Events:BAG_UPDATE_DELAYED()
    GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED (timerBagUpdateDelayedScanInventory=%s, isMailOpen=%s, isAHClosed=%s)",
                      tostring(self.timerBagUpdateDelayedScanInventory), tostring(self.isMailOpen),
                      tostring(self.isAuctionHouseClosed))

    if shouldSkipGuildEvent("BAG_UPDATE_DELAYED") then
        return
    end

    if self.isMailOpen then
        GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (mail is still open)")

        return
    end

    if self.isAuctionHouseClosed == false then
        GBCR.Output:Debug("EVENTS", "BAG_UPDATE_DELAYED: skipping (AH is still open)")

        return
    end

    if self.timerBagUpdateDelayedScanInventory and not self.timerBagUpdateDelayedScanInventory:IsCancelled() then
        self.timerBagUpdateDelayedScanInventory:Cancel()
        self.timerBagUpdateDelayedScanInventory = nil
    end

    self.timerBagUpdateDelayedScanInventory = NewTimer(timerIntervals.BAG_UPDATE_QUIET_TIME, function()
        GBCR.Output:Debug("EVENTS", "Debounced BAG_UPDATE_DELAYED timer fired")

        GBCR.Inventory:OnUpdateStart()
        GBCR.Inventory:OnUpdateStop()
        self.timerBagUpdateDelayedScanInventory = nil
    end)
end

function Events:BANKFRAME_OPENED()
    GBCR.Output:Debug("EVENTS", "BANKFRAME_OPENED event fired")

    GBCR.Inventory:OnUpdateStart()
end

function Events:BANKFRAME_CLOSED()
    GBCR.Output:Debug("EVENTS", "BANKFRAME_CLOSED event fired")

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
    GBCR.Output:Debug("EVENTS", "MERCHANT_SHOW event fired")

    self.isMerchantOpen = true
    self.pendingVendorSellItem = nil
    GBCR.Inventory:OnUpdateStart()
end

function Events:MERCHANT_CLOSED()
    GBCR.Output:Debug("EVENTS", "MERCHANT_CLOSED event fired")

    self.isMerchantOpen = false
    self.pendingVendorSellItem = nil
    GBCR.Inventory:OnUpdateStop()
end

function Events:TRADE_SHOW()
    GBCR.Output:Debug("EVENTS", "TRADE_SHOW event fired")

    GBCR.Ledger:ResetTradeState()
    local partnerName = UnitName("npc") or UnitName("target")
    GBCR.Ledger.tradePartner = partnerName or ""
    GBCR.Ledger.tradePartnerUid = GBCR.Guild:DetermineUidForGuildMemberName(GBCR.Ledger.tradePartner)
    GBCR.Inventory:OnUpdateStart()
end

function Events:TRADE_MONEY_CHANGED()
    GBCR.Output:Debug("EVENTS", "TRADE_MONEY_CHANGED event fired")

    GBCR.Ledger.tradeMoney.giving = GetPlayerTradeMoney() or 0
    GBCR.Ledger.tradeMoney.receiving = GetTargetTradeMoney() or 0
end

function Events:TRADE_ACCEPT_UPDATE()
    GBCR.Output:Debug("EVENTS", "TRADE_ACCEPT_UPDATE event fired")

    GBCR.Ledger.tradeMoney.giving = GetPlayerTradeMoney() or 0
    GBCR.Ledger.tradeMoney.receiving = GetTargetTradeMoney() or 0
end

function Events:TRADE_PLAYER_ITEM_CHANGED()
    GBCR.Output:Debug("EVENTS", "TRADE_PLAYER_ITEM_CHANGED event fired")

    GBCR.Ledger:RefreshTradeItems()
end

function Events:TRADE_TARGET_ITEM_CHANGED()
    GBCR.Output:Debug("EVENTS", "TRADE_TARGET_ITEM_CHANGED event fired")

    GBCR.Ledger:RefreshTradeItems()
end

function Events:TRADE_REQUEST_CANCEL()
    GBCR.Output:Debug("EVENTS", "TRADE_REQUEST_CANCEL event fired")

    GBCR.Ledger:ResetTradeState()
end

function Events:TRADE_CLOSED()
    GBCR.Output:Debug("EVENTS", "TRADE_CLOSED event fired")

    GBCR.Inventory:OnUpdateStop()
end

function Events:UI_ERROR_MESSAGE(_, errorType, message)
    if message == tradeComplete then
        GBCR.Output:Debug("EVENTS", "UI_ERROR_MESSAGE event fired, message tradeComplete: committing trade to ledger")
        GBCR.Ledger:CommitTradeToLedger()
    elseif message == tradeBagFull or message == tradeTargetBagFull or message == tradeCancelled or message ==
        tradeTargetMaxExceeded then
        GBCR.Output:Debug("EVENTS", "UI_ERROR_MESSAGE event fired, trade failed (%s): discarding", tostring(message))
        GBCR.Ledger:ResetTradeState()
    end
end

function Events:GET_ITEM_INFO_RECEIVED(_, itemID, success)
    GBCR.Output:Debug("EVENTS", "GET_ITEM_INFO_RECEIVED event fired (itemID=%s, success=%s)", tostring(itemID), tostring(success))

    local pending = GBCR.Inventory.pendingItemInfoLoads
    if not pending or not pending[itemID] then
        return
    end

    pending[itemID] = nil

    if not success then
        return
    end

    GBCR.Output:Debug("EVENTS", "GET_ITEM_INFO_RECEIVED: data resolved for %d, queuing rescan", itemID)

    if self.timerGetItemInfoReceivedScanInventory then
        self.timerGetItemInfoReceivedScanInventory:Cancel()
    end

    self.timerGetItemInfoReceivedScanInventory = NewTimer(Constants.TIMER_INTERVALS.ITEM_INFO_RESCAN, function()
        self.timerGetItemInfoReceivedScanInventory = nil
        GBCR.Inventory:OnUpdateStart()
        GBCR.Inventory:OnUpdateStop()
        GBCR.UI.Inventory:MarkAllDirty()
        GBCR.UI:QueueUIRefresh()
    end)

    if success and GBCR.UI.Inventory.currentTab == "ledger" and GBCR.UI.Inventory.refreshLedger then
        GBCR.UI.Inventory.refreshLedger()
    end
end
