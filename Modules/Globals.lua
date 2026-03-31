local addonName, GBCR = ...

GBCR.Globals = {}
local Globals = GBCR.Globals

-- Lua APIs
Globals.date = date
Globals.debugprofilestop = debugprofilestop
Globals.gsub = gsub
Globals.hooksecurefunc = hooksecurefunc
Globals.strsplit = strsplit
Globals.time = time
Globals.wipe = wipe

-- Game APIs
Globals.After = After or C_Timer.After
Globals.CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
Globals.ChatEdit_InsertLink = ChatEdit_InsertLink
Globals.ChatFrame_RemoveAllChannels = ChatFrame_RemoveAllChannels
Globals.ChatFrame_RemoveAllMessageGroups = ChatFrame_RemoveAllMessageGroups
Globals.CheckInbox = CheckInbox
Globals.ClearCursor = ClearCursor
Globals.ClickSendMailItemButton = ClickSendMailItemButton
Globals.CreateFrame = CreateFrame
Globals.DressUpItemLink = DressUpItemLink
Globals.FCF_DockFrame = FCF_DockFrame
Globals.FCF_ResetChatWindows = FCF_ResetChatWindows
Globals.FCF_SelectDockFrame = FCF_SelectDockFrame
Globals.FCF_SetLocked = FCF_SetLocked
Globals.FCF_SetWindowColor = FCF_SetWindowColor
Globals.FCF_SetWindowName = FCF_SetWindowName
Globals.GameTooltip_SetDefaultAnchor = GameTooltip_SetDefaultAnchor
Globals.GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
Globals.GetChatWindowInfo = GetChatWindowInfo
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
Globals.ChatFrame1 = ChatFrame1
Globals.Enum = Enum
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
Globals.ITEM_UNIQUE = ITEM_UNIQUE
Globals.NUM_BANKGENERIC_SLOTS = NUM_BANKGENERIC_SLOTS
Globals.NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS

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

-- Helper function to count entries in tables
function Globals:CountTableEntries(tbl)
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
function Globals:CountArrayEntries(tbl)
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
function Globals:Count(tbl)
    if not tbl or type(tbl) ~= "table" then
        return 0
    end

    if tbl[1] ~= nil then
        return self:CountArrayEntries(tbl)
    end

    return self:CountTableEntries(tbl)
end

-- Helper function that generates a comparison function based on a priority list of rules
function Globals:CreateSortHandler(rules)
	return function(a, b)
		local itemDataA = a.itemInfo
		local itemDataB = b.itemInfo

		for _, rule in ipairs(rules) do
            local property = rule.property
			local isDescending = rule.isDescending
			local fallback = rule.fallback

			local compareValueA = itemDataA[property]
			local compareValueB = itemDataB[property]

			if compareValueA ~= compareValueB then
				compareValueA = compareValueA ~= nil and compareValueA or fallback
				compareValueB = compareValueB ~= nil and compareValueB or fallback

				if isDescending then
					return compareValueA > compareValueB
				else
					return compareValueA < compareValueB
				end
			end
		end

		return false
	end
end

-- Helped to print text in color
function Globals:Colorize(color, text)
    return string.format("|c%s%s|r", tostring(color), tostring(text))
end