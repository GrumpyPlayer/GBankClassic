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
    local count = 0
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
                count = count + 1
            end
        end
    end

    return count, items
end

local function scanBags(baginfo)
    local total = 0
    local numslots = 0
    local bagItems = nil

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        local count, items = scanBag(bag, slots)
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
        total = total + count
        numslots = numslots + slots
    end

    for _, v in pairs(bagItems) do
        table.insert(baginfo, v)
    end

    return total, numslots
end

local function scanBank(bankinfo)
    local numslots = NUM_BANKGENERIC_SLOTS
    local total, bankItems = scanBag(BANK_CONTAINER, NUM_BANKGENERIC_SLOTS)

    for bag = 5, 11 do
        local slots = GetContainerNumSlots(bag)
        local count, items = scanBag(bag, slots)
        for k, v in pairs(items) do
            if bankItems[k] then
                local item = bankItems[k]
                bankItems[k] = { ID = item.ID, Count = item.Count + v.Count, Link = item.Link }
            else
                bankItems[k] = v
            end
        end
        total = total + count
        numslots = numslots + slots
    end

    for _, v in pairs(bankItems) do
        table.insert(bankinfo, v)
    end

    return total, numslots
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

	local player = GBankClassic_Guild:GetNormalizedPlayer()
    local isBank = false
    local guildBankAlts = GBankClassic_Guild:GetRosterGuildBankAlts()
	if not guildBankAlts or #guildBankAlts == 0 then
		return
	end

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
	-- Load from aggregate view (info.alts)
	if info.alts and info.alts[player] then
		alt = info.alts[player]
	end

	if isBankAvailable() then
		alt.bank = {
			items = {},
			slots = {},
		}
		local count, slots = scanBank(alt.bank.items)
		alt.bank.slots = { count = count, total = slots }
	end

	alt.bags = {
		items = {},
		slots = {},
	}
	local count, slots = scanBags(alt.bags.items)
	alt.bags.slots = { count = count, total = slots }

	local money = GetMoney()
	alt.money = money

	-- Scan mail inventory if mail was accessed
	GBankClassic_Output:Debug("INVENTORY", "Bank:Scan() for player '%s', hasUpdated=%s", player, tostring(GBankClassic_MailInventory.hasUpdated))

	if GBankClassic_MailInventory.hasUpdated then
		GBankClassic_Output:Debug("INVENTORY", "Starting mail scan for player '%s'", player)

		local mailData = GBankClassic_MailInventory:ScanMailInventory()
		if mailData then
			local itemCount = GBankClassic_Globals:Count(mailData.items)

			-- Check if alt.mail already exists
			local hadPreviousMail = alt.mail ~= nil
			local previousItemCount = 0
			if hadPreviousMail and alt.mail.items then
				previousItemCount = #alt.mail.items
			end

			GBankClassic_Output:Debug("INVENTORY", "Replacing mail data for '%s': old=%d items, new=%d items", player, previousItemCount, itemCount)

			alt.mail = mailData
			GBankClassic_Output:Debug("INVENTORY", "Assigned alt.mail with %d items, version=%s, lastScan=%s", #mailData.items, tostring(mailData.version), tostring(mailData.lastScan))

			-- Verify assignment worked
			if alt.mail then
				GBankClassic_Output:Debug("INVENTORY", "Confirmed: alt.mail exists with %d items", #alt.mail.items)
			else
				GBankClassic_Output:Debug("INVENTORY", "ERROR: alt.mail is nil after assignment!")
			end
		end

		GBankClassic_Output:Debug("INVENTORY", "Clearing hasUpdated flag after successful scan")
		GBankClassic_MailInventory.hasUpdated = false
	end

	-- Aggregate bank + bags + mail into alt.items for sync and display
	local bankItems = (alt.bank and alt.bank.items) or {}
	local bagItems = (alt.bags and alt.bags.items) or {}
	local mailItems = (alt.mail and alt.mail.items) or {}
	-- Log sample counts from source arrays before aggregation
	if #bankItems > 0 then
		local bankSample = {}
		for i = 1, math.min(3, #bankItems) do
			local item = bankItems[i]
			if item then
				table.insert(bankSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
			end
		end
		GBankClassic_Output:Debug("INVENTORY", "  bank.items (first 3): %s", table.concat(bankSample, ", "))
	end
	if #bagItems > 0 then
		local bagSample = {}
		for i = 1, math.min(3, #bagItems) do
			local item = bagItems[i]
			if item then
				table.insert(bagSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
			end
		end
		GBankClassic_Output:Debug("INVENTORY", "  bags.items (first 3): %s", table.concat(bagSample, ", "))
	end
	if #mailItems > 0 then
		local mailSample = {}
		for i = 1, math.min(3, #mailItems) do
			local item = mailItems[i]
			if item then
				table.insert(mailSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
			end
		end
		GBankClassic_Output:Debug("INVENTORY", "  mail.items (first 3): %s", table.concat(mailSample, ", "))
	end

	-- Aggregate all three sources (returns table with composite keys, deduplicates by ID)
	local aggregated = GBankClassic_Item:Aggregate(bankItems, bagItems)
	aggregated = GBankClassic_Item:Aggregate(aggregated, mailItems)

	-- Convert back to array format for storage/sync/display
	alt.items = {}
	for _, item in pairs(aggregated) do
		table.insert(alt.items, item)
	end

	-- Log sample counts after aggregation
	if alt.items and #alt.items > 0 then
		local scanSample = {}
		for i = 1, math.min(5, #alt.items) do
			local item = alt.items[i]
			if item then
				table.insert(scanSample, string.format("%s:%d", item.ID or "?", item.Count or 0))
			end
		end
		GBankClassic_Output:Debug("INVENTORY", "After scan aggregation - First 5 items: %s", table.concat(scanSample, ", "))
	end

	-- Also clean up source arrays to remove any duplicates (in case of corrupted data)
	-- This ensures future scans start fresh
	if alt.bank and alt.bank.items then
		local cleanBank = {}
		local bankAgg = GBankClassic_Item:Aggregate(alt.bank.items, nil)
		for _, item in pairs(bankAgg) do
			table.insert(cleanBank, item)
		end
		alt.bank.items = cleanBank
	end
	if alt.bags and alt.bags.items then
		local cleanBags = {}
		local bagsAgg = GBankClassic_Item:Aggregate(alt.bags.items, nil)
		for _, item in pairs(bagsAgg) do
			table.insert(cleanBags, item)
		end
		alt.bags.items = cleanBags
	end

	-- Only update version if inventory actually changed
	-- Compute a hash of the current inventory state (use aggregated alt.items)
	local currentHash = self:ComputeInventoryHash(alt.items, money)
	local previousHash = alt.inventoryHash

	if currentHash ~= previousHash then
		-- Inventory changed, update version timestamp
		local updatedAt = GetServerTime()
		alt.version = updatedAt
		alt.inventoryUpdatedAt = updatedAt
		alt.inventoryHash = currentHash
		GBankClassic_Output:Debug("INVENTORY", "Inventory changed for %s, version updated to %d (hash: %s)", player, alt.version, tostring(currentHash))
	else
		-- No changes detected, preserve existing version
		GBankClassic_Output:Debug("INVENTORY", "No inventory changes for %s, version unchanged (hash: %s)", player, tostring(currentHash))
		-- Backfill inventoryUpdatedAt if missing
		if not alt.inventoryUpdatedAt and alt.version then
			alt.inventoryUpdatedAt = alt.version
		end
	end

	-- Compute mailHash for mail-specific change detection
	-- This allows receivers to detect when mail data exists and has changed
	-- mailHash is computed whenever mail is scanned (even if empty) to track all mail state changes
	-- nil mailHash = "never scanned mail" vs hash value = "mail scanned" (could be empty or full)
	if alt.mail and alt.mail.items then
		local currentMailHash = self:ComputeInventoryHash(alt.mail.items, nil)
		local previousMailHash = alt.mailHash

		if currentMailHash ~= previousMailHash then
			alt.mailHash = currentMailHash
			GBankClassic_Output:Debug("INVENTORY", "Mail hash updated for %s: %s (was: %s, %d items)", player, tostring(currentMailHash), tostring(previousMailHash), #alt.mail.items)
		else
			-- Ensure mailHash is set even if unchanged (in case it was missing before)
			alt.mailHash = currentMailHash
			GBankClassic_Output:Debug("INVENTORY", "Mail hash unchanged for %s: %s (%d items)", player, tostring(currentMailHash), #alt.mail.items)
		end

	else
		-- No mail data structure (mail was never scanned this session)
		-- Keep previous mailHash if it exists to preserve data across sessions
		GBankClassic_Output:Debug("INVENTORY", "Mail not scanned this session for %s, preserving existing mailHash", player)
	end

	-- Initialize tables if needed
	if not info.alts then
		info.alts = {}
	end

	-- Log what we're about to save
	if alt.mail then
		GBankClassic_Output:Debug("INVENTORY", "alt.mail exists with %d items, type=%s", #alt.mail.items, type(alt.mail))
		-- Handle both old format (number) and new format (table)
		if type(alt.mail.slots) == "table" then
			GBankClassic_Output:Debug("INVENTORY", "alt.mail.slots = table with count=%d", alt.mail.slots.count)
		elseif type(alt.mail.slots) == "number" then
			GBankClassic_Output:Debug("INVENTORY", "alt.mail.slots = %d (old format, migrating)", alt.mail.slots)
			-- Migrate old format to new format
			local oldSlots = alt.mail.slots
			alt.mail.slots = { count = #alt.mail.items, total = oldSlots }
		else
			GBankClassic_Output:Debug("INVENTORY", "alt.mail.slots = nil")
		end
	end

	-- Write to aggregate view (info.alts) for normal use
	info.alts[player] = alt

	if alt.mail then
		GBankClassic_Output:Debug("INVENTORY", "Saved mail to info.alts[%s] (%d items)", player, #alt.mail.items)
	else
		GBankClassic_Output:Debug("INVENTORY", "No mail data to save for %s", player)
	end

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
	else
		GBankClassic_Output:Debug("INVENTORY", "Skipping scan because hasUpdated is false")
    end
    self.hasUpdated = false
end

-- Recalculate alt.items from existing bank/bags/mail data
-- Used to fix aggregation without requiring a full scan
function Bank:RecalculateAggregatedItems(alt)
	if not alt then
		return
	end

	-- First deduplicate source data (bank/bags) in case they have duplicates
	local bankItems = {}
	if alt.bank and alt.bank.items then
		local deduped = GBankClassic_Item:Aggregate(alt.bank.items, nil)
		for _, item in pairs(deduped) do
			table.insert(bankItems, item)
		end
		-- Write deduplicated bank items back to source to fix SV file
		alt.bank.items = bankItems
	end

	local bagItems = {}
	if alt.bags and alt.bags.items then
		local deduped = GBankClassic_Item:Aggregate(alt.bags.items, nil)
		for _, item in pairs(deduped) do
			table.insert(bagItems, item)
		end
		-- Write deduplicated bag items back to source to fix SV file
		alt.bags.items = bagItems
	end

	local mailItems = {}
	if alt.mail and alt.mail.items then
		GBankClassic_Output:Debug("INVENTORY", "Before mail deduplication: %d items.", #alt.mail.items)
		-- Check for duplicates before deduplication
		local mailByID = {}
		for i, item in ipairs(alt.mail.items) do
			if item and item.ID then
				if not mailByID[item.ID] then
					mailByID[item.ID] = {}
				end
				table.insert(mailByID[item.ID], { index = i, Count = item.Count, Link = item.Link })
			end
		end
		for itemID, entries in pairs(mailByID) do
			if #entries > 1 then
				GBankClassic_Output:Debug("INVENTORY", "Before mail deduplication: item ID %d has %d entries.", itemID, #entries)
				for _, entry in ipairs(entries) do
					GBankClassic_Output:Debug("INVENTORY", "  index=%d, count=%d, link=%s", entry.index, entry.Count, entry.Link or "nil")
				end
			end
		end

		-- Mail items are now stored as array (same as bank/bags)
		local deduped = GBankClassic_Item:Aggregate(alt.mail.items, nil)
		for _, item in pairs(deduped) do
			table.insert(mailItems, item)
		end
		GBankClassic_Output:Debug("INVENTORY", "After mail deduplication: %d unique items.", #mailItems)
		-- Write deduplicated mail items back to source to fix SV file
		alt.mail.items = mailItems
	end

	-- Aggregate all three sources
	GBankClassic_Output:Debug("INVENTORY", "Before aggregation of items: bank=%d, bags=%d, and mail=%d.", #bankItems, #bagItems, #mailItems)
	local aggregated = GBankClassic_Item:Aggregate(bankItems, bagItems)
	GBankClassic_Output:Debug("INVENTORY", "After aggregating bank + bags: %d unique items.", GBankClassic_Globals:Count(aggregated))
	aggregated = GBankClassic_Item:Aggregate(aggregated, mailItems)
	GBankClassic_Output:Debug("INVENTORY", "After adding mail: %d unique items.", GBankClassic_Globals:Count(aggregated))

	-- Convert back to array format
	alt.items = {}
	for _, item in pairs(aggregated) do
		if item.ID then
			table.insert(alt.items, item)
		end
	end

	GBankClassic_Output:Debug("INVENTORY", "After aggregation of items: bank=%d, bags=%d, mail=%d, total=%d", #bankItems, #bagItems, #mailItems, #alt.items)
end

-- Compute a hash of inventory state to detect actual changes
-- Only updates version timestamps when this hash changes
function Bank:ComputeInventoryHash(items, money)
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
				-- Use ID + Count for hash (link variations don't affect inventory state)
				-- This ensures hash matches even if links aren't reconstructed yet
				local itemCount = item.Count or 1
				local itemIdentity = tostring(item.ID)

				-- For weapons/armor, include link key to catch suffix differences
				if item.Link and GBankClassic_Item and GBankClassic_Item.NeedsLink then
					if GBankClassic_Item:NeedsLink(item.Link) then
						local linkKey = GBankClassic_Item:GetItemKey(item.Link)
						if linkKey and linkKey ~= "" then
							itemIdentity = linkKey
						end
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