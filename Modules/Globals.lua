local addonName, GBCR = ...

GBCR.Globals = {}
local Globals = GBCR.Globals

-- Lua APIs
Globals.bit_band = bit.band
Globals.bit_bxor = bit.bxor
Globals.date = date
Globals.debugprofilestop = debugprofilestop
Globals.hooksecurefunc = hooksecurefunc
Globals.ipairs = ipairs
Globals.math_abs = math.abs
Globals.math_ceil = math.ceil
Globals.math_floor = math.floor
Globals.math_max = math.max
Globals.math_min = math.min
Globals.math_random = math.random
Globals.next = next
Globals.pairs = pairs
Globals.select = select
Globals.string_byte = string.byte
Globals.string_find = string.find
Globals.string_format = string.format
Globals.string_gmatch = string.gmatch
Globals.string_gsub = string.gsub
Globals.string_len = string.len
Globals.string_lower = string.lower
Globals.string_match = string.match
Globals.string_sub = string.sub
Globals.strsplit = strsplit
Globals.table_concat = table.concat
Globals.table_remove = table.remove
Globals.table_sort = table.sort
Globals.table_unpack = table.unpack or unpack
Globals.time = time
Globals.tonumber = tonumber
Globals.tostring = tostring
Globals.type = type
Globals.wipe = table.wipe or wipe

-- Game APIs
Globals.After = After or C_Timer.After
Globals.BuyMerchantItem = BuyMerchantItem
Globals.CanEditOfficerNote = CanEditOfficerNote or C_GuildInfo.CanEditOfficerNote
Globals.CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
Globals.ChatEdit_InsertLink = ChatEdit_InsertLink
Globals.CheckInbox = CheckInbox
Globals.ClearCursor = ClearCursor
Globals.CreateFrame = CreateFrame
Globals.DeleteCursorItem = DeleteCursorItem
Globals.DressUpItemLink = DressUpItemLink
Globals.GameTooltip_SetDefaultAnchor = GameTooltip_SetDefaultAnchor
Globals.GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
Globals.GetClassColor = GetClassColor or C_ClassColor.GetClassColor
Globals.GetCoinTextureString = GetCoinTextureString or C_CurrencyInfo.GetCoinTextureString
Globals.GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
Globals.GetContainerNumFreeSlots = GetContainerNumFreeSlots or C_Container.GetContainerNumFreeSlots
Globals.GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
Globals.GetCursorInfo = GetCursorInfo
Globals.GetCursorPosition = GetCursorPosition
Globals.GetGameTime = GetGameTime
Globals.GetGuildInfo = GetGuildInfo
Globals.GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
Globals.GetInboxHeaderInfo = GetInboxHeaderInfo
Globals.GetInboxItem = GetInboxItem
Globals.GetInboxItemLink = GetInboxItemLink
Globals.GetInboxNumItems = GetInboxNumItems
Globals.GetItemClassInfo = GetItemClassInfo or C_Item.GetItemClassInfo
Globals.GetItemInfo = GetItemInfo or C_Item.GetItemInfo
Globals.GetItemInventoryTypeByID = GetItemInventoryTypeByID or C_Item.GetItemInventoryTypeByID
Globals.GetItemQualityColor = GetItemQualityColor or C_Item.GetItemQualityColor
Globals.GetItemSubClassInfo = GetItemSubClassInfo or C_Item.GetItemSubClassInfo
Globals.GetMerchantItemInfo = GetMerchantItemInfo
Globals.GetMerchantItemLink = GetMerchantItemLink
Globals.GetMerchantNumItems = GetMerchantNumItems
Globals.GetMoney = GetMoney
Globals.GetNormalizedRealmName = GetNormalizedRealmName
Globals.GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
Globals.GetRealmName = GetRealmName
Globals.GetSendMailItem = GetSendMailItem
Globals.GetSendMailItemLink = GetSendMailItemLink
Globals.GetSendMailMoney = GetSendMailMoney
Globals.GetServerTime = GetServerTime or C_DateAndTime.GetServerTime
Globals.GetPlayerTradeMoney = GetPlayerTradeMoney
Globals.GetTargetTradeMoney = GetTargetTradeMoney
Globals.GetTime = GetTime
Globals.GetTradePlayerItemInfo = GetTradePlayerItemInfo
Globals.GetTradePlayerItemLink = GetTradePlayerItemLink
Globals.GetTradeTargetItemInfo = GetTradeTargetItemInfo
Globals.GetTradeTargetItemLink = GetTradeTargetItemLink
Globals.GuildControlGetNumRanks = GuildControlGetNumRanks or C_GuildInfo.GuildControlGetNumRanks
Globals.GuildControlGetRankFlags = GuildControlGetRankFlags or C_GuildInfo.GuildControlGetRankFlags
Globals.GuildControlGetRankName = GuildControlGetRankName
Globals.GuildRoster = GuildRoster or C_GuildInfo.GuildRoster
Globals.InCombatLockdown = InCombatLockdown
Globals.IsAddOnLoaded = IsAddOnLoaded or C_AddOns.IsAddOnLoaded
Globals.IsAltKeyDown = IsAltKeyDown
Globals.IsControlKeyDown = IsControlKeyDown
Globals.IsGuildOfficer = IsGuildOfficer or C_GuildInfo.IsGuildOfficer
Globals.IsInGuild = IsInGuild
Globals.IsInInstance = IsInInstance
Globals.IsInRaid = IsInRaid
Globals.IsShiftKeyDown = IsShiftKeyDown
Globals.NewTicker = NewTicker or C_Timer.NewTicker
Globals.NewTimer = NewTimer or C_Timer.NewTimer
Globals.PickupContainerItem = PickupContainerItem or C_Container.PickupContainerItem
Globals.PickupItem = PickupItem or C_Container.PickupItem
Globals.SearchBoxTemplate_OnTextChanged = SearchBoxTemplate_OnTextChanged
Globals.SellCursorItem = SellCursorItem
Globals.TakeInboxItem = TakeInboxItem
Globals.TakeInboxMoney = TakeInboxMoney
Globals.UnitGUID = UnitGUID
Globals.UnitName = UnitName

