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

	-- Scan bank if available
	alt.bank = {
		items = {},
	}
	scanBank(alt.bank.items)

	-- Scan bags
	alt.bags = {
		items = {},
	}
	scanBags(alt.bags.items)

	-- Scan money
	local money = GetMoney()
	alt.money = money

	-- Scan mail inventory if mail was accessed
	GBankClassic_Output:Debug("INVENTORY", "Mail scan for %s (GBankClassic_MailInventory.hasUpdated=%s)", player, tostring(GBankClassic_MailInventory.hasUpdated))
	if GBankClassic_MailInventory.hasUpdated then
		GBankClassic_Output:Debug("INVENTORY", "Starting mail scan for %s", player)
		local mailData = GBankClassic_MailInventory:ScanMailInventory()
		if mailData then
			local itemCount = GBankClassic_Globals:Count(mailData.items)
			local hadPreviousMail = alt.mail ~= nil
			local previousItemCount = 0
			if hadPreviousMail and alt.mail.items then
				previousItemCount = #alt.mail.items
			end
			GBankClassic_Output:Debug("INVENTORY", "Replacing mail data for %s (old=%d items, new=%d items, version=%s)", player, previousItemCount, itemCount, mailData.version)
			alt.mail = mailData
		end
		GBankClassic_Output:Debug("INVENTORY", "Clearing hasUpdated flag after successful scan")
		GBankClassic_MailInventory.hasUpdated = false
	end

	-- Aggregate bank + bags + mail into alt.items
	self:RecalculateAggregatedItems(alt)

	-- Compute hash of the current inventory state
	local currentHash = GBankClassic_DeltaComms:ComputeInventoryHash(alt.items, nil, nil, money)
	local previousHash = alt.inventoryHash
	local currentImprovedInventoryHash = self:ComputeImprovedInventoryHash(alt.items, money)
	local previousImprovedInventoryHash = alt.improvedInventoryHash
	alt.inventoryHash = currentHash
	alt.improvedInventoryHash = currentImprovedInventoryHash

	if currentImprovedInventoryHash ~= previousImprovedInventoryHash then
		alt.version = GetServerTime()
		GBankClassic_Output:Debug("INVENTORY", "Inventory changed for %s, version updated to %d (improvedInventoryHash=%s)", player, alt.version, tostring(currentImprovedInventoryHash))
	else
		GBankClassic_Output:Debug("INVENTORY", "No inventory changes for %s, version unchanged (improvedInventoryHash=%s)", player, tostring(currentImprovedInventoryHash))
	end

	-- Compute hash for current mailbox state
	-- mailHash is computed whenever mail is scanned (even if empty) to track all mail state changes (mailHash is nil when mail was never scanned)
	if alt.mail and alt.mail.items then
		local currentMailHash = GBankClassic_DeltaComms:ComputeInventoryHash(alt.mail.items, nil, nil, nil)
		local previousMailHash = alt.mailHash
		local currentImprovedMailHash = self:ComputeImprovedInventoryHash(alt.mail.items, nil)
		local previousImprovedMailHash = alt.improvedMailHash
		alt.mailHash = currentMailHash
		alt.improvedMailHash = currentImprovedMailHash

		if currentImprovedMailHash ~= previousImprovedMailHash then
			alt.version = GetServerTime()
			GBankClassic_Output:Debug("INVENTORY", "Mail changed for %s, version updated to %s (improvedMailHash=%s)", player, alt.version, tostring(currentMailHash))
		else
			GBankClassic_Output:Debug("INVENTORY", "No mail changes for %s, hash unchanged", player, tostring(currentMailHash))
		end
	else
		-- No mail data structure (mail was never scanned this session)
		-- Keep previous mailHash if it exists to preserve data across sessions
		GBankClassic_Output:Debug("INVENTORY", "Mail not scanned this session for %s, preserving existing mail hash", player)
	end

	-- Write to GBankClassic_Guild.Info for normal use
	if not info.alts then
		info.alts = {}
	end
	info.alts[player] = alt

	-- Save snapshot after scan so next broadcast can compute proper delta
	if info.name then
		GBankClassic_Database:SaveSnapshot(info.name, player, alt)
		GBankClassic_Output:Debug("DELTA", "Saved snapshot for %s after scan (hash=%s)", player, tostring(alt.inventoryHash))
	end

    -- Always share inventory with guild after a scan
    GBankClassic_Guild:Share()
end

