GBankClassic_Globals = GBankClassic_Globals or {}

local Globals = GBankClassic_Globals

-- Globals

-- WoW Lua APIs
local debugprofilestop = debugprofilestop
local hooksecurefunc = hooksecurefunc
local date = date
local time = time
local wipe = wipe
Globals.debugprofilestop = debugprofilestop
Globals.hooksecurefunc = hooksecurefunc
Globals.date = date
Globals.time = time
Globals.wipe = wipe

-- WoW APIs
local IsInRaid = IsInRaid
local IsInGuild = IsInGuild
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
Globals.IsInRaid = IsInRaid
Globals.IsInGuild = IsInGuild
Globals.IsShiftKeyDown = IsShiftKeyDown
Globals.IsControlKeyDown = IsControlKeyDown
local FCF_DockFrame = FCF_DockFrame
local FCF_ResetChatWindows = FCF_ResetChatWindows
local FCF_SetLocked = FCF_SetLocked
local FCF_SetWindowColor = FCF_SetWindowColor
local FCF_SetWindowName = FCF_SetWindowName
Globals.FCF_DockFrame = FCF_DockFrame
Globals.FCF_ResetChatWindows = FCF_ResetChatWindows
Globals.FCF_SetLocked = FCF_SetLocked
Globals.FCF_SetWindowColor = FCF_SetWindowColor
Globals.FCF_SetWindowName = FCF_SetWindowName
local ChatFrame_RemoveAllMessageGroups = ChatFrame_RemoveAllMessageGroups
local GetChatWindowInfo = GetChatWindowInfo
local CreateFrame = CreateFrame
local ChatFrame_RemoveAllChannels = ChatFrame_RemoveAllChannels
local ChatEdit_InsertLink = ChatEdit_InsertLink
local StaticPopup_Show = StaticPopup_Show
local GameTooltip_SetDefaultAnchor = GameTooltip_SetDefaultAnchor
Globals.ChatFrame_RemoveAllMessageGroups = ChatFrame_RemoveAllMessageGroups
Globals.GetChatWindowInfo = GetChatWindowInfo
Globals.CreateFrame = CreateFrame
Globals.ChatFrame_RemoveAllChannels = ChatFrame_RemoveAllChannels
Globals.ChatEdit_InsertLink = ChatEdit_InsertLink
Globals.StaticPopup_Show = StaticPopup_Show
Globals.GameTooltip_SetDefaultAnchor = GameTooltip_SetDefaultAnchor
local GetCursorInfo = GetCursorInfo
local ClearCursor = ClearCursor
local ClickSendMailItemButton = ClickSendMailItemButton
local PickupItem = PickupItem
local PickupContainerItem = PickupContainerItem or C_Container.PickupContainerItem
local CheckInbox = CheckInbox
local TakeInboxItem = TakeInboxItem
local TakeInboxMoney = TakeInboxMoney
local DressUpItemLink = DressUpItemLink
Globals.GetCursorInfo = GetCursorInfo
Globals.ClearCursor = ClearCursor
Globals.ClickSendMailItemButton = ClickSendMailItemButton
Globals.PickupItem = PickupItem
Globals.PickupContainerItem = PickupContainerItem
Globals.CheckInbox = CheckInbox
Globals.TakeInboxItem = TakeInboxItem
Globals.TakeInboxMoney = TakeInboxMoney
Globals.DressUpItemLink = DressUpItemLink
local GuildRoster = GuildRoster or C_GuildInfo.GuildRoster
local GetGuildInfo = GetGuildInfo
local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
local CanViewOfficerNote = CanViewOfficerNote
Globals.GuildRoster = GuildRoster
Globals.GetGuildInfo = GetGuildInfo
Globals.GetNumGuildMembers = GetNumGuildMembers
Globals.GetGuildRosterInfo = GetGuildRosterInfo
Globals.CanViewOfficerNote = CanViewOfficerNote
local GetItemNameByID = GetItemNameByID or C_Item.GetItemNameByID
local GetItemInfo = GetItemInfo
local GetItemInfoInstant = GetItemInfoInstant
local GetItemQualityColor = GetItemQualityColor
local GetItemInventoryTypeByID = GetItemInventoryTypeByID or C_Item.GetItemInventoryTypeByID
Globals.GetItemNameByID = GetItemNameByID
Globals.GetItemInfo = GetItemInfo
Globals.GetItemInfoInstant = GetItemInfoInstant
Globals.GetItemQualityColor = GetItemQualityColor
Globals.GetItemInventoryTypeByID = GetItemInventoryTypeByID
local GetInboxHeaderInfo = GetInboxHeaderInfo
local GetInboxItem = GetInboxItem
local GetInboxText = GetInboxText
local GetInboxItemLink = GetInboxItemLink
local GetInboxNumItems = GetInboxNumItems
local GetSendMailItem = GetSendMailItem
Globals.GetInboxHeaderInfo = GetInboxHeaderInfo
Globals.GetInboxItem = GetInboxItem
Globals.GetInboxText = GetInboxText
Globals.GetInboxItemLink = GetInboxItemLink
Globals.GetInboxNumItems = GetInboxNumItems
Globals.GetSendMailItem = GetSendMailItem
local GetMoney = GetMoney
local GetCoinTextureString = GetCoinTextureString
local GetContainerNumFreeSlots = GetContainerNumFreeSlots or C_Container.GetContainerNumFreeSlots
local GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
Globals.GetMoney = GetMoney
Globals.GetCoinTextureString = GetCoinTextureString
Globals.GetContainerNumFreeSlots = GetContainerNumFreeSlots
Globals.GetContainerItemInfo = GetContainerItemInfo
Globals.GetContainerNumSlots = GetContainerNumSlots
local GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
local UnitName = UnitName
local GetNormalizedRealmName = GetNormalizedRealmName
local GetRealmName = GetRealmName
local GetClassColor = GetClassColor
Globals.GetAddOnMetadata = GetAddOnMetadata
Globals.UnitName = UnitName
Globals.GetNormalizedRealmName = GetNormalizedRealmName
Globals.GetRealmName = GetRealmName
Globals.GetClassColor = GetClassColor
local GetServerTime = GetServerTime
local GetTime = GetTime
local SecondsToTime = SecondsToTime
Globals.GetServerTime = GetServerTime
Globals.GetTime = GetTime
Globals.SecondsToTime = SecondsToTime
local After = After or C_Timer.After
local NewTicker = NewTicker or C_Timer.NewTicker
local NewTimer = NewTimer or C_Timer.NewTimer
Globals.After = After
Globals.NewTicker = NewTicker
Globals.NewTimer = NewTimer

