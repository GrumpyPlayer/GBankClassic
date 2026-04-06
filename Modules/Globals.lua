local addonName, GBCR = ...

GBCR.Globals = {}
local Globals = GBCR.Globals

-- Lua APIs
Globals.date = date
Globals.debugprofilestop = debugprofilestop
Globals.find = string.find
Globals.gsub = gsub
Globals.hooksecurefunc = hooksecurefunc
Globals.ipairs = ipairs
Globals.math_floor = math.floor
Globals.math_min = math.min
Globals.next = next
Globals.pairs = pairs
Globals.select = select
Globals.string_byte = string.byte
Globals.string_format = string.format
Globals.string_gsub = string.gsub
Globals.string_len = string.len
Globals.string_lower = string.lower
Globals.string_match = string.match
Globals.strsplit = strsplit
Globals.sub = string.sub
Globals.table_concat = table.concat
Globals.table_insert = table.insert
Globals.table_remove = table.remove
Globals.table_sort = table.sort
Globals.time = time
Globals.tonumber = tonumber
Globals.tostring = tostring
Globals.type = type
Globals.unpack = table.unpack or unpack
Globals.wipe = table.wipe or wipe

-- Game APIs
Globals.After = After or C_Timer.After
Globals.CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
Globals.ChatEdit_InsertLink = ChatEdit_InsertLink
Globals.CheckInbox = CheckInbox
Globals.ClearCursor = ClearCursor
Globals.ClickSendMailItemButton = ClickSendMailItemButton
Globals.CreateFrame = CreateFrame
Globals.DressUpItemLink = DressUpItemLink
Globals.GameTooltip_SetDefaultAnchor = GameTooltip_SetDefaultAnchor
Globals.GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
Globals.GetClassColor = GetClassColor or C_ClassColor.GetClassColor
Globals.GetCoinTextureString = GetCoinTextureString or C_CurrencyInfo.GetCoinTextureString
Globals.GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
Globals.GetContainerNumFreeSlots = GetContainerNumFreeSlots or C_Container.GetContainerNumFreeSlots
Globals.GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
Globals.GetCursorInfo = GetCursorInfo
Globals.GetGuildInfo = GetGuildInfo
Globals.GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
Globals.GetInboxHeaderInfo = GetInboxHeaderInfo
Globals.GetInboxItem = GetInboxItem
Globals.GetInboxItemLink = GetInboxItemLink
Globals.GetInboxNumItems = GetInboxNumItems
Globals.GetInboxText = GetInboxText
Globals.GetItemInfo = GetItemInfo or C_Item.GetItemInfo
Globals.GetItemInfoInstant = GetItemInfoInstant or C_Item.GetItemInfoInstant
Globals.GetItemInventoryTypeByID = GetItemInventoryTypeByID or C_Item.GetItemInventoryTypeByID
Globals.GetItemNameByID = GetItemNameByIDeByID or C_Item.GetItemNameByIDeByID
Globals.GetItemQualityColor = GetItemQualityColor or C_Item.GetItemQualityColor
Globals.GetMoney = GetMoney
Globals.GetNormalizedRealmName = GetNormalizedRealmName
Globals.GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
Globals.GetRealmName = GetRealmName
Globals.GetSendMailItem = GetSendMailItem
Globals.GetServerTime = GetServerTime or C_DateAndTime.GetServerTime
Globals.GetTime = GetTime
Globals.GuildControlGetNumRanks = GuildControlGetNumRanks or C_GuildInfo.GuildControlGetNumRanks
Globals.GuildControlGetRankFlags = GuildControlGetRankFlags or C_GuildInfo.GuildControlGetRankFlags
Globals.GuildRoster = GuildRoster or C_GuildInfo.GuildRoster
Globals.IsAddOnLoaded = IsAddOnLoaded or C_AddOns.IsAddOnLoaded
Globals.IsAltKeyDown = IsAltKeyDown
Globals.IsControlKeyDown = IsControlKeyDown
Globals.IsInGuild = IsInGuild
Globals.IsInInstance = IsInInstance
Globals.IsInRaid = IsInRaid
Globals.IsShiftKeyDown = IsShiftKeyDown
Globals.NewTicker = NewTicker or C_Timer.NewTicker
Globals.NewTimer = NewTimer or C_Timer.NewTimer
Globals.PickupContainerItem = PickupContainerItem or C_Container.PickupContainerItem
Globals.PickupItem = PickupItem or C_Container.PickupItem
Globals.SecondsToTime = SecondsToTime
Globals.StaticPopup_Show = StaticPopup_Show
Globals.TakeInboxItem = TakeInboxItem
Globals.TakeInboxMoney = TakeInboxMoney
Globals.UnitName = UnitName

-- Global tables
Globals.BankFrame = BankFrame
Globals.Enum = Enum
Globals.GameTooltip = GameTooltip
Globals.Item = Item
Globals.MailFrame = MailFrame
Globals.SendMailNameEditBox = SendMailNameEditBox
Globals.Settings = Settings
Globals.UIParent = UIParent
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
Globals.ITEM_UNIQUE = ITEM_UNIQUE
Globals.LOOT_ITEM_PUSHED_SELF = LOOT_ITEM_PUSHED_SELF
Globals.LOOT_ITEM_PUSHED_SELF_MULTIPLE = LOOT_ITEM_PUSHED_SELF_MULTIPLE
Globals.LOOT_ITEM_SELF = LOOT_ITEM_SELF
Globals.LOOT_ITEM_SELF_MULTIPLE = LOOT_ITEM_SELF_MULTIPLE
Globals.NUM_BANKGENERIC_SLOTS = NUM_BANKGENERIC_SLOTS

-- Libraries
local AceAddon = LibStub("AceAddon-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
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
    AceDB = AceDB,
    AceDBOptions = AceDBOptions,
    AceGUI = AceGUI,
    LibDataBroker = LibDataBroker,
    LibDBIcon = LibDBIcon,
    LibDeflate = LibDeflate,
    LibSerialize = LibSerialize,
}

local pairs = Globals.pairs
local ipairs = Globals.ipairs
local type = Globals.type

-- Helper function to count entries in tables
local function countTableEntries(self, tbl)
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
local function countArrayEntries(self, tbl)
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
local function countEntries(self, tbl)
    if not tbl or type(tbl) ~= "table" then
        return 0
    end

    if tbl[1] ~= nil then
        return countArrayEntries(self, tbl)
    end

    return countTableEntries(self, tbl)
end

-- Helper function that generates a comparison function based on a priority list of rules
local function createSortHandler(self, rules)
    local numRules = #rules

	return function(a, b)
		local itemDataA = a.itemInfo
		local itemDataB = b.itemInfo

		for i = 1, numRules do
            local rule = rules[i]
            local property = rule.property
			local compareValueA = itemDataA[property]
			local compareValueB = itemDataB[property]

			if compareValueA ~= compareValueB then
				compareValueA = compareValueA ~= nil and compareValueA or rule.fallback
				compareValueB = compareValueB ~= nil and compareValueB or rule.fallback

				if rule.isDescending then
					return compareValueA > compareValueB
				else
					return compareValueA < compareValueB
				end
			end
		end

		return false
	end
end

-- Helper function to print text in color
local function colorizeText(self, color, text)
    return "|c" .. color .. text .. "|r"
end

-- Export functions for other modules
Globals.Count = countEntries
Globals.CreateSortHandler = createSortHandler
Globals.Colorize = colorizeText