--[[
function Bank:HasInventorySpace()
    local total = 0
    for bag = 0, 4 do
        local slots, _ = GetContainerNumFreeSlots(bag)
        total = total + slots
    end

    return total > 0
end

-- Find all slots containing an item by name (case-insensitive)
-- Returns: table of {bag, slot, count, link}
function Bank:FindItemsByName(itemName)
	local results = {}
	if not itemName or itemName == "" then
		return results
	end

	local targetName = string.lower(itemName)

	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		for slot = 1, slots do
			local itemInfo = GetContainerItemInfo(bag, slot)
			if itemInfo and itemInfo.hyperlink then
				local name = GetItemInfo(itemInfo.hyperlink)
				if name and string.lower(name) == targetName then
					table.insert(results, { bag = bag, slot = slot, count = itemInfo.stackCount or 1, link = itemInfo.hyperlink })
				end
			end
		end
	end

	return results
end

-- Count total of named item in bags (0-4)
-- Returns: totalCount, itemsTable
function Bank:CountItemInBags(itemName)
	local items = self:FindItemsByName(itemName)
	local total = 0
	for _, item in ipairs(items) do
		total = total + item.count
	end
    
	return total, items
end
]]--

function Bank:OnUpdateStart()
    self.hasUpdated = true
end

function Bank:OnUpdateStop()
	GBankClassic_Output:Debug("INVENTORY", "OnUpdateStop called, hasUpdated=%s", tostring(self.hasUpdated))
    if self.hasUpdated then
		GBankClassic_Output:Debug("INVENTORY", "Calling scan")
        self:Scan()
		GBankClassic_Output:Debug("INVENTORY", "Scan completed")
		
		-- Trigger UI refresh if inventory window is open
		if GBankClassic_UI_Inventory.isOpen then
			if not GBankClassic_UI_Inventory.currentTab or GBankClassic_UI_Inventory.currentTab == GBankClassic_Guild.player then
				GBankClassic_UI_Inventory:DrawContent()
				GBankClassic_UI_Inventory:RefreshCurrentTab()
			end
		end
		if GBankClassic_UI_Search.isOpen then
			GBankClassic_UI_Search:BuildSearchData()
			GBankClassic_UI_Search:DrawContent()
			GBankClassic_UI_Search.searchField:Fire("OnEnterPressed")
		end
		if GBankClassic_UI_Donations.isOpen then
			GBankClassic_UI_Donations:DrawContent()
		end
	else
		GBankClassic_Output:Debug("INVENTORY", "Skipping scan because hasUpdated is false")
    end
    self.hasUpdated = false
end

-- Recalculate alt.items from existing bank/bags/mail data
function Bank:RecalculateAggregatedItems(alt)
	if not alt then
		return
	end

	local bankItems = {}
	if alt.bank and alt.bank.items then
		local deduped = GBankClassic_Item:Aggregate(alt.bank.items, nil)
		for _, item in pairs(deduped) do
			table.insert(bankItems, item)
		end
		alt.bank.items = bankItems
	end

	local bagItems = {}
	if alt.bags and alt.bags.items then
		local deduped = GBankClassic_Item:Aggregate(alt.bags.items, nil)
		for _, item in pairs(deduped) do
			table.insert(bagItems, item)
		end
		alt.bags.items = bagItems
	end

	local mailItems = {}
	if alt.mail and alt.mail.items then
		local deduped = GBankClassic_Item:Aggregate(alt.mail.items, nil)
		for _, item in pairs(deduped) do
			table.insert(mailItems, item)
		end
		alt.mail.items = mailItems
	end

	-- Aggregate all three sources
	GBankClassic_Output:Debug("INVENTORY", "Before aggregation of items: bank=%d, bags=%d, and mail=%d.", #bankItems, #bagItems, #mailItems)
	local aggregated = GBankClassic_Item:Aggregate(bankItems, bagItems)
	GBankClassic_Output:Debug("INVENTORY", "After aggregating bank + bags: %d unique items.", GBankClassic_Globals:Count(aggregated))
	aggregated = GBankClassic_Item:Aggregate(aggregated, mailItems)
	GBankClassic_Output:Debug("INVENTORY", "After adding mail: %d unique items.", GBankClassic_Globals:Count(aggregated))

	-- Convert table to array format
	alt.items = {}
	for _, item in pairs(aggregated) do
		if item.ID then
			table.insert(alt.items, item)
		end
	end

	GBankClassic_Output:Debug("INVENTORY", "After aggregation of items: bank=%d, bags=%d, mail=%d, total=%d", #bankItems, #bagItems, #mailItems, #alt.items)
end

-- Compute an immproved hash of inventory state to detect changes
-- Considers enchant/suffix for weapons/gear
-- Only updates version timestamps when this hash changes
-- Hash calculations from users with version 2.5.4 or older only consider ID and Count
function Bank:ComputeImprovedInventoryHash(items, money)
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

	return GBankClassic_Core and GBankClassic_Core:Checksum(combined) or 0
end