-- WoW global tables
local GameFontNormal = GameFontNormal
local GameTooltip = GameTooltip
local SendMailNameEditBox = SendMailNameEditBox
local Settings = Settings
local BankFrame = BankFrame
local MailFrame = MailFrame
local UIParent = UIParent
local UISpecialFrames = UISpecialFrames
local WorldFrame = WorldFrame
Globals.GameFontNormal = GameFontNormal
Globals.GameTooltip = GameTooltip
Globals.SendMailNameEditBox = SendMailNameEditBox
Globals.Settings = Settings
Globals.BankFrame = BankFrame
Globals.MailFrame = MailFrame
Globals.UIParent = UIParent
Globals.UISpecialFrames = UISpecialFrames
Globals.WorldFrame = WorldFrame

-- WoW global variables
local ATTACHMENTS_MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE
local ATTACHMENTS_MAX_SEND = ATTACHMENTS_MAX_SEND
local BANK_CONTAINER = BANK_CONTAINER
local ITEM_UNIQUE = ITEM_UNIQUE
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local NUM_BANKGENERIC_SLOTS = NUM_BANKGENERIC_SLOTS
Globals.ATTACHMENTS_MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE
Globals.ATTACHMENTS_MAX_SEND = ATTACHMENTS_MAX_SEND
Globals.BANK_CONTAINER = BANK_CONTAINER
Globals.ITEM_UNIQUE = ITEM_UNIQUE
Globals.NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
Globals.NUM_BANKGENERIC_SLOTS = NUM_BANKGENERIC_SLOTS

-- Embedded libraries or other AddOns
local LibStub = LibStub
local Bagnon = Bagnon
local BagBrother = BagBrother
Globals.LibStub = LibStub
Globals.Bagnon = Bagnon
Globals.BagBrother = BagBrother

-- Helper function that returns upvalues
function Globals.GetUpvalues(...)
    local keys = {...}
    local result = {}
    for _, key in ipairs(keys) do
        result[key] = Globals[key] or _G[key]
    end

    return result
end

-- Helpers

-- Generic helpers to count entries in tables
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

-- Generic helpers to count entries in array
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