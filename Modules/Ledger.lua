local addonName, GBCR = ...

GBCR.Ledger = {}
local Ledger = GBCR.Ledger

Ledger.indexTimestamp = 1
Ledger.indexItemId = 2
Ledger.indexEnchant = 3
Ledger.indexSuffix = 4
Ledger.indexCount = 5
Ledger.indexActor = 6
Ledger.indexOperation = 7

local Globals = GBCR.Globals
local bit_band = Globals.bit_band
local date = Globals.date
local ipairs = Globals.ipairs
local math_min = Globals.math_min
local string_format = Globals.string_format
local string_match = Globals.string_match
local strsplit = Globals.strsplit
local table_concat = Globals.table_concat
local table_sort = Globals.table_sort
local tonumber = Globals.tonumber
local wipe = Globals.wipe

local After = Globals.After
local CheckInbox = Globals.CheckInbox
local GetCoinTextureString = Globals.GetCoinTextureString
local GetInboxHeaderInfo = Globals.GetInboxHeaderInfo
local GetInboxItem = Globals.GetInboxItem
local GetInboxItemLink = Globals.GetInboxItemLink
local GetItemInfo = Globals.GetItemInfo
local GetMerchantItemInfo = Globals.GetMerchantItemInfo
local GetMerchantItemLink = Globals.GetMerchantItemLink
local GetMoney = Globals.GetMoney
local GetSendMailItem = Globals.GetSendMailItem
local GetSendMailItemLink = Globals.GetSendMailItemLink
local GetSendMailMoney = Globals.GetSendMailMoney
local GetServerTime = Globals.GetServerTime
local GetTradePlayerItemInfo = Globals.GetTradePlayerItemInfo
local GetTradePlayerItemLink = Globals.GetTradePlayerItemLink
local GetTradeTargetItemInfo = Globals.GetTradeTargetItemInfo
local GetTradeTargetItemLink = Globals.GetTradeTargetItemLink
local NewTimer = Globals.NewTimer

local attachmentsMaxReceive = Globals.ATTACHMENTS_MAX_RECEIVE
local attachmentsMaxSend = Globals.ATTACHMENTS_MAX_SEND
local tradeMaxItems = Globals.MAX_TRADABLE_ITEMS

local Constants = GBCR.Constants
local ledgerConstants = Constants.LEDGER
local ledgerOperations = Constants.LEDGER_OPERATION
local timerIntervals = Constants.TIMER_INTERVALS

local Output = GBCR.Output