-- Global tables
Globals.Enum = Enum
Globals.GameFontDisable = GameFontDisable
Globals.GameFontHighlight = GameFontHighlight
Globals.GameFontHighlightSmall = GameFontHighlightSmall
Globals.GameFontNormal = GameFontNormal
Globals.GameTooltip = GameTooltip
Globals.Item = Item
Globals.MailFrame = MailFrame
Globals.SendMailNameEditBox = SendMailNameEditBox
Globals.Settings = Settings
Globals.UIParent = UIParent
Globals.UISpecialFrames = UISpecialFrames
Globals.WorldFrame = WorldFrame

-- Global variables
Globals.ATTACHMENTS_MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE
Globals.ATTACHMENTS_MAX_SEND = ATTACHMENTS_MAX_SEND
Globals.AUCTION_EXPIRED_MAIL_SUBJECT = AUCTION_EXPIRED_MAIL_SUBJECT
Globals.AUCTION_OUTBID_MAIL_SUBJECT = AUCTION_OUTBID_MAIL_SUBJECT
Globals.AUCTION_REMOVED_MAIL_SUBJECT = AUCTION_REMOVED_MAIL_SUBJECT
Globals.AUCTION_SOLD_MAIL_SUBJECT = AUCTION_SOLD_MAIL_SUBJECT
Globals.AUCTION_WON_MAIL_SUBJECT = AUCTION_WON_MAIL_SUBJECT
Globals.BANK_CONTAINER = BANK_CONTAINER
Globals.ERR_TRADE_BAG_FULL = ERR_TRADE_BAG_FULL
Globals.ERR_TRADE_CANCELLED = ERR_TRADE_CANCELLED
Globals.ERR_TRADE_COMPLETE = ERR_TRADE_COMPLETE
Globals.ERR_TRADE_TARGET_BAG_FULL = ERR_TRADE_TARGET_BAG_FULL
Globals.ERR_TRADE_TARGET_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS = ERR_TRADE_TARGET_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS
Globals.ITEM_BIND_ON_ACQUIRE = Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire or 1
Globals.MAX_TRADABLE_ITEMS = MAX_TRADABLE_ITEMS
Globals.NUM_BANKGENERIC_SLOTS = NUM_BANKGENERIC_SLOTS

-- Global namespaces
Globals.C_Container = _G.C_Container

-- Libraries
local AceAddon = LibStub("AceAddon-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local LibSerialize = LibStub("LibSerialize")
GBCR.Libs = {
    AceAddon = AceAddon,
    AceConfig = AceConfig,
    AceConfigDialog = AceConfigDialog,
    AceConfigRegistry = AceConfigRegistry,
    AceDB = AceDB,
    AceDBOptions = AceDBOptions,
    AceGUI = AceGUI,
    LibDataBroker = LibDataBroker,
    LibDBIcon = LibDBIcon,
    LibDeflate = LibDeflate,
    LibSerialize = LibSerialize
}

local pairs = Globals.pairs
local ipairs = Globals.ipairs
local type = Globals.type

-- Helper function to count entries in tables
local function countTableEntries(tbl)
    if not tbl or type(tbl) ~= "table" then
        return 0
    end

    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
    end

    return n
end

-- Helper function to count entries in array
local function countArrayEntries(tbl)
    if not tbl or type(tbl) ~= "table" then
        return 0
    end

    local n = 0
    for _ in ipairs(tbl) do
        n = n + 1
    end

    return n
end

-- Smart count: uses array counting when it looks list-like (`tbl[1]`), otherwise counts by pairs
local function countEntries(tbl)
    if not tbl or type(tbl) ~= "table" then
        return 0
    end

    if tbl[1] ~= nil then
        return countArrayEntries(tbl)
    end

    return countTableEntries(tbl)
end

-- Generate a comparison function based on a priority list of rules
local function createSortHandler(rules)
    local numRules = #rules

    return function(a, b)
        local infoA = a.itemInfo
        local infoB = b.itemInfo

        for i = 1, numRules do
            local rule = rules[i]
            local property = rule.property
            local valA, valB

            if property == "name" then
                valA = a.lowerName or (infoA and infoA.name)
                valB = b.lowerName or (infoB and infoB.name)
            else
                valA = infoA and infoA[property]
                valB = infoB and infoB[property]
            end

            if valA ~= valB then
                valA = valA ~= nil and valA or rule.fallback
                valB = valB ~= nil and valB or rule.fallback

                if valA ~= valB then
                    if rule.isDescending then
                        return valA > valB
                    else
                        return valA < valB
                    end
                end
            end
        end

        return false
    end
end

-- Helper function to wrap a text string in escape codes to display it in a specific color
local function colorizeText(color, text)
    return "|c" .. color .. text .. "|r"
end

-- Evaluates whether a heavy background loop should yield execution to the next frame to prevent freezing the game client
local function shouldYield(frameStart, processedThisFrame, checkInterval, fallbackLimit)
    if processedThisFrame >= fallbackLimit then
        return true
    end

    if processedThisFrame % checkInterval == 0 and (Globals.debugprofilestop() - frameStart) > 12 then
        return true
    end

    return false
end

-- Export functions for other modules
Globals.Count = countEntries
Globals.CreateSortHandler = createSortHandler
Globals.ColorizeText = colorizeText
Globals.ShouldYield = shouldYield
