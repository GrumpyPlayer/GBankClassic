GBankClassic_Bank = GBankClassic_Bank or {}

local Bank = GBankClassic_Bank

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("GetContainerNumFreeSlots", "GetContainerItemInfo", "GetContainerNumSlots", "GetMoney", "GetServerTime")
local GetContainerNumFreeSlots = upvalues.GetContainerNumFreeSlots
local GetContainerItemInfo = upvalues.GetContainerItemInfo
local GetContainerNumSlots = upvalues.GetContainerNumSlots
local GetMoney = upvalues.GetMoney
local GetServerTime = upvalues.GetServerTime
local upvalues = Globals.GetUpvalues("BANK_CONTAINER", "NUM_BANKGENERIC_SLOTS")
local BANK_CONTAINER = upvalues.BANK_CONTAINER
local NUM_BANKGENERIC_SLOTS = upvalues.NUM_BANKGENERIC_SLOTS

local function isBankAvailable()
    local _, bagType = GetContainerNumFreeSlots(BANK_CONTAINER)

    return bagType ~= nil
end

local function hasUpdated()
    return Bank.hasUpdated
end

local function scanBag(bag, slots)
    local items = {}

    for slot = 1, slots do
        local itemInfo = GetContainerItemInfo(bag, slot)
        if itemInfo then
            local itemCount = itemInfo.stackCount
            local itemLink = itemInfo.hyperlink
            local itemID = itemInfo.itemID
            if itemLink then
                local key = itemID .. itemLink
                if items[key] then
                    local item = items[key]
                    items[key] = { ID = item.ID, Count = item.Count + itemCount, Link = item.Link }
                else
                    items[key] = { ID = itemID, Count = itemCount, Link = itemLink }
                end
            end
        end
    end

    return items
end

local function scanBags(bagTable)
    local bagItems = nil

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        local items = scanBag(bag, slots)
        if bagItems == nil then
            bagItems = items
        else
            for k, v in pairs(items) do
                if bagItems[k] then
                    local item = bagItems[k]
                    bagItems[k] = { ID = item.ID, Count = item.Count + v.Count, Link = item.Link }
                else
                    bagItems[k] = v
                end
            end
        end
    end

    for _, v in pairs(bagItems) do
        table.insert(bagTable, v)
    end
end

local function scanBank(bankTable)
	if isBankAvailable() then
		local bankItems = scanBag(BANK_CONTAINER, NUM_BANKGENERIC_SLOTS)

		for bag = 5, 11 do
			local slots = GetContainerNumSlots(bag)
			local items = scanBag(bag, slots)
			for k, v in pairs(items) do
				if bankItems[k] then
					local item = bankItems[k]
					bankItems[k] = { ID = item.ID, Count = item.Count + v.Count, Link = item.Link }
				else
					bankItems[k] = v
				end
			end
		end

		for _, v in pairs(bankItems) do
			table.insert(bankTable, v)
		end
	end
end

function Bank:Scan()
    if Bank.eventsRegistered then
        if not hasUpdated() then
            return
        end
    end

    local info = GBankClassic_Guild.Info
    if not info then
        return
    end

    local guildBankAlts = GBankClassic_Guild:GetRosterGuildBankAlts()
	if not guildBankAlts or #guildBankAlts == 0 then
		return
	end

	local player = GBankClassic_Guild:GetNormalizedPlayer()
    local isBank = false
	for i = 1, #guildBankAlts do
        local guildBankAltName = guildBankAlts[i]
        local normV = GBankClassic_Guild:NormalizeName(guildBankAltName) or guildBankAltName
        if normV == player then
            isBank = true
            break
        end
    end
	if not isBank then
		return
	end

    if not GBankClassic_Options:GetBankEnabled() then
		return
	end

	local alt = {}
	if info.alts and info.alts[player] then
		alt = info.alts[player]
	end

    -- Initialize persistent storage if needed
	if not alt.cache then alt.cache = {} end
    if not alt.cache.bank then alt.cache.bank = { items = {} } end
    if not alt.cache.bags then alt.cache.bags = { items = {} } end
    if not alt.cache.mail then alt.cache.mail = { items = {} } end

    -- Scan bank if available, otherwise keep existing data
    if isBankAvailable() then
        local bankData = {}
        scanBank(bankData)
        alt.cache.bank.items = bankData
    end

	-- Scan bags (always available)
	local bagData = {}
	scanBags(bagData)
    alt.cache.bags.items = bagData

	-- Scan money (always available)
	local money = GetMoney()
	alt.money = money

	-- Scan mail inventory if mail was accessed
	local mailData = nil
	GBankClassic_Output:Debug("INVENTORY", "Mail scan for %s (GBankClassic_MailInventory.hasUpdated=%s)", player, tostring(GBankClassic_MailInventory.hasUpdated))
	if GBankClassic_MailInventory.hasUpdated then
		GBankClassic_Output:Debug("INVENTORY", "Starting mail scan for %s", player)
		mailData = GBankClassic_MailInventory:ScanMailInventory()
        if mailData then
            alt.cache.mail.items = mailData
        end
		GBankClassic_Output:Debug("INVENTORY", "Clearing hasUpdated flag after successful scan")
		GBankClassic_MailInventory.hasUpdated = false
	end

	-- Aggregate bank + bags + mail into alt.items
	self:RecalculateAggregatedItems(alt.cache.bank.items, alt.cache.bags.items, alt.cache.mail.items, alt)

	-- Compute hash of the current inventory state
	local currentItemsHash = self:ComputeItemsHash(alt.items, money)
	local previousItemsHash = alt.itemsHash
	-- Store the hash if there's at least 1 item
	if #alt.items > 0 then
		alt.itemsHash = currentItemsHash
	else
		alt.itemsHash = nil
	end

	if currentItemsHash ~= previousItemsHash then
		alt.version = GetServerTime()
		GBankClassic_Output:Debug("INVENTORY", "Inventory changed for %s, version updated to %d (itemsHash=%s)", player, alt.version, tostring(currentItemsHash))
	else
		GBankClassic_Output:Debug("INVENTORY", "No inventory changes for %s, version unchanged (itemsHash=%s)", player, tostring(currentItemsHash))
	end

	-- Write to GBankClassic_Guild.Info for normal use
	if not info.alts then
		info.alts = {}
	end
	info.alts[player] = alt

    -- Always share inventory with guild after a scan
    GBankClassic_Guild:Share()