-- ================================================================================================
-- Format a single ledger entry for display
local function formatEntry(self, entry, altName)
    local opCode = entry[self.indexOperation]
    if not opCode then
        return
    end

    local timestamp = entry[self.indexTimestamp]
    local itemId = entry[self.indexItemId]
    local enchant = entry[self.indexEnchant]
    local suffix = entry[self.indexSuffix]
    local count = entry[self.indexCount]
    local actor = entry[self.indexActor]
    local timeString = date("%H:%M", timestamp)

    local actorName = ""
    if actor and actor ~= "" then
        local name = GBCR.Guild:FindGuildMemberByUid(actor)
        if name then
            actorName = name
        else
            actorName = Globals.ColorizeText(Constants.COLORS.GRAY, "(outside guild)")
        end
    end

    local isMoney = (itemId == Constants.LEDGER_MONEY_ITEM)
    local itemRef
    local iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"

    if isMoney then
        itemRef = GetCoinTextureString(count)
        iconPath = "Interface\\Icons\\INV_Misc_Coin_01"
    else
        local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
        if not name and itemId > 0 then
            if GBCR.Inventory and GBCR.Inventory.pendingItemInfoLoads then
                if not GBCR.Inventory.pendingItemInfoLoads[itemId] then
                    GBCR.Inventory.pendingItemInfoLoads[itemId] = true
                    GetItemInfo(itemId)
                end
            end
        end

        itemRef = name and (count > 1 and count .. "x " .. name or name) or string_format("%dx [item:%d]", count, itemId)
        if icon then
            iconPath = icon
        end
    end

    local IN = bit_band(opCode, ledgerOperations.IN) ~= 0
    local OUT = bit_band(opCode, ledgerOperations.OUT) ~= 0
    local isMail = bit_band(opCode, ledgerOperations.MAIL) ~= 0
    local isTrade = bit_band(opCode, ledgerOperations.TRADE) ~= 0
    local isVendor = bit_band(opCode, ledgerOperations.VENDOR) ~= 0
    local isLoot = bit_band(opCode, ledgerOperations.LOOT) ~= 0
    local isCOD = bit_band(opCode, ledgerOperations.COD) ~= 0
    local isDestroy = bit_band(opCode, ledgerOperations.DESTROY) ~= 0
    local isAH = bit_band(opCode, ledgerOperations.AH) ~= 0
    local isAHBuyer = bit_band(opCode, ledgerOperations.AH_BUYER) ~= 0

    local desc
    if isAH then
        if IN then
            if isAHBuyer then
                desc = string_format("Received %s (outbid refund) from Auction House", itemRef)
            else
                desc = string_format("Received %s (sale proceeds) from Auction House", itemRef)
            end
        elseif OUT then
            if isAHBuyer then
                desc = string_format("Won %s at Auction House", itemRef)
            else
                desc = string_format("Retrieved %s from Auction House (cancelled or expired)", itemRef)
            end
        end
    elseif isMail and IN and isCOD then
        desc = string_format("Paid COD and received %s via mail", itemRef)
    elseif isMail and IN then
        desc = actorName ~= "" and string_format("Received %s from %s via mail", itemRef, actorName) or
                   string_format("Received %s via mail", itemRef)
    elseif isMail and OUT then
        desc = actorName ~= "" and string_format("Sent %s to %s via mail", itemRef, actorName) or
                   string_format("Sent %s via mail", itemRef)
    elseif isTrade and IN then
        desc = string_format("Received %s from %s via trade", itemRef, actorName)
    elseif isTrade and OUT then
        desc = string_format("Gave %s to %s via trade", itemRef, actorName)
    elseif isVendor and IN then
        desc = string_format("Sold %s to vendor", itemRef)
    elseif isVendor and OUT then
        desc = string_format("Bought %s from vendor", itemRef)
    elseif isLoot and IN then
        desc = string_format("Looted %s", itemRef)
    elseif isDestroy and OUT then
        desc = string_format("Destroyed %s", itemRef)
    else
        desc = string_format("%s %s", IN and "Received" or "Lost", itemRef)
    end

    if not desc then
        desc = string_format("Unknown transaction (%s)", itemRef or "nil")
    end

    return timeString, iconPath, desc
end

-- Export ledger as plain text for copy-paste
local function exportLedger(self, altName, callback)
    local sv = GBCR.Database.savedVariables
    if not sv or not sv.alts or not sv.alts[altName] then
        if callback then
            callback("")
        end

        return
    end

    local ledger = sv.alts[altName].ledger
    if not ledger or #ledger == 0 then
        if callback then
            callback("No ledger entries")
        end

        return
    end

    local lines = {"Ledger for " .. altName .. ":"}
    local total = #ledger
    local index = 1
    local batchSize = Constants.LIMITS.BATCH_SIZE_GETITEMINFO

    local function processBatch()
        local endIndex = math_min(index + batchSize - 1, total)
        for i = index, endIndex do
            local entry = ledger[i]
            if entry then
                local timestamp = entry[self.indexTimestamp]
                local _, _, desc = formatEntry(self, entry, altName)

                if desc then
                    lines[#lines + 1] = string_format("[%s] %s", date("%Y-%m-%d %H:%M", timestamp), desc)
                end
            end
        end
        index = endIndex + 1
        if index <= total then
            After(0, processBatch)
        else
            if callback then
                callback(table_concat(lines, "\n"))
            end
        end
    end

    After(0, processBatch)
end

-- ================================================================================================
-- Helper to define the ledger key
local function makeLedgerEntryKey(self, entry)
    return entry[self.indexTimestamp] .. "_" .. entry[self.indexItemId] .. "_" .. entry[self.indexOperation] .. "_" ..
               (entry[self.indexCount] or 0) .. "_" .. (entry[self.indexActor] or "")
end

-- Merge received ledger entries into local ledger (dedup by timestamp + itemId + opCode)
local function mergeLedger(self, altName, incomingSlice)
    if not incomingSlice or #incomingSlice == 0 then
        return
    end

    local sv = GBCR.Database.savedVariables
    if not sv or not sv.alts or not sv.alts[altName] then
        return
    end

    local alt = sv.alts[altName]
    if not alt.ledger then
        alt.ledger = {}
    end
    local ledger = alt.ledger

    local existing = {}
    for i = 1, #ledger do
        existing[makeLedgerEntryKey(self, ledger[i])] = true
    end

    local added = 0
    for _, entry in ipairs(incomingSlice) do
        local key = makeLedgerEntryKey(self, entry)
        if not existing[key] then
            ledger[#ledger + 1] = entry
            existing[key] = true
            added = added + 1
        end
    end

    if added > 0 then
        table_sort(ledger, function(a, b)
            return a[self.indexTimestamp] > b[self.indexTimestamp]
        end)
        for i = ledgerConstants.PRUNE_TO + 1, #ledger do
            ledger[i] = nil
        end
    end
end

-- Append a ledger entry to the current player's ledger
-- itemString: "id" or "id:enchant:suffix" or nil for money (money uses itemId=LEDGER_MONEY_ITEM=0)
-- count: positive integer (quantity or copper for money)
-- actorUid: guild member UID string or "" for world/AH events
-- opCode: bitmask from ledgerOperations
local function appendLedger(self, altName, itemString, count, actorUid, opCode, dedupeContext)
    local sv = GBCR.Database.savedVariables
    if not sv or not sv.alts or not sv.alts[altName] then
        return
    end

    local alt = sv.alts[altName]
    if not alt.ledger then
        alt.ledger = {}
    end
    local ledger = alt.ledger

    local itemId, enchant, suffix = 0, 0, 0
    if itemString and itemString ~= "" then
        local p1, p2, p3 = strsplit(":", itemString)
        itemId = tonumber(p1) or 0
        enchant = tonumber(p2) or 0
        suffix = tonumber(p3) or 0
    end

    local ledgerLen = #ledger + 1
    ledger[ledgerLen] = {GetServerTime(), itemId, enchant, suffix, count or 1, actorUid or "", opCode}
    Output:Debug("LEDGER",
                 "Recorded ledger entry for %s (timestamp=%s, itemId=%s, enchant=%s, suffix=%s, count=%s, actorUid=%s, opcode=%s)",
                 altName, GetServerTime(), itemId, enchant, suffix, count or 1, actorUid or "", opCode)

    if ledgerLen > ledgerConstants.MAX_ENTRIES then
        table_sort(ledger, function(a, b)
            return a[self.indexTimestamp] > b[self.indexTimestamp]
        end)
        for i = ledgerConstants.PRUNE_TO + 1, #ledger do
            ledger[i] = nil
        end
    end

    if self.timerLedgerUpdateBroadcast and not self.timerLedgerUpdateBroadcast:IsCancelled() then
        self.timerLedgerUpdateBroadcast:Cancel()
        self.timerLedgerUpdateBroadcast = nil
    end

    self.timerLedgerUpdateBroadcast = NewTimer(timerIntervals.LEDGER_UPDATE_QUIET_TIME, function()
        alt.version = GetServerTime()

        local networkMeta = GBCR.Database.savedVariables and GBCR.Database.savedVariables.networkMeta
        if networkMeta then
            networkMeta.seedCount = 0
            networkMeta.lastSeedTime = nil
            networkMeta.lastSeedTarget = nil
        end

        Output:Debug("LEDGER", "Ledger changed for %s, version updated to %d", altName, alt.version)
        GBCR.Protocol:SendAnnounce(GBCR.Guild:GetNormalizedPlayerName())
        GBCR.UI.Inventory:MarkAltDirty(altName)

        self.timerLedgerUpdateBroadcast = nil
    end)
end

-- ================================================================================================

-- Helper to match AH mail subjects ("REMOVED","EXPIRED","OUTBID","SOLD","WON") or nil
local function getAHMailType(subject)
    for _, patternData in ipairs(Constants.AH_MAIL_SUBJECT_PATTERNS) do
        if string_match(subject, patternData.pattern) then
            return patternData.ahType
        end
    end

    return nil
end

-- Helper to fetch and bundle mail context
local function getMailContext(mailId)
    local _, _, sender, subject, money, cod, daysLeft, itemCount, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(mailId)
    if not sender or wasReturned or isGM then
        return nil
    end

    return {
        sender = sender,
        money = tonumber(money) or 0,
        cod = tonumber(cod) or 0,
        daysLeft = daysLeft or 0,
        itemCount = itemCount or 0,
        ahType = getAHMailType(subject),
        actorUid = GBCR.Guild:DetermineUidForGuildMemberName(sender)
    }
end

-- Helper to resolve the opCode
local function resolveOpCode(header, isMoney)
    if header.ahType then
        local fallback = isMoney and ledgerOperations.AH_SOLD or ledgerOperations.AH_CANCELLED

        return Constants.AH_MAIL_OPCODES[header.ahType] or fallback
    end

    return (not isMoney and header.cod > 0) and ledgerOperations.MAIL_COD_IN or ledgerOperations.MAIL_IN
end

-- Commit taking an item from opened mail to the ledger
local function onTakeInboxItem(self, mailId, attachmentIndex, header)
    header = header or getMailContext(mailId)
    if not header then
        return
    end

    local link = GetInboxItemLink(mailId, attachmentIndex)
    if not link then
        return
    end

    local _, _, _, count = GetInboxItem(mailId, attachmentIndex)
    local itemStr = GBCR.Inventory:GetItemKey(link)
    local opCode = resolveOpCode(header, false)
    local player = GBCR.Guild:GetNormalizedPlayerName()

    local dedupeKey = string_format("mail_%s_%.12f_%d_%d_%s", header.sender, header.daysLeft or 0, attachmentIndex,
                                    tonumber(count) or 1, itemStr)
    if self.mailRegistry[dedupeKey] then
        Output:Debug("LEDGER", "Prevented tracking for key: %s", dedupeKey)

        return
    end

    Output:Debug("LEDGER", "Queueing incoming item from mail: x%d %s from %s (opCode=%s, key=%s)", count or 1, itemStr,
                 header.sender, opCode, dedupeKey)

    self.mailRegistry[dedupeKey] = true
    table.insert(self.mailItemQueue, {
        sender = header.sender,
        actorUid = header.actorUid,
        itemStr = itemStr,
        link = link,
        qty = tonumber(count) or 1,
        opCode = opCode,
        dedupeContext = dedupeKey,
        player = player
    })
end

-- Commit taking money from opened mail to the ledger
local function onTakeInboxMoney(self, mailId, header)
    header = header or getMailContext(mailId)
    if not header or header.money <= 0 or header.cod > 0 then
        return
    end

    local opCode = resolveOpCode(header, true)
    local player = GBCR.Guild:GetNormalizedPlayerName()

    local dedupeKey = string_format("mail_%.12f_money", header.daysLeft or 0)
    if self.mailRegistry[dedupeKey] then
        Output:Debug("LEDGER", "Prevented tracking for key: %s", dedupeKey)

        return
    end

    Output:Debug("LEDGER", "Queueing incoming money from mail: %d copper from %s (key=%s)", header.money, header.sender, dedupeKey)

    self.mailRegistry[dedupeKey] = true
    self.mailMoneyQueue[#self.mailMoneyQueue + 1] = {
        sender = header.sender,
        actorUid = header.actorUid,
        amount = header.money,
        opCode = opCode,
        dedupeContext = dedupeKey,
        player = player,
        moneySnapshot = GetMoney()
    }
end

-- Commit taking an item or money from opened mail to the ledger
local function onAutoLootMailItem(self, mailId)
    local header = getMailContext(mailId)
    if not header then
        return
    end

    onTakeInboxMoney(self, mailId, header)

    if header.itemCount > 0 then
        for i = 1, math_min(header.itemCount, attachmentsMaxReceive) do
            onTakeInboxItem(self, mailId, i, header)
        end
    end
end

-- Commit outgoing mail to the ledger
local function onSendMail(self, recipient)
    local player = GBCR.Guild:GetNormalizedPlayerName()
    local actorUid = GBCR.Guild:DetermineUidForGuildMemberName(recipient)

    for i = 1, attachmentsMaxSend do
        local link = GetSendMailItemLink(i)
        if link then
            local _, _, _, count = GetSendMailItem(i)
            appendLedger(self, player, GBCR.Inventory:GetItemKey(link), tonumber(count) or 1, actorUid, ledgerOperations.MAIL_OUT)
        end
    end

    local money = GetSendMailMoney() or 0
    if money > 0 then
        local dedupeContext = string_format("mail_%s_money", tostring(GetServerTime()))
        appendLedger(self, player, nil, money, actorUid, ledgerOperations.MAIL_OUT, dedupeContext)
    end

    Output:Debug("LEDGER", "onSendMail: logged outgoing mail to %s", recipient or "?")
end

-- ================================================================================================
-- Reset the trading state
local function resetTradeState()
    wipe(Ledger.tradeGiving)
    wipe(Ledger.tradeReceiving)
    Ledger.tradeMoney.giving = 0
    Ledger.tradeMoney.receiving = 0
    Ledger.tradePartner = ""
    Ledger.tradePartnerUid = ""
end

-- Record the current trade window state
local function refreshTradeItems()
    wipe(Ledger.tradeGiving)
    wipe(Ledger.tradeReceiving)

    for i = 1, tradeMaxItems do
        local link = GetTradePlayerItemLink(i)
        if link and link ~= "" then
            local _, _, count = GetTradePlayerItemInfo(i)
            Ledger.tradeGiving[#Ledger.tradeGiving + 1] = {
                itemString = GBCR.Inventory:GetItemKey(link),
                count = tonumber(count) or 1
            }
        end

        local targetlink = GetTradeTargetItemLink(i)
        if targetlink and targetlink ~= "" then
            local _, _, count = GetTradeTargetItemInfo(i)
            Ledger.tradeReceiving[#Ledger.tradeReceiving + 1] = {
                itemString = GBCR.Inventory:GetItemKey(targetlink),
                count = tonumber(count) or 1
            }
        end
    end
end

-- Commit a trade to the ledger
local function commitTradeToLedger(self)
    if not GBCR.Guild.weAreGuildBankAlt then
        resetTradeState()

        return
    end

    local player = GBCR.Guild:GetNormalizedPlayerName()
    local actorUid = self.tradePartnerUid

    for _, item in ipairs(self.tradeGiving) do
        appendLedger(self, player, item.itemString, item.count, actorUid, ledgerOperations.TRADE_OUT)
    end

    if self.tradeMoney.giving > 0 then
        appendLedger(self, player, nil, self.tradeMoney.giving, actorUid, ledgerOperations.TRADE_OUT)
    end

    for _, item in ipairs(self.tradeReceiving) do
        appendLedger(self, player, item.itemString, item.count, actorUid, ledgerOperations.TRADE_IN)
    end

    if self.tradeMoney.receiving > 0 then
        appendLedger(self, player, nil, self.tradeMoney.receiving, actorUid, ledgerOperations.TRADE_IN)
    end

    Output:Debug("LEDGER", "commitTradeToLedger: %d given + %d received for %s", #self.tradeGiving, #self.tradeReceiving, player)

    resetTradeState()
end

-- ================================================================================================
-- Commit vendor purchase to the ledger 
local function onBuyMerchantItem(self, index, quantity)
    quantity = tonumber(quantity) or 1
    local link = GetMerchantItemLink(index)
    if not link then
        return
    end

    local player = GBCR.Guild:GetNormalizedPlayerName()
    appendLedger(self, player, GBCR.Inventory:GetItemKey(link), quantity, "", ledgerOperations.VENDOR_BUY)

    local _, _, price = GetMerchantItemInfo(index)
    local cost = (tonumber(price) or 0) * quantity
    if cost > 0 then
        appendLedger(self, player, nil, cost, "", ledgerOperations.VENDOR_BUY)
    end

    Output:Debug("LEDGER", "onBuyMerchantItem: %s x%d (%d copper)", link, quantity, cost)
end

-- Commit vendor sale to the ledger 
local function onSellCursorItem(self)
    local item = GBCR.Events.pendingVendorSellItem
    if not item then
        return
    end

    local player = GBCR.Guild:GetNormalizedPlayerName()
    appendLedger(self, player, item.itemString, item.count, "", ledgerOperations.VENDOR_SELL)

    GBCR.Events.pendingVendorSellItem = nil

    Output:Debug("LEDGER", "onSellCursorItem: %s x%d", item.itemString, item.count)
end

-- Commit item destroy to the ledger 
local function onDeleteCursorItem(self)
    local item = GBCR.Events.pendingCursorItem
    if not item then
        return
    end

    local player = GBCR.Guild:GetNormalizedPlayerName()
    appendLedger(self, player, item.itemString, item.count, "", ledgerOperations.DESTROY_OUT)

    GBCR.Events.pendingCursorItem = nil

    Output:Debug("LEDGER", "onDeleteCursorItem: %s x%d", item.itemString, item.count)
end

-- ================================================================================================
-- Calls a game API that populates client's inbox with messages so that mailbox information can be accessed from anywhere in the world
local function checkInbox()
    CheckInbox()
end

-- ================================================================================================
-- Initiate state tracking
local function init(self)
    self.tradeGiving = {}
    self.tradeReceiving = {}
    self.tradeMoney = {giving = 0, receiving = 0}
    self.tradePartner = ""
    self.tradePartnerUid = ""
    self.mailRegistry = {}
    self.mailItemQueue = {}
    self.mailMoneyQueue = nil
end

-- ================================================================================================
-- Export functions for other modules
Ledger.FormatEntry = formatEntry
Ledger.ExportLedger = exportLedger

Ledger.MergeLedger = mergeLedger
Ledger.AppendLedger = appendLedger

Ledger.OnTakeInboxItem = onTakeInboxItem
Ledger.OnTakeInboxMoney = onTakeInboxMoney
Ledger.OnAutoLootMailItem = onAutoLootMailItem
Ledger.OnSendMail = onSendMail

Ledger.ResetTradeState = resetTradeState
Ledger.RefreshTradeItems = refreshTradeItems
Ledger.CommitTradeToLedger = commitTradeToLedger

Ledger.OnBuyMerchantItem = onBuyMerchantItem
Ledger.OnSellCursorItem = onSellCursorItem
Ledger.OnDeleteCursorItem = onDeleteCursorItem

Ledger.Check = checkInbox

Ledger.Init = init