end

function Bank:OnUpdateStart()
    self.hasUpdated = true
end

function Bank:OnUpdateStop()
	GBankClassic_Output:Debug("INVENTORY", "OnUpdateStop called, hasUpdated=%s", tostring(self.hasUpdated))
    if self.hasUpdated then
		GBankClassic_Output:Debug("INVENTORY", "Calling scan")
        self:Scan()
		GBankClassic_Output:Debug("INVENTORY", "Scan completed")
		GBankClassic_UI:RequestRefresh()
	else
		GBankClassic_Output:Debug("INVENTORY", "Skipping scan because hasUpdated is false")
    end
    self.hasUpdated = false
end

-- Recalculate aggregate alt.items from bank, bags, mail, and money
function Bank:RecalculateAggregatedItems(bankData, bagData, mailData, alt)
	local bankItems = {}
	if bankData then
		local deduped = GBankClassic_Item:Aggregate(bankData, nil)
		for _, item in pairs(deduped) do
			table.insert(bankItems, item)
		end
	end

	local bagItems = {}
	if bagData then
		local deduped = GBankClassic_Item:Aggregate(bagData, nil)
		for _, item in pairs(deduped) do
			table.insert(bagItems, item)
		end
	end

	local mailItems = {}
	if mailData then
		local deduped = GBankClassic_Item:Aggregate(mailData, nil)
		for _, item in pairs(deduped) do
			table.insert(mailItems, item)
		end
	end

	-- Aggregate all three sources
	GBankClassic_Output:Debug("INVENTORY", "Before aggregation of items: bank=%d, bags=%d, and mail=%d", #bankItems, #bagItems, #mailItems)
	local aggregated = GBankClassic_Item:Aggregate(bankItems, bagItems)
	GBankClassic_Output:Debug("INVENTORY", "After aggregating bank + bags: %d unique items", GBankClassic_Globals:Count(aggregated))
	aggregated = GBankClassic_Item:Aggregate(aggregated, mailItems)
	GBankClassic_Output:Debug("INVENTORY", "After adding mail: %d unique items", GBankClassic_Globals:Count(aggregated))

	-- Convert table to array format
	alt.items = {}
	for _, item in pairs(aggregated) do
		if item.ID then
			table.insert(alt.items, item)
		end
	end

	GBankClassic_Output:Debug("INVENTORY", "After aggregation of items: bank=%d, bags=%d, mail=%d, total=%d", #bankItems, #bagItems, #mailItems, #alt.items)
end

-- Compute an immproved hash of inventory state to detect changes considering enchant/suffix for weapons/gear
function Bank:ComputeItemsHash(items, money)
	local parts = {}
	table.insert(parts, tostring(money))

	-- Hash aggregated items directly
	local function hashItems(itemsArray)
		if not itemsArray or type(itemsArray) ~= "table" then
			return ""
		end

		local sorted = {}
		for _, item in ipairs(itemsArray) do
			if item and item.ID and item.ID > 0 then
				local itemCount = item.Count or 1
				local itemIdentity = tostring(item.ID)

				-- For weapons/armor, include link key to catch suffix differences
				if item.Link and GBankClassic_Item:NeedsLink(item.Link) then
					local linkKey = GBankClassic_Item:GetImprovedItemKey(item.Link)
					if linkKey and linkKey ~= "" then
						itemIdentity = linkKey
					end
				end

				table.insert(sorted, string.format("%s:%d", itemIdentity, itemCount))
			end
		end
		table.sort(sorted)

		return table.concat(sorted, ",")
	end

	table.insert(parts, "I:" .. hashItems(items))
	local combined = table.concat(parts, "|")

	-- Inline checksum
	if type(combined) ~= "string" then
		return 0
	end

	local sum = 0
	local len = #combined
	for i = 1, len do
		local byte = string.byte(combined, i)
		sum = (sum * 31 + byte) % 2147483647
	end

	-- Include length to catch truncation
	sum = (sum * 31 + len) % 2147483647

	return sum